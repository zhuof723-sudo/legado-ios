import UIKit
import SwiftUI

// MARK: - 容器协议

/// 点击/链接回调的打包，由 SwiftUI 层注入。
struct BookPageTapHandlers {
    var onZoneTap: ((ReaderTapAction) -> Void)?
    var onLinkTap: ((ReaderLinkTarget) -> Void)?
}

/// 三种翻页容器的公共接口。SwiftUI 只跟这个协议对话，不关心内部
/// 是 UIPageViewController 还是瞬时切换。
protocol BookPagedContainer: AnyObject {
    var pages: [ReaderPage] { get set }
    var config: ReaderConfig { get }
    var currentIndex: Int { get set }
    /// 文字区偏移与尺寸：边距调整后由 SwiftUI 层同步进来，
    /// 后续新建的页面视图（updatePages / 翻页预取）都按最新值创建。
    var contentOffset: CGPoint { get set }
    var contentSize: CGSize { get set }
    var onUserPageChange: ((Int) -> Void)? { get set }
    var tapHandlers: BookPageTapHandlers { get set }

    func goToPage(_ index: Int, animated: Bool)
    func updatePages(_ newPages: [ReaderPage], keepIndex: Int)
    func refreshAppearance()
}

extension BookPagedContainer {
    /// 包装一页为独立 UIViewController（UIPageViewController 数据源的单元）。
    func makeViewController(at index: Int) -> UIViewController {
        guard pages.indices.contains(index) else { return UIViewController() }
        let pageView = BookPageContentView(
            page: pages[index],
            config: config,
            contentOffset: contentOffset,
            contentSize: contentSize
        )
        pageView.onZoneTap = { [weak self] action in self?.tapHandlers.onZoneTap?(action) }
        pageView.onLinkTap = { [weak self] target in self?.tapHandlers.onLinkTap?(target) }
        return IndexedPageViewController(index: index, pageView: pageView)
    }
}

/// UIPageViewController 的页面包装：index 供翻页完成后同步页码。
final class IndexedPageViewController: UIViewController {
    let pageIndex: Int
    let pageView: BookPageContentView

    init(index: Int, pageView: BookPageContentView) {
        self.pageIndex = index
        self.pageView = pageView
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = pageView.backgroundColor
        pageView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(pageView)
        NSLayoutConstraint.activate([
            pageView.topAnchor.constraint(equalTo: view.topAnchor),
            pageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pageView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
}

// MARK: - 仿真翻页 / 平移（UIPageViewController 同源实现）

/// Apple Books 式仿真卷页 = UIPageViewController(.pageCurl)，
/// 平移 = UIPageViewController(.scroll)。两种动画共用同一份
/// 数据源/委托代码，只在 transitionStyle 上区分。
final class PagedFlowController: UIPageViewController,
                                 UIPageViewControllerDataSource,
                                 UIPageViewControllerDelegate,
                                 BookPagedContainer {
    var pages: [ReaderPage] = []
    let config: ReaderConfig
    var currentIndex: Int = 0
    var onUserPageChange: ((Int) -> Void)?
    var tapHandlers = BookPageTapHandlers()
    var contentOffset: CGPoint
    var contentSize: CGSize

    init(
        pages: [ReaderPage],
        config: ReaderConfig,
        initialIndex: Int,
        transitionStyle: UIPageViewController.TransitionStyle,
        contentOffset: CGPoint,
        contentSize: CGSize
    ) {
        self.pages = pages
        self.config = config
        self.currentIndex = initialIndex
        self.contentOffset = contentOffset
        self.contentSize = contentSize
        super.init(transitionStyle: transitionStyle, navigationOrientation: .horizontal, options: nil)
        // 单页模式：翻卷时纸张背面留白，下一页从底下露出（Apple Books 竖屏同款）。
        isDoubleSided = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        dataSource = self
        delegate = self
        view.backgroundColor = UIColor(config.currentTheme.background)
        if !pages.isEmpty {
            let initial = min(max(currentIndex, 0), pages.count - 1)
            setViewControllers([pageController(at: initial)], direction: .forward, animated: false)
            currentIndex = initial
        }
    }

    private func pageController(at index: Int) -> UIViewController {
        makeViewController(at: index)
    }

    // MARK: BookPagedContainer

    func goToPage(_ index: Int, animated: Bool) {
        guard pages.indices.contains(index), index != currentIndex else { return }
        let direction: UIPageViewController.NavigationDirection = index > currentIndex ? .forward : .reverse
        setViewControllers(
            [pageController(at: index)],
            direction: direction,
            animated: animated
        ) { [weak self] _ in
            self?.finishTransition(to: index)
        }
    }

    func updatePages(_ newPages: [ReaderPage], keepIndex: Int) {
        pages = newPages
        let safe = min(max(keepIndex, 0), max(newPages.count - 1, 0))
        currentIndex = safe
        if !newPages.isEmpty {
            setViewControllers([pageController(at: safe)], direction: .forward, animated: false)
        }
    }

    func refreshAppearance() {
        view.backgroundColor = UIColor(config.currentTheme.background)
        viewControllers?.compactMap { $0 as? IndexedPageViewController }
            .forEach { $0.pageView.refreshAppearance() }
    }

    private func finishTransition(to index: Int) {
        guard currentIndex != index else { return }
        currentIndex = index
        onUserPageChange?(index)
    }

    // MARK: UIPageViewControllerDataSource

    func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerBefore viewController: UIViewController
    ) -> UIViewController? {
        guard let indexed = viewController as? IndexedPageViewController else { return nil }
        let index = indexed.pageIndex - 1
        return index >= 0 ? pageController(at: index) : nil
    }

    func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerAfter viewController: UIViewController
    ) -> UIViewController? {
        guard let indexed = viewController as? IndexedPageViewController else { return nil }
        let index = indexed.pageIndex + 1
        return index < pages.count ? pageController(at: index) : nil
    }

    // MARK: UIPageViewControllerDelegate

    func pageViewController(
        _ pageViewController: UIPageViewController,
        didFinishAnimating finished: Bool,
        previousViewControllers: [UIViewController],
        transitionCompleted completed: Bool
    ) {
        guard completed,
              let indexed = pageViewController.viewControllers?.first as? IndexedPageViewController else { return }
        finishTransition(to: indexed.pageIndex)
    }
}

// MARK: - 无动画（瞬时切换）

/// 无动画模式：点击/滑动直接换页，零过渡。切页仍然是异步闭环——
/// 手势只发出意图（zone 回调），真正的页码更新由 SwiftUI 驱动回来，
/// 与仿真/平移走同一条状态通道。
final class InstantPageController: UIViewController, BookPagedContainer {
    var pages: [ReaderPage] = []
    let config: ReaderConfig
    var currentIndex: Int = 0
    var onUserPageChange: ((Int) -> Void)?
    var tapHandlers = BookPageTapHandlers()

    var contentOffset: CGPoint
    var contentSize: CGSize
    private var currentPageView: BookPageContentView?

    init(
        pages: [ReaderPage],
        config: ReaderConfig,
        initialIndex: Int,
        contentOffset: CGPoint,
        contentSize: CGSize
    ) {
        self.pages = pages
        self.config = config
        self.currentIndex = initialIndex
        self.contentOffset = contentOffset
        self.contentSize = contentSize
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(config.currentTheme.background)

        let swipeLeft = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipeLeft))
        swipeLeft.direction = .left
        let swipeRight = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipeRight))
        swipeRight.direction = .right
        view.addGestureRecognizer(swipeLeft)
        view.addGestureRecognizer(swipeRight)

        showPage(at: currentIndex)
    }

    @objc private func handleSwipeLeft() {
        tapHandlers.onZoneTap?(.nextPage)
    }

    @objc private func handleSwipeRight() {
        tapHandlers.onZoneTap?(.previousPage)
    }

    private func showPage(at index: Int) {
        guard pages.indices.contains(index) else { return }
        currentPageView?.removeFromSuperview()
        let pageView = BookPageContentView(
            page: pages[index],
            config: config,
            contentOffset: contentOffset,
            contentSize: contentSize
        )
        pageView.onZoneTap = { [weak self] action in self?.tapHandlers.onZoneTap?(action) }
        pageView.onLinkTap = { [weak self] target in self?.tapHandlers.onLinkTap?(target) }
        pageView.frame = view.bounds
        pageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(pageView)
        currentPageView = pageView
        currentIndex = index
    }

    // MARK: BookPagedContainer

    func goToPage(_ index: Int, animated: Bool) {
        guard index != currentIndex else { return }
        showPage(at: index)
    }

    func updatePages(_ newPages: [ReaderPage], keepIndex: Int) {
        pages = newPages
        let safe = min(max(keepIndex, 0), max(newPages.count - 1, 0))
        showPage(at: safe)
    }

    func refreshAppearance() {
        view.backgroundColor = UIColor(config.currentTheme.background)
        currentPageView?.refreshAppearance()
    }
}

// MARK: - SwiftUI 包装

/// 阅读页容器：对外只暴露 pages / 当前页码 / 两类点击回调。
/// 翻页模式变化时由 SwiftUI 的 .id 重建容器；主题变化走 refreshAppearance 热刷新。
struct BookPagedReaderRepresentable: UIViewControllerRepresentable {
    let pages: [ReaderPage]
    let config: ReaderConfig
    @Binding var pageIndex: Int
    /// 文字区偏移与尺寸（阅读边距），分页时与渲染时必须一致。
    let contentOffset: CGPoint
    let contentSize: CGSize
    var onZoneTap: (ReaderTapAction) -> Void
    var onLinkTap: (ReaderLinkTarget) -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        let container: BookPagedContainer
        switch config.currentTurnStyle {
        case .curl:
            container = PagedFlowController(
                pages: pages,
                config: config,
                initialIndex: pageIndex,
                transitionStyle: .pageCurl,
                contentOffset: contentOffset,
                contentSize: contentSize
            )
        case .slide:
            container = PagedFlowController(
                pages: pages,
                config: config,
                initialIndex: pageIndex,
                transitionStyle: .scroll,
                contentOffset: contentOffset,
                contentSize: contentSize
            )
        case .none:
            container = InstantPageController(
                pages: pages,
                config: config,
                initialIndex: pageIndex,
                contentOffset: contentOffset,
                contentSize: contentSize
            )
        }
        applyCallbacks(to: container)
        return container as! UIViewController
    }

    private func applyCallbacks(to container: BookPagedContainer) {
        container.tapHandlers = BookPageTapHandlers(
            onZoneTap: onZoneTap,
            onLinkTap: onLinkTap
        )
        container.onUserPageChange = { index in
            DispatchQueue.main.async {
                guard pageIndex != index else { return }
                pageIndex = index
            }
        }
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        guard let container = uiViewController as? BookPagedContainer else { return }

        // 回调可能捕获了新的闭包，每轮同步。
        applyCallbacks(to: container)

        // 文字区几何（边距）可能变了：同步给容器，后续新建页面用最新值。
        container.contentOffset = contentOffset
        container.contentSize = contentSize

        // 主题/夜间切换：热刷新背景与文字颜色，不重排。
        container.refreshAppearance()

        if container.pages != pages {
            container.updatePages(pages, keepIndex: pageIndex)
        } else if container.currentIndex != pageIndex {
            container.goToPage(pageIndex, animated: config.currentTurnStyle != .none)
        }
    }
}
