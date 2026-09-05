import SwiftUI
import SwiftData
import UIKit
import AVFoundation
import Combine

/// 阅读器：CoreText 精确分页 + 覆盖/滑动翻页 + 液态玻璃控制层（对照设计稿）
struct ReaderView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: ReaderViewModel
    let bookUrl: String
    let bookName: String
    let bookAuthor: String
    let coverURL: String

    @AppStorage("reader.fontSize") private var fontSize: Double = 18
    @AppStorage("reader.lineSpacingIndex") private var lineSpacingIndex: Int = 1
    @AppStorage("reader.bgIndex") private var bgIndex: Int = 1
    @AppStorage("reader.nightMode") private var nightMode = false
    @AppStorage("reader.eyeCare") private var eyeCare = false
    @AppStorage("reader.turnMode") private var turnMode: Int = 2      // 0覆盖 1仿真 2滑动
    @AppStorage("reader.autoRead") private var autoRead = false
    @AppStorage("reader.immersiveDarkInitialized") private var immersiveDarkInitialized = false

    @StateObject private var speech = ReaderSpeechController()
    @State private var pages: [String] = []
    @State private var paginatedForKey = ""
    @State private var pageIndex = 0
    @State private var pendingJumpToLastPage = false
    @State private var showControls = false
    @State private var showSettings = false
    @State private var showToc = false
    @State private var showChapterSearch = false

    private let hPadding: CGFloat = 20
    private let tPadding: CGFloat = 56
    private let bPadding: CGFloat = 44

    init(
        viewModel: ReaderViewModel,
        bookUrl: String,
        bookName: String,
        bookAuthor: String = "",
        coverURL: String = ""
    ) {
        self.viewModel = viewModel
        self.bookUrl = bookUrl
        self.bookName = bookName
        self.bookAuthor = bookAuthor
        self.coverURL = coverURL
    }

    private var lineSpacingValue: CGFloat {
        [CGFloat(4), CGFloat(8), CGFloat(14)][min(max(lineSpacingIndex, 0), 2)]
    }

    private var effectiveIndex: Int { nightMode ? 4 : min(max(bgIndex, 0), 3) }
    private var bgColor: Color { Theme.readerBackgrounds[effectiveIndex] }
    private var textColor: Color { Theme.readerTextColors[effectiveIndex] }

    var body: some View {
        GeometryReader { geo in
            let pageSize = CGSize(
                width: max(geo.size.width - hPadding * 2, 1),
                height: max(geo.size.height - tPadding - bPadding, 1)
            )
            let paginationKey = "\(viewModel.currentContent.hashValue)|\(Int(fontSize))|\(lineSpacingIndex)|"
                + "\(Int(pageSize.width))x\(Int(pageSize.height))|\(viewModel.currentIndex)"

            ZStack {
                bgColor.ignoresSafeArea()
                content(pageSize: pageSize, key: paginationKey)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) { showControls.toggle() }
                    }
                if eyeCare {
                    Color.yellow.opacity(0.07).ignoresSafeArea().allowsHitTesting(false)
                }
                if turnMode != 2 {
                    readerTapOverlay
                }
                chrome
                    .zIndex(20)
            }
            .task(id: paginationKey) {
                await repaginate(content: viewModel.currentContent, pageSize: pageSize, key: paginationKey)
            }
            .task(id: autoRead) {
                guard autoRead else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 3_500_000_000)
                    if Task.isCancelled { break }
                    goNextPage()
                }
            }
        }
        .statusBarHidden(false)
        .preferredColorScheme(nightMode ? .dark : .light)
        .toolbar(.hidden, for: .tabBar)
        .onAppear {
            if !immersiveDarkInitialized {
                nightMode = true
                immersiveDarkInitialized = true
            }
        }
        .onDisappear { speech.stop() }
        .sheet(isPresented: $showSettings) {
            ReaderSettingsPanel().presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showToc) {
            TocSheet(bookUrl: bookUrl, viewModel: viewModel).presentationDetents([.large])
        }
        .sheet(isPresented: $showChapterSearch) {
            ReaderChapterSearchView(text: viewModel.currentContent)
                .presentationDetents([.medium, .large])
        }
        .onChange(of: viewModel.currentIndex) {
            saveProgress()
            if speech.isSpeaking, pageIndex < pages.count { speech.speak(pages[pageIndex]) }
        }
        .onChange(of: pageIndex) {
            if speech.isSpeaking, pageIndex < pages.count { speech.speak(pages[pageIndex]) }
        }
    }

    // MARK: - 正文

    @ViewBuilder
    private func content(pageSize: CGSize, key: String) -> some View {
        if paginatedForKey == key, pageIndex < pages.count {
            if turnMode == 2 {
                TabView(selection: $pageIndex) {
                    ForEach(pages.indices, id: \.self) { i in
                        pageText(pages[i], pageSize: pageSize).tag(i)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .ignoresSafeArea(edges: .bottom)
            } else {
                pageText(pages[pageIndex], pageSize: pageSize)
                    .id("\(pageIndex)-\(key)")
                    .animation(.easeInOut(duration: 0.22), value: pageIndex)
            }
        } else if viewModel.isLoadingContent || viewModel.isLoadingToc {
            ProgressView()
        } else if let err = viewModel.errorMessage {
            Text(err).foregroundStyle(.red).multilineTextAlignment(.center).padding()
        } else {
            ProgressView()
        }
    }

    private func pageText(_ s: String, pageSize: CGSize) -> some View {
        Text(s)
            .font(.system(size: fontSize))
            .lineSpacing(lineSpacingValue)
            .foregroundStyle(textColor)
            .frame(width: pageSize.width, height: pageSize.height, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .top)
    }

    // 独立控制层点击区域：滑动翻页模式也必须能点击中间显示工具栏
    private var readerTapOverlay: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                Rectangle().fill(.clear)
                    .contentShape(Rectangle())
                    .onTapGesture { if turnMode != 2 { goPrevPage() } }
                    .allowsHitTesting(turnMode != 2)
                Rectangle().fill(.clear)
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { showControls.toggle() } }
                Rectangle().fill(.clear)
                    .contentShape(Rectangle())
                    .onTapGesture { if turnMode != 2 { goNextPage() } }
                    .allowsHitTesting(turnMode != 2)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .zIndex(10)
        .allowsHitTesting(true)
    }


    // MARK: - 沉浸式控制层

    private var chrome: some View {
        VStack(spacing: 0) {
            if showControls { immersiveHeader }
            Spacer(minLength: 0)
            if showControls {
                immersiveBottomPanel
            } else if !pages.isEmpty {
                HStack {
                    Text("\(pageIndex + 1)/\(pages.count)")
                    Spacer()
                    Text(viewModel.currentChapterTitle ?? "")
                        .lineLimit(1)
                }
                .font(.caption2)
                .foregroundStyle(textColor.opacity(0.55))
                .padding(.horizontal, 18)
                .padding(.bottom, 8)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .animation(.easeInOut(duration: 0.2), value: showControls)
    }

    private var immersiveHeader: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(Color.black.opacity(0.32), in: Circle())
                    .glassCard(Circle(), interactive: true)
                    .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 0.8))
            }
            Spacer(minLength: 0)
            VStack(spacing: 2) {
                Text(bookName)
                    .font(.headline)
                    .lineLimit(1)
                if !bookAuthor.isEmpty {
                    Text(bookAuthor).font(.caption).foregroundStyle(.white.opacity(0.65)).lineLimit(1)
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .frame(height: 52)
            .background(Color.black.opacity(0.32), in: Capsule())
            .glassCard(Capsule(), interactive: true)
            .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 0.8))
            Spacer(minLength: 0)
            SmartCover(url: coverURL, title: bookName)
                .frame(width: 52, height: 52)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 1))
        }
        .environment(\.colorScheme, .dark)
    }

    private var immersiveBottomPanel: some View {
        VStack(spacing: 16) {
            HStack {
                Text(viewModel.currentChapterTitle ?? bookName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                Text("\(pageIndex + 1) / \(max(pages.count, 1))")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.72))
            }

            HStack(spacing: 12) {
                Button { goPrevPage() } label: {
                    Image(systemName: "chevron.left").frame(width: 34, height: 34)
                }
                Slider(
                    value: Binding(
                        get: { Double(min(pageIndex, max(pages.count - 1, 0))) },
                        set: { pageIndex = Int($0.rounded()) }
                    ),
                    in: 0...Double(max(pages.count - 1, 1))
                )
                .tint(Theme.accent)
                Button { goNextPage() } label: {
                    Image(systemName: "chevron.right").frame(width: 34, height: 34)
                }
            }

            HStack {
                immersiveToolButton("list.bullet", "目录") { showToc = true }
                Spacer()
                immersiveToolButton(speech.isSpeaking ? "speaker.wave.2.fill" : "speaker.wave.2", "听书") {
                    guard pageIndex < pages.count else { return }
                    speech.toggle(pages[pageIndex])
                }
                Spacer()
                immersiveToolButton("magnifyingglass", "搜索") { showChapterSearch = true }
                Spacer()
                immersiveToolButton("textformat.size", "大小") { showSettings = true }
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .background(Color.black.opacity(0.48), in: RoundedRectangle(cornerRadius: 22))
        .glassCard(RoundedRectangle(cornerRadius: 22), interactive: true)
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.white.opacity(0.12), lineWidth: 0.8))
        .shadow(color: .black.opacity(0.34), radius: 22, y: 9)
        .environment(\.colorScheme, .dark)
    }

    private func immersiveToolButton(_ icon: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 21, weight: .medium))
                Text(label).font(.caption)
            }
            .frame(minWidth: 48, minHeight: 48)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 翻页

    private func goNextPage() {
        guard !pages.isEmpty else { return }
        if pageIndex + 1 < pages.count {
            pageIndex += 1
        } else {
            Task { await viewModel.nextChapter() }
        }
    }

    private func goPrevPage() {
        if pageIndex > 0 {
            pageIndex -= 1
        } else {
            pendingJumpToLastPage = true
            Task { await viewModel.prevChapter() }
        }
    }

    // MARK: - 分页

    private func repaginate(content: String, pageSize: CGSize, key: String) async {
        guard !content.isEmpty else {
            pages = []
            paginatedForKey = key
            return
        }
        let fSize = fontSize
        let lSpacing = lineSpacingValue
        let result = await Task.detached(priority: .userInitiated) {
            TextPaginator.paginate(
                text: content,
                font: UIFont.systemFont(ofSize: fSize),
                lineSpacing: lSpacing,
                pageSize: pageSize
            )
        }.value

        guard content == viewModel.currentContent else { return }
        pages = result
        if pendingJumpToLastPage {
            pageIndex = max(0, result.count - 1)
            pendingJumpToLastPage = false
        } else if pageIndex >= result.count {
            pageIndex = 0
        }
        paginatedForKey = key
    }

    // MARK: - 进度保存

    private func saveProgress() {
        let url = bookUrl
        let descriptor = FetchDescriptor<ShelfBook>(predicate: #Predicate { $0.bookUrl == url })
        if let book = try? context.fetch(descriptor).first {
            book.lastReadChapterIndex = viewModel.currentIndex
            book.lastReadChapterTitle = viewModel.currentChapterTitle
            book.lastReadAt = Date()
            book.totalChapters = viewModel.chapters.count
            try? context.save()
        }
    }
}


@MainActor
private final class ReaderSpeechController: ObservableObject {
    @Published private(set) var isSpeaking = false
    private let synthesizer = AVSpeechSynthesizer()

    func toggle(_ text: String) {
        if isSpeaking {
            stop()
        } else {
            speak(text)
        }
    }

    func speak(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
        isSpeaking = true
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
    }
}

private struct ReaderChapterSearchView: View {
    @Environment(\.dismiss) private var dismiss
    let text: String
    @State private var query = ""

    private var matches: [String] {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return [] }
        return text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.localizedCaseInsensitiveContains(keyword) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ContentUnavailableView("章内搜索", systemImage: "magnifyingglass",
                                           description: Text("输入关键字查找当前章节内容"))
                } else if matches.isEmpty {
                    ContentUnavailableView("没有找到结果", systemImage: "magnifyingglass",
                                           description: Text("当前章节不包含“\(query)”"))
                } else {
                    List(Array(matches.enumerated()), id: \.offset) { _, line in
                        Text(line).font(.body).textSelection(.enabled)
                    }
                    .listStyle(.plain)
                }
            }
            .searchable(text: $query, prompt: "搜索当前章节")
            .navigationTitle("章内搜索")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}
