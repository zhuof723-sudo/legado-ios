import SwiftUI
import SwiftData
import UIKit
import AVFoundation

/// 阅读器：UIPageViewController 稳定翻页 + CoreText 分页 + 液态玻璃控制层
struct ReaderView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: ReaderViewModel
    let bookUrl: String
    let bookName: String
    let bookAuthor: String
    let coverURL: String

    @StateObject private var config = ReaderConfig.shared
    @StateObject private var speech = ReaderSpeechController()
    @AppStorage("reader.autoRead") private var autoRead = false

    @State private var pages: [String] = []
    @State private var paginatedForKey = ""
    @State private var pageIndex = 0
    @State private var pendingJumpToLastPage = false
    @State private var showControls = false
    @State private var showSettings = false
    @State private var showToc = false
    @State private var showChapterSearch = false

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

    private var bgColor: Color { config.currentTheme.background }
    private var textColor: Color { config.currentTheme.textColor }

    var body: some View {
        GeometryReader { geo in
            let pageSize = CGSize(
                width: max(geo.size.width - config.paddingH * 2, 1),
                height: max(geo.size.height - config.paddingTop - config.paddingBottom, 1)
            )
            let paginationKey = "\(viewModel.currentContent.hashValue)|\(Int(config.fontSize))|\(config.lineSpacing)|\(config.bold)|\(config.paragraphSpacing)|\(config.paragraphIndent)|"
                + "\(Int(pageSize.width))x\(Int(pageSize.height))|\(viewModel.currentIndex)"

            ZStack {
                bgColor.ignoresSafeArea()

                if paginatedForKey == paginationKey, !pages.isEmpty {
                    PageReaderViewRepresentable(
                        pages: pages,
                        config: config,
                        currentIndex: $pageIndex
                    )
                    .padding(.horizontal, config.paddingH)
                    .padding(.top, config.paddingTop)
                    .padding(.bottom, config.paddingBottom)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) { showControls.toggle() }
                    }
                } else if viewModel.isLoadingContent || viewModel.isLoadingToc {
                    ProgressView()
                } else if let err = viewModel.errorMessage {
                    Text(err).foregroundStyle(.red).multilineTextAlignment(.center).padding()
                } else {
                    ProgressView()
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
                    try? await Task.sleep(nanoseconds: UInt64(config.autoReadSpeed * 1_000_000_000))
                    if Task.isCancelled { break }
                    goNextPage()
                }
            }
        }
        .statusBarHidden(false)
        .preferredColorScheme(config.nightMode ? .dark : .light)
        .toolbar(.hidden, for: .tabBar)
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

    // MARK: - 沉浸式控制层

    private var chrome: some View {
        VStack(spacing: 0) {
            if showControls {
                immersiveHeader
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity)
                    ))
            }
            Spacer(minLength: 0)
            if showControls {
                immersiveBottomPanel
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .move(edge: .bottom).combined(with: .opacity)
                    ))
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
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .animation(.spring(response: 0.35, dampingFraction: 0.85, blendDuration: 0.1), value: showControls)
    }

    private var immersiveHeader: some View {
        HStack(spacing: 10) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .glassCircle()
            }
            Spacer(minLength: 0)
            VStack(spacing: 1) {
                Text(bookName)
                    .font(.subheadline.bold())
                    .lineLimit(1)
                if !bookAuthor.isEmpty {
                    Text(bookAuthor).font(.caption2).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(Color.black.opacity(0.22), in: Capsule())
            .glassCard(Capsule(), interactive: true)
            Spacer(minLength: 0)
            SmartCover(url: coverURL, title: bookName)
                .frame(width: 36, height: 36)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 0.8))
        }
        .environment(\.colorScheme, .dark)
    }

    private var immersiveBottomPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(viewModel.currentChapterTitle ?? bookName)
                    .font(.caption).foregroundStyle(.white).lineLimit(1)
                Spacer()
                Text("\(pageIndex + 1) / \(max(pages.count, 1))")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
            HStack(spacing: 8) {
                Button { goPrevPage() } label: {
                    Image(systemName: "chevron.left").frame(width: 28, height: 28)
                }
                .tint(.white.opacity(0.9))
                Slider(
                    value: Binding(
                        get: { Double(min(pageIndex, max(pages.count - 1, 0))) },
                        set: { pageIndex = Int($0.rounded()) }
                    ),
                    in: 0...Double(max(pages.count - 1, 1))
                )
                .tint(Theme.accent)
                Button { goNextPage() } label: {
                    Image(systemName: "chevron.right").frame(width: 28, height: 28)
                }
                .tint(.white.opacity(0.9))
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
                immersiveToolButton("textformat.size", "排版") { showSettings = true }
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.36), in: RoundedRectangle(cornerRadius: 18))
        .glassCard(RoundedRectangle(cornerRadius: 18), interactive: true)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.1), lineWidth: 0.6))
        .shadow(color: .black.opacity(0.3), radius: 14, y: 6)
        .environment(\.colorScheme, .dark)
    }

    private func immersiveToolButton(_ icon: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 16, weight: .medium))
                Text(label).font(.caption2)
            }
            .frame(minWidth: 40, minHeight: 40)
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
        let font = config.uiFont
        let lSpacing = config.lineSpacing
        let pSpacing = config.paragraphSpacing
        let indent = config.indentPixels

        let result = await Task.detached(priority: .userInitiated) {
            TextPaginator.paginate(
                text: content,
                font: font,
                lineSpacing: lSpacing,
                paragraphSpacing: pSpacing,
                firstLineIndent: indent,
                alignment: config.coreTextAlignment,
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
