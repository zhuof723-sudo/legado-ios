import SwiftUI
import SwiftData
import UIKit

/// 阅读器：CoreText 精确分页 + 覆盖/滑动翻页 + 液态玻璃控制层（对照设计稿）
struct ReaderView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: ReaderViewModel
    let bookUrl: String
    let bookName: String

    @AppStorage("reader.fontSize") private var fontSize: Double = 18
    @AppStorage("reader.lineSpacingIndex") private var lineSpacingIndex: Int = 1
    @AppStorage("reader.bgIndex") private var bgIndex: Int = 1
    @AppStorage("reader.nightMode") private var nightMode = false
    @AppStorage("reader.eyeCare") private var eyeCare = false
    @AppStorage("reader.turnMode") private var turnMode: Int = 2      // 0覆盖 1仿真 2滑动
    @AppStorage("reader.autoRead") private var autoRead = false

    @State private var pages: [String] = []
    @State private var paginatedForKey = ""
    @State private var pageIndex = 0
    @State private var pendingJumpToLastPage = false
    @State private var showControls = false
    @State private var showSettings = false
    @State private var showToc = false
    @State private var pageSizeState: CGSize = .zero

    private let hPadding: CGFloat = 20
    private let tPadding: CGFloat = 56
    private let bPadding: CGFloat = 44

    init(viewModel: ReaderViewModel, bookUrl: String, bookName: String) {
        self.viewModel = viewModel
        self.bookUrl = bookUrl
        self.bookName = bookName
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
                if eyeCare {
                    Color.yellow.opacity(0.07).ignoresSafeArea().allowsHitTesting(false)
                }
                if turnMode != 2 {
                    tapZones(screenWidth: geo.size.width)
                }
                chrome
            }
            .onAppear { pageSizeState = pageSize }
            .task(id: paginationKey) {
                pageSizeState = pageSize
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
        .statusBarHidden(!showControls)
        // 无论从书架、搜索、历史还是详情页进入，都隐藏根 TabBar
        .toolbar(.hidden, for: .tabBar)
        .sheet(isPresented: $showSettings) {
            ReaderSettingsPanel().presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showToc) {
            TocSheet(bookUrl: bookUrl, viewModel: viewModel).presentationDetents([.large])
        }
        .onChange(of: viewModel.currentIndex) { saveProgress() }
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
                .overlay(alignment: .bottom) {
                    if showControls { bottomBar }
                }
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

    // MARK: - 点击分区

    private func tapZones(screenWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            Color.clear
                .onTapGesture { if turnMode != 2 { goPrevPage() } }
                .allowsHitTesting(turnMode != 2)
            Color.clear
                .onTapGesture { withAnimation { showControls.toggle() } }
            Color.clear
                .onTapGesture { if turnMode != 2 { goNextPage() } }
                .allowsHitTesting(turnMode != 2)
        }
        .contentShape(Rectangle())
    }

    // MARK: - 控制层（液态玻璃）

    private var chrome: some View {
        VStack(spacing: 0) {
            if showControls { topBar }
            Spacer(minLength: 0)
            if showControls {
                bottomBar
            } else if !pages.isEmpty {
                Text("\(pageIndex + 1) / \(pages.count)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 10)
            }
        }
        .padding(.horizontal, 12)
        .animation(.easeInOut(duration: 0.2), value: showControls)
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.white.opacity(0.7)))
            }
            Text(viewModel.currentChapterTitle ?? bookName)
                .font(.subheadline.bold())
                .lineLimit(1)
            Spacer()
        }
        .padding(10)
        .glassCard(RoundedRectangle(cornerRadius: 16))
    }

    private var bottomBar: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(viewModel.currentChapterTitle ?? bookName)
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Slider(
                value: Binding(
                    get: { Double(min(pageIndex, max(pages.count - 1, 0))) },
                    set: { pageIndex = Int($0) }
                ),
                in: 0...Double(max(pages.count - 1, 1))
            )
            .tint(Theme.accent)

            HStack {
                toolButton("list.bullet", "目录") { showToc = true }
                toolButton(nightMode ? "sun.max" : "moon", nightMode ? "日间" : "夜间") {
                    nightMode.toggle()
                }
                toolButton(autoRead ? "pause.circle" : "play.circle", "自动") {
                    autoRead.toggle()
                }
                toolButton("textformat.size", "字号") { showSettings = true }
                Spacer()
                Text("\(pageIndex + 1)/\(pages.count)").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .glassCard(RoundedRectangle(cornerRadius: 20))
    }

    private func toolButton(_ icon: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 18, weight: .medium))
                Text(label).font(.caption2)
            }
            .foregroundStyle(.primary.opacity(0.8))
            .frame(width: 52, height: 46)
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
