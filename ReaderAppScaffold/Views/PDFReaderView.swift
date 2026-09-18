import SwiftUI
import UIKit
import AVFoundation

// MARK: - PDF 单页视图

/// 一页 PDF：UIImageView 承载后台渲染的位图，主题背景色随配置刷新。
final class PDFPageViewController: UIViewController {
    let pageIndex: Int
    private let viewModel: PDFReaderViewModel
    private let imageView = UIImageView()
    private var requestedSize: CGSize = .zero
    private var themeBackground: UIColor = .white
    /// 整页点击回调（位置 + 页面宽度）
    var onOutsideTap: ((CGPoint, CGFloat) -> Void)?

    init(pageIndex: Int, viewModel: PDFReaderViewModel, background: UIColor) {
        self.pageIndex = pageIndex
        self.viewModel = viewModel
        self.themeBackground = background
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = themeBackground

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.isUserInteractionEnabled = false
        view.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: view.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let size = view.bounds.size
        guard size.width > 1, size.height > 1, size != requestedSize else { return }
        requestedSize = size
        let page = pageIndex
        viewModel.image(for: page, targetSize: size) { [weak self] renderedPage, image in
            guard let self, renderedPage == self.pageIndex else { return }
            self.imageView.image = image
        }
    }

    func applyTheme(background: UIColor) {
        themeBackground = background
        view.backgroundColor = background
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else { return }
        let location = gesture.location(in: view)
        onOutsideTap?(location, view.bounds.width)
    }
}

// MARK: - PDF 翻页容器（UIPageViewController 卷页）

struct PDFPageControllerView: UIViewControllerRepresentable {
    let viewModel: PDFReaderViewModel
    var themeBackground: UIColor
    var onPageChanged: (Int) -> Void
    var onOutsideTap: ((CGPoint, CGFloat) -> Void)

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIPageViewController {
        let pvc = UIPageViewController(
            transitionStyle: .pageCurl,
            navigationOrientation: .horizontal,
            options: nil
        )
        pvc.dataSource = context.coordinator
        pvc.delegate = context.coordinator
        context.coordinator.parent = self
        if viewModel.pageCount > 0 {
            let target = min(viewModel.currentPage, viewModel.pageCount - 1)
            pvc.setViewControllers(
                [context.coordinator.makePage(target)],
                direction: .forward,
                animated: false
            )
        }
        return pvc
    }

    func updateUIViewController(_ pvc: UIPageViewController, context: Context) {
        context.coordinator.parent = self
        // 主题背景热刷新：改色不重建页面。
        for case let page as PDFPageViewController in pvc.viewControllers ?? [] {
            page.applyTheme(background: themeBackground)
        }
        let target = min(max(viewModel.currentPage, 0), max(viewModel.pageCount - 1, 0))
        if let visible = pvc.viewControllers?.first as? PDFPageViewController,
           visible.pageIndex != target {
            pvc.setViewControllers(
                [context.coordinator.makePage(target)],
                direction: target > visible.pageIndex ? .forward : .reverse,
                animated: true
            )
        }
    }

    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        var parent: PDFPageControllerView

        init(_ parent: PDFPageControllerView) {
            self.parent = parent
        }

        func makePage(_ index: Int) -> PDFPageViewController {
            let page = PDFPageViewController(
                pageIndex: index,
                viewModel: parent.viewModel,
                background: parent.themeBackground
            )
            page.onOutsideTap = { [weak self] location, width in
                self?.parent.onOutsideTap(location, width)
            }
            return page
        }

        func pageViewController(
            _ pageViewController: UIPageViewController,
            viewControllerBefore viewController: UIViewController
        ) -> UIViewController? {
            guard let page = viewController as? PDFPageViewController, page.pageIndex > 0 else { return nil }
            return makePage(page.pageIndex - 1)
        }

        func pageViewController(
            _ pageViewController: UIPageViewController,
            viewControllerAfter viewController: UIViewController
        ) -> UIViewController? {
            guard let page = viewController as? PDFPageViewController,
                  page.pageIndex + 1 < parent.viewModel.pageCount else { return nil }
            return makePage(page.pageIndex + 1)
        }

        func pageViewController(
            _ pageViewController: UIPageViewController,
            didFinishAnimating finished: Bool,
            previousViewControllers: [UIViewController],
            transitionCompleted completed: Bool
        ) {
            guard completed,
                  let visible = pageViewController.viewControllers?.first as? PDFPageViewController else { return }
            parent.viewModel.goToPage(visible.pageIndex)
            parent.onPageChanged(visible.pageIndex)
        }
    }
}

// MARK: - PDF 阅读器（SwiftUI 外壳）

/// PDF 阅读器：PDFKit 按页渲染 + UIPageViewController 卷页，
/// 控制层复用阅读器控制层（顶栏/底栏/进度线/书签/TTS）。
struct PDFReaderView: View {
    @Environment(\.dismiss) private var dismiss
    let book: PDFBook

    @StateObject private var viewModel: PDFReaderViewModel
    @ObservedObject private var prefs = ReadingPreferences.shared
    @StateObject private var speech = SpeechController()

    @State private var showControls = false
    @State private var showSettings = false
    @State private var showToc = false
    @State private var pageIndex = 0
    @State private var isCurrentPageBookmarked = false

    init(book: PDFBook) {
        self.book = book
        _viewModel = StateObject(wrappedValue: PDFReaderViewModel(book: book))
    }

    private var bookUrl: String { "pdf://\(book.id)" }
    private var textColor: Color { prefs.currentTheme.textColor }
    private var backgroundColor: UIColor { UIColor(prefs.currentTheme.background) }

    private var progress: Double {
        guard viewModel.pageCount > 1 else { return 0 }
        return Double(min(pageIndex + 1, viewModel.pageCount)) / Double(viewModel.pageCount)
    }

    var body: some View {
        ZStack {
            prefs.currentTheme.background.ignoresSafeArea()

            if let error = viewModel.errorMessage {
                VStack(spacing: 14) {
                    Image(systemName: "doc.richtext").font(.system(size: 44)).foregroundStyle(.red)
                    Text(error).foregroundStyle(.red).multilineTextAlignment(.center)
                }
                .padding()
            } else {
                PDFPageControllerView(
                    viewModel: viewModel,
                    themeBackground: backgroundColor,
                    onPageChanged: { page in
                        pageIndex = page
                    },
                    onOutsideTap: { location, width in
                        handlePageTap(x: location.x, width: width)
                    }
                )
                .ignoresSafeArea(.container, edges: .all)
            }

            chrome
                .zIndex(20)
        }
        .overlay(alignment: .bottom) {
            ProgressHairline(progress: progress, accent: prefs.currentAccent)
        }
        .statusBarHidden(!showControls)
        .preferredColorScheme(prefs.nightMode ? .dark : .light)
        .toolbar(.hidden, for: .tabBar)
        .onDisappear { speech.stop() }
        .sheet(isPresented: $showSettings) {
            AppearancePanel().presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showToc) {
            ContentsSheet(
                bookKey: bookUrl,
                entries: (0..<max(viewModel.pageCount, 1)).map {
                    ContentsSheet.Entry(index: $0, name: "第 \($0 + 1) 页")
                },
                currentIndex: pageIndex,
                onSelectChapter: { index in
                    viewModel.goToPage(index)
                },
                onSelectBookmark: { bookmark in
                    viewModel.goToPage(bookmark.pageIndex)
                }
            )
            .presentationDetents([.large])
        }
        .onChange(of: pageIndex) { _, _ in
            refreshBookmarkState()
            if speech.isSpeaking, let text = viewModel.currentPageText {
                speech.speak(text)
            }
        }
        .onAppear {
            if viewModel.pageCount > 0 {
                pageIndex = min(viewModel.currentPage, viewModel.pageCount - 1)
            }
            refreshBookmarkState()
        }
    }

    // MARK: - 点击分区（复用 Apple Books 热区）

    private func handlePageTap(x: CGFloat, width: CGFloat) {
        switch TapZones.classify(x: x, width: width) {
        case .previousPage:
            goPrevPage()
        case .nextPage:
            goNextPage()
        case .toggleControls:
            withAnimation(.easeInOut(duration: 0.2)) { showControls.toggle() }
        }
    }

    private func goPrevPage() {
        guard viewModel.currentPage > 0 else {
            withAnimation(.easeInOut(duration: 0.2)) { showControls.toggle() }
            return
        }
        viewModel.goToPage(viewModel.currentPage - 1)
        pageIndex = viewModel.currentPage
    }

    private func goNextPage() {
        guard viewModel.currentPage + 1 < viewModel.pageCount else {
            withAnimation(.easeInOut(duration: 0.2)) { showControls.toggle() }
            return
        }
        viewModel.goToPage(viewModel.currentPage + 1)
        pageIndex = viewModel.currentPage
    }

    // MARK: - 书签

    private var bookmarkIdentity: BookBookmark {
        BookBookmark(
            bookUrl: bookUrl,
            chapterIndex: pageIndex,
            pageIndex: pageIndex,
            label: "\(book.name) · 第 \(pageIndex + 1) 页",
            createdAt: Date()
        )
    }

    private func refreshBookmarkState() {
        let id = bookmarkIdentity
        isCurrentPageBookmarked = BookmarkStore.all(for: bookUrl).contains { $0.id == id.id }
    }

    private func toggleBookmark() {
        let bookmark = bookmarkIdentity
        if isCurrentPageBookmarked {
            BookmarkStore.remove(bookmark)
        } else {
            BookmarkStore.add(bookmark)
        }
        isCurrentPageBookmarked.toggle()
    }

    // MARK: - 控制层

    private var chrome: some View {
        VStack(spacing: 0) {
            if showControls {
                LiquidGlassContainer(spacing: 12) {
                    ReadingTopBar(
                        title: book.name,
                        accent: textColor,
                        isBookmarked: isCurrentPageBookmarked,
                        showSearch: false,
                        onBack: { dismiss() },
                        onTitle: { showToc = true },
                        onSearch: {},
                        onBookmark: { toggleBookmark() }
                    )
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity),
                    removal: .move(edge: .top).combined(with: .opacity)
                ))
            }
            Spacer(minLength: 0)
            if showControls {
                LiquidGlassContainer(spacing: 14) {
                    ReadingBottomBar(
                        pageText: "第 \(pageIndex + 1) 页 / 共 \(max(viewModel.pageCount, 1)) 页",
                        accent: textColor,
                        isSpeaking: speech.isSpeaking,
                        onContents: { showToc = true },
                        onTts: {
                            speech.toggle(viewModel.currentPageText ?? "")
                        },
                        onAppearance: { showSettings = true }
                    )
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .move(edge: .bottom).combined(with: .opacity)
                ))
            } else {
                Text("\(pageIndex + 1) / \(max(viewModel.pageCount, 1))")
                    .font(.caption2)
                    .foregroundStyle(textColor.opacity(0.45))
                    .padding(.bottom, 10)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .animation(.spring(response: 0.35, dampingFraction: 0.85, blendDuration: 0.1), value: showControls)
    }
}