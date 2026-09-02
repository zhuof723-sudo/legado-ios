import SwiftUI
import SwiftData

/// 真正的"翻页"阅读器：用 `TextPaginator` (CoreText) 把当前章节按屏幕尺寸/字号/行距
/// 精确切成一页一页，点击左侧30%=上一页、右侧30%=下一页、中间40%=呼出/收起菜单，
/// 也支持左右滑动。翻到本章最后一页再往后翻会自动接下一章(反之接上一章)。
///
/// 分页是纯 CPU 计算，字号/行距/屏幕尺寸/章节内容任一变化都会在 `.task(id:)` 里
/// 用 `Task.detached` 重新算一遍（避免大章节卡主线程），算完再切回主线程更新UI。
public struct ReaderView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: ReaderViewModel
    let bookUrl: String
    let bookName: String

    @AppStorage("reader.fontSize") private var fontSize: Double = 18
    @AppStorage("reader.lineSpacing") private var lineSpacing: Double = 8

    @State private var pages: [String] = []
    @State private var paginatedForKey: String = ""
    @State private var pageIndex = 0
    @State private var pendingJumpToLastPage = false
    @State private var showControls = false
    @State private var showSettings = false

    private let horizontalPadding: CGFloat = 20
    private let topPadding: CGFloat = 56
    private let bottomPadding: CGFloat = 40

    public init(viewModel: ReaderViewModel, bookUrl: String, bookName: String) {
        self.viewModel = viewModel
        self.bookUrl = bookUrl
        self.bookName = bookName
    }

    public var body: some View {
        GeometryReader { geo in
            let pageSize = CGSize(
                width: max(geo.size.width - horizontalPadding * 2, 1),
                height: max(geo.size.height - topPadding - bottomPadding, 1)
            )
            // 内容/字号/行距/尺寸/章节 任一变化，这个key就会变，从而触发下面的.task重新分页
            let paginationKey = "\(viewModel.currentContent.hashValue)|\(fontSize)|\(lineSpacing)|"
                + "\(Int(pageSize.width))x\(Int(pageSize.height))|\(viewModel.currentIndex)"

            ZStack {
                Color(.systemBackground).ignoresSafeArea()

                Group {
                    if paginatedForKey == paginationKey, pageIndex < pages.count {
                        Text(pages[pageIndex])
                            .font(.system(size: fontSize))
                            .lineSpacing(lineSpacing)
                            .frame(width: pageSize.width, height: pageSize.height, alignment: .topLeading)
                    } else if viewModel.isLoadingContent || viewModel.isLoadingToc {
                        ProgressView()
                    } else if let err = viewModel.errorMessage {
                        Text(err).foregroundStyle(.red).multilineTextAlignment(.center).padding()
                    } else {
                        ProgressView()
                    }
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.top, topPadding)
                .padding(.bottom, bottomPadding)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onEnded { value in handleGesture(value, screenWidth: geo.size.width) }
                )

                VStack(spacing: 0) {
                    if showControls { topBar }
                    Spacer(minLength: 0)
                    if showControls {
                        bottomBar
                    } else if !pages.isEmpty {
                        pageIndicator
                    }
                }
            }
            .task(id: paginationKey) {
                await repaginate(content: viewModel.currentContent, pageSize: pageSize, key: paginationKey)
            }
        }
        .navigationBarHidden(true)
        .statusBarHidden(!showControls)
        .popover(isPresented: $showSettings) { settingsPopover }
        .onChange(of: viewModel.currentIndex) { saveProgress() }
    }

    // MARK: - 手势：左1/3上一页，右1/3下一页，中间呼出菜单；滑动距离够大按滑动方向翻页

    private func handleGesture(_ value: DragGesture.Value, screenWidth: CGFloat) {
        let dx = value.translation.width
        if abs(dx) > 60 {
            if dx < 0 { goNextPage() } else { goPrevPage() }
            return
        }
        let x = value.location.x
        if x < screenWidth * 0.3 {
            goPrevPage()
        } else if x > screenWidth * 0.7 {
            goNextPage()
        } else {
            withAnimation { showControls.toggle() }
        }
    }

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

    // MARK: - 分页计算

    private func repaginate(content: String, pageSize: CGSize, key: String) async {
        guard !content.isEmpty else {
            pages = []
            paginatedForKey = key
            return
        }
        let fSize = fontSize
        let lSpacing = lineSpacing
        let result = await Task.detached(priority: .userInitiated) {
            TextPaginator.paginate(
                text: content,
                font: UIFont.systemFont(ofSize: fSize),
                lineSpacing: lSpacing,
                pageSize: pageSize
            )
        }.value

        guard content == viewModel.currentContent else { return } // 章节又变了，这次结果作废

        pages = result
        if pendingJumpToLastPage {
            pageIndex = max(0, result.count - 1)
            pendingJumpToLastPage = false
        } else {
            pageIndex = 0
        }
        paginatedForKey = key
    }

    // MARK: - 控件

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: { Image(systemName: "chevron.left") }
            Text(viewModel.currentChapterTitle ?? bookName)
                .font(.subheadline).lineLimit(1)
            Spacer()
        }
        .padding()
        .background(.thinMaterial)
    }

    private var bottomBar: some View {
        VStack(spacing: 12) {
            HStack {
                Button {
                    Task { await viewModel.prevChapter() }
                } label: { Label("上一章", systemImage: "chevron.left") }
                .disabled(viewModel.currentIndex <= 0)

                Spacer()

                Button { showSettings = true } label: { Image(systemName: "textformat.size") }

                Spacer()

                Button {
                    Task { await viewModel.nextChapter() }
                } label: { Label("下一章", systemImage: "chevron.right") }
                .disabled(viewModel.currentIndex + 1 >= viewModel.chapters.count)
            }
            pageIndicator
        }
        .padding()
        .background(.thinMaterial)
    }

    private var pageIndicator: some View {
        Text(pages.isEmpty ? " " : "\(pageIndex + 1) / \(pages.count)")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.bottom, 8)
    }

    private var settingsPopover: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("字号: \(Int(fontSize))")
            Slider(value: $fontSize, in: 12...32, step: 1)
            Text("行距: \(Int(lineSpacing))")
            Slider(value: $lineSpacing, in: 0...20, step: 1)
        }
        .padding()
        .frame(width: 260)
    }

    private func saveProgress() {
        let url = bookUrl
        let descriptor = FetchDescriptor<ShelfBook>(predicate: #Predicate { $0.bookUrl == url })
        if let book = try? context.fetch(descriptor).first {
            book.lastReadChapterIndex = viewModel.currentIndex
            book.lastReadChapterTitle = viewModel.currentChapterTitle
            book.lastReadAt = Date()
            try? context.save()
        }
    }
}
