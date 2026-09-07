import SwiftUI
import UIKit

// MARK: - 单页内容视图

final class PageContentView: UIView, UITextViewDelegate {
    let text: String
    let config: ReaderConfig
    /// 是否启用段评按钮
    var reviewEnabled: Bool = false {
        didSet { updateAttributedText() }
    }
    /// 点击评论按钮的回调（参数：段落索引）
    var onReviewTap: ((Int) -> Void)?
    /// 各段落的评论数（用于显示在评论按钮上）
    var reviewCounts: [Int: Int] = [:] {
        didSet { updateAttributedText() }
    }
    private let textView = UITextView()

    init(text: String, config: ReaderConfig) {
        self.text = text
        self.config = config
        super.init(frame: .zero)
        setupTextView()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setupTextView() {
        backgroundColor = .clear
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.backgroundColor = .clear
        textView.isEditable = false
        textView.isScrollEnabled = false
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.showsVerticalScrollIndicator = false
        textView.showsHorizontalScrollIndicator = false
        textView.delegate = self
        textView.isUserInteractionEnabled = true
        textView.linkTextAttributes = [
            .foregroundColor: UIColor.systemGray,
            .underlineColor: UIColor.clear
        ]

        addSubview(textView)
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: topAnchor),
            textView.leadingAnchor.constraint(equalTo: leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        updateAttributedText()
    }

    /// 更新文本（根据 reviewEnabled 决定是否添加评论链接）
    private func updateAttributedText() {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = config.lineSpacing
        paragraphStyle.paragraphSpacing = config.paragraphSpacing
        paragraphStyle.lineBreakMode = .byWordWrapping
        paragraphStyle.alignment = config.coreTextAlignment
        paragraphStyle.firstLineHeadIndent = config.indentPixels

        let attributes: [NSAttributedString.Key: Any] = [
            .font: config.uiFont,
            .foregroundColor: UIColor(config.currentTheme.textColor),
            .paragraphStyle: paragraphStyle
        ]

        if reviewEnabled {
            // 启用段评：在每段末尾添加评论链接（NSLink，比 NSTextAttachment 更可靠）
            textView.attributedText = ReviewLinkHelper.attachReviewLinks(
                to: text,
                attributes: attributes,
                reviewCounts: reviewCounts
            )
        } else {
            textView.attributedText = NSAttributedString(string: text, attributes: attributes)
        }
    }

    // MARK: - UITextViewDelegate

    func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
        // 处理评论链接点击
        if let paragraphIndex = ReviewLinkHelper.paragraphIndex(from: URL) {
            onReviewTap?(paragraphIndex)
            return false
        }
        return true
    }
}

// MARK: - 翻页容器协议

protocol PageReaderContainer: AnyObject {
    var pages: [String] { get set }
    var config: ReaderConfig { get }
    var currentIndex: Int { get set }
    var onPageChanged: ((Int) -> Void)? { get set }
    /// 是否启用段评按钮
    var reviewEnabled: Bool { get set }
    /// 点击评论按钮的回调
    var onReviewTap: ((Int) -> Void)? { get set }
    /// 各段落的评论数
    var reviewCounts: [Int: Int] { get set }
    func goToPage(_ index: Int, animated: Bool)
    func updatePages(_ newPages: [String], keepIndex: Int)
}

// MARK: - 水平滑动翻页（UIScrollView + pagingEnabled，最流畅）

final class HorizontalSlideReader: UIViewController, PageReaderContainer, UIScrollViewDelegate {
    var pages: [String] = []
    let config: ReaderConfig
    var currentIndex: Int = 0
    var onPageChanged: ((Int) -> Void)?
    var reviewEnabled: Bool = false
    var onReviewTap: ((Int) -> Void)?
    var reviewCounts: [Int: Int] = [:]

    private let scrollView = UIScrollView()
    private let stackView = UIStackView()
    private var pageViews: [PageContentView] = []
    private var isProgrammaticScroll = false
    private var needsInitialOffset = true
    private var lastBoundsSize: CGSize = .zero
    private var pendingAnimatedIndex: Int?

    init(pages: [String], config: ReaderConfig, initialIndex: Int) {
        self.pages = pages
        self.config = config
        self.currentIndex = initialIndex
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        setupScrollView()
        reloadPages()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let size = scrollView.bounds.size
        guard size.width > 0, size.height > 0 else { return }

        // 只在首次布局或旋转/尺寸变化时校准位置。布局过程中不能持续重置
        // contentOffset，否则用户拖拽时会被抢回当前页，表现为翻页卡顿或跳回。
        if needsInitialOffset || lastBoundsSize != size {
            let targetIndex = pendingAnimatedIndex ?? currentIndex
            let safeIndex = min(max(targetIndex, 0), max(pages.count - 1, 0))
            isProgrammaticScroll = true
            scrollView.setContentOffset(
                CGPoint(x: CGFloat(safeIndex) * size.width, y: 0),
                animated: false
            )
            isProgrammaticScroll = false
            needsInitialOffset = false
            lastBoundsSize = size
        }
    }

    private func setupScrollView() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.delegate = self
        scrollView.isPagingEnabled = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = true
        scrollView.alwaysBounceVertical = false
        scrollView.bounces = true
        scrollView.scrollsToTop = false
        scrollView.contentInset = .zero
        scrollView.contentInsetAdjustmentBehavior = .never

        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.spacing = 0
        stackView.alignment = .fill
        // 每个页面有明确的宽度约束，使用 fill 避免 fillEqually 与宽度约束冲突。
        stackView.distribution = .fill

        view.addSubview(scrollView)
        scrollView.addSubview(stackView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stackView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            stackView.heightAnchor.constraint(equalTo: scrollView.heightAnchor)
        ])
    }

    private func reloadPages() {
        stackView.arrangedSubviews.forEach {
            stackView.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        pageViews.removeAll()
        pendingAnimatedIndex = nil
        needsInitialOffset = true
        lastBoundsSize = .zero

        for text in pages {
            let pageView = PageContentView(text: text, config: config)
            pageView.reviewEnabled = reviewEnabled
            pageView.onReviewTap = onReviewTap
            pageView.reviewCounts = reviewCounts
            pageView.translatesAutoresizingMaskIntoConstraints = false
            stackView.addArrangedSubview(pageView)
            pageView.widthAnchor.constraint(equalTo: scrollView.widthAnchor).isActive = true
            pageViews.append(pageView)
        }

        view.setNeedsLayout()
        view.layoutIfNeeded()

        let safeIndex = min(max(currentIndex, 0), max(pages.count - 1, 0))
        currentIndex = safeIndex
        if scrollView.bounds.width > 0 {
            isProgrammaticScroll = true
            scrollView.setContentOffset(
                CGPoint(x: CGFloat(safeIndex) * scrollView.bounds.width, y: 0),
                animated: false
            )
            isProgrammaticScroll = false
            needsInitialOffset = false
            lastBoundsSize = scrollView.bounds.size
        }
    }

    func updatePages(_ newPages: [String], keepIndex: Int) {
        pages = newPages
        let safeIndex = min(max(keepIndex, 0), max(newPages.count - 1, 0))
        currentIndex = safeIndex
        reloadPages()
    }

    func goToPage(_ index: Int, animated: Bool) {
        guard index >= 0, index < pages.count else { return }
        guard scrollView.bounds.width > 0 else {
            currentIndex = index
            pendingAnimatedIndex = nil
            return
        }
        guard index != currentIndex || abs(scrollView.contentOffset.x - CGFloat(index) * scrollView.bounds.width) > 1 else {
            return
        }

        currentIndex = index
        pendingAnimatedIndex = animated ? index : nil
        isProgrammaticScroll = true
        let targetX = CGFloat(index) * scrollView.bounds.width
        scrollView.setContentOffset(CGPoint(x: targetX, y: 0), animated: animated)
        if !animated {
            isProgrammaticScroll = false
        }
    }

    // MARK: - UIScrollViewDelegate

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        isProgrammaticScroll = false
        pendingAnimatedIndex = nil
        guard !pages.isEmpty else { return }
        let pageWidth = scrollView.bounds.width
        guard pageWidth > 0 else { return }
        let page = Int(round(scrollView.contentOffset.x / pageWidth))
        let clampedPage = min(max(page, 0), pages.count - 1)
        if clampedPage != currentIndex {
            currentIndex = clampedPage
            onPageChanged?(currentIndex)
        }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        pendingAnimatedIndex = nil
        guard !pages.isEmpty else { return }
        let pageWidth = scrollView.bounds.width
        guard pageWidth > 0 else { return }
        let page = Int(round(scrollView.contentOffset.x / pageWidth))
        let clampedPage = min(max(page, 0), pages.count - 1)
        if clampedPage != currentIndex {
            currentIndex = clampedPage
            onPageChanged?(currentIndex)
        }
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate {
            pendingAnimatedIndex = nil
            guard !pages.isEmpty else { return }
            let pageWidth = scrollView.bounds.width
            guard pageWidth > 0 else { return }
            let page = Int(round(scrollView.contentOffset.x / pageWidth))
            let clampedPage = min(max(page, 0), pages.count - 1)
            if clampedPage != currentIndex {
                currentIndex = clampedPage
                onPageChanged?(currentIndex)
            }
        }
    }
}

// MARK: - 覆盖翻页（新页面从边缘覆盖旧页面）

final class CoverPageReader: UIViewController, PageReaderContainer {
    var pages: [String] = []
    let config: ReaderConfig
    var currentIndex: Int = 0
    var onPageChanged: ((Int) -> Void)?
    var reviewEnabled: Bool = false
    var onReviewTap: ((Int) -> Void)?
    var reviewCounts: [Int: Int] = [:]

    private var currentPageView: PageContentView?
    private var isTransitioning = false

    init(pages: [String], config: ReaderConfig, initialIndex: Int) {
        self.pages = pages
        self.config = config
        self.currentIndex = initialIndex
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        installSwipeGestures()
        if !pages.isEmpty {
            showPage(at: min(max(currentIndex, 0), pages.count - 1), animated: false, direction: 1)
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if !isTransitioning, let page = currentPageView {
            page.frame = view.bounds
        }
    }

    private func installSwipeGestures() {
        let left = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipe(_:)))
        left.direction = .left
        left.cancelsTouchesInView = false
        view.addGestureRecognizer(left)

        let right = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipe(_:)))
        right.direction = .right
        right.cancelsTouchesInView = false
        view.addGestureRecognizer(right)
    }

    @objc private func handleSwipe(_ gesture: UISwipeGestureRecognizer) {
        guard !isTransitioning else { return }
        let direction = gesture.direction == .left ? 1 : -1
        let target = currentIndex + direction
        guard target >= 0, target < pages.count else { return }
        showPage(at: target, animated: true, direction: direction)
    }

    private func makePage(at index: Int) -> PageContentView {
        let page = PageContentView(text: pages[index], config: config)
        page.reviewEnabled = reviewEnabled
        page.onReviewTap = onReviewTap
        page.reviewCounts = reviewCounts
        page.frame = view.bounds
        page.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        return page
    }

    private func showPage(at index: Int, animated: Bool, direction: Int) {
        guard index >= 0, index < pages.count else { return }
        let next = makePage(at: index)
        let old = currentPageView
        let width = max(view.bounds.width, 1)

        if !animated || old == nil || view.bounds.width <= 1 {
            old?.removeFromSuperview()
            next.frame = view.bounds
            view.addSubview(next)
            currentPageView = next
            currentIndex = index
            isTransitioning = false
            return
        }

        isTransitioning = true
        // direction 1：下一页从右侧覆盖；direction -1：上一页从左侧覆盖
        next.frame = view.bounds.offsetBy(dx: direction > 0 ? width : -width, dy: 0)
        view.addSubview(next)
        UIView.animate(
            withDuration: 0.30,
            delay: 0,
            options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction]
        ) {
            next.frame = self.view.bounds
        } completion: { [weak self, weak old, weak next] finished in
            guard let self, let next else { return }
            guard finished else {
                next.removeFromSuperview()
                self.isTransitioning = false
                return
            }
            old?.removeFromSuperview()
            self.currentPageView = next
            self.currentIndex = index
            self.isTransitioning = false
            self.onPageChanged?(index)
        }
    }

    func updatePages(_ newPages: [String], keepIndex: Int) {
        pages = newPages
        guard !newPages.isEmpty else {
            currentPageView?.removeFromSuperview()
            currentPageView = nil
            currentIndex = 0
            return
        }
        let safeIndex = min(max(keepIndex, 0), newPages.count - 1)
        showPage(at: safeIndex, animated: false, direction: 1)
    }

    func goToPage(_ index: Int, animated: Bool) {
        guard index >= 0, index < pages.count, index != currentIndex, !isTransitioning else { return }
        let direction = index > currentIndex ? 1 : -1
        showPage(at: index, animated: animated, direction: direction)
    }
}

// MARK: - 仿真翻页（UIPageViewController pageCurl）

private final class IndexedPageViewController: UIViewController {
    let pageIndex: Int
    let pageView: PageContentView

    init(index: Int, pageView: PageContentView) {
        self.pageIndex = index
        self.pageView = pageView
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
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

final class CurlPageReader: UIPageViewController, PageReaderContainer, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
    var pages: [String] = []
    let config: ReaderConfig
    var currentIndex: Int = 0
    var onPageChanged: ((Int) -> Void)?
    var reviewEnabled: Bool = false
    var onReviewTap: ((Int) -> Void)?
    var reviewCounts: [Int: Int] = [:]

    init(pages: [String], config: ReaderConfig, initialIndex: Int) {
        self.pages = pages
        self.config = config
        self.currentIndex = initialIndex
        super.init(transitionStyle: .pageCurl, navigationOrientation: .horizontal, options: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        dataSource = self
        delegate = self
        view.backgroundColor = .clear
        if !pages.isEmpty {
            let initial = min(currentIndex, pages.count - 1)
            setViewControllers([makeVC(at: initial)], direction: .forward, animated: false)
            currentIndex = initial
        }
    }

    func updatePages(_ newPages: [String], keepIndex: Int) {
        pages = newPages
        let safeIndex = min(max(keepIndex, 0), max(newPages.count - 1, 0))
        currentIndex = safeIndex
        if !newPages.isEmpty {
            setViewControllers([makeVC(at: safeIndex)], direction: .forward, animated: false)
        }
    }

    func goToPage(_ index: Int, animated: Bool) {
        guard index >= 0, index < pages.count, index != currentIndex else { return }
        let direction: UIPageViewController.NavigationDirection = index > currentIndex ? .forward : .reverse
        setViewControllers([makeVC(at: index)], direction: direction, animated: animated) { [weak self] _ in
            self?.currentIndex = index
            self?.onPageChanged?(index)
        }
    }

    private func makeVC(at index: Int) -> UIViewController {
        guard index >= 0, index < pages.count else {
            return UIViewController()
        }
        let pageView = PageContentView(text: pages[index], config: config)
        pageView.reviewEnabled = reviewEnabled
        pageView.onReviewTap = onReviewTap
        pageView.reviewCounts = reviewCounts
        return IndexedPageViewController(index: index, pageView: pageView)
    }

    func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
        guard let indexed = viewController as? IndexedPageViewController else { return nil }
        let index = indexed.pageIndex - 1
        return index >= 0 ? makeVC(at: index) : nil
    }

    func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
        guard let indexed = viewController as? IndexedPageViewController else { return nil }
        let index = indexed.pageIndex + 1
        return index < pages.count ? makeVC(at: index) : nil
    }

    func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
        guard completed,
              let indexed = pageViewController.viewControllers?.first as? IndexedPageViewController else { return }
        currentIndex = indexed.pageIndex
        onPageChanged?(indexed.pageIndex)
    }
}

// MARK: - 垂直滚动翻页

final class VerticalScrollReader: UIViewController, PageReaderContainer, UIScrollViewDelegate {
    var pages: [String] = []
    let config: ReaderConfig
    var currentIndex: Int = 0
    var onPageChanged: ((Int) -> Void)?
    var reviewEnabled: Bool = false
    var onReviewTap: ((Int) -> Void)?
    var reviewCounts: [Int: Int] = [:]

    private let scrollView = UIScrollView()
    private let stackView = UIStackView()
    private var pageViews: [PageContentView] = []

    init(pages: [String], config: ReaderConfig, initialIndex: Int) {
        self.pages = pages
        self.config = config
        self.currentIndex = initialIndex
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        setupScrollView()
        reloadPages()
    }

    private func setupScrollView() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.delegate = self
        scrollView.isPagingEnabled = true
        scrollView.decelerationRate = .fast
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.alwaysBounceVertical = true
        scrollView.scrollsToTop = false
        scrollView.contentInsetAdjustmentBehavior = .never

        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.spacing = 0
        stackView.alignment = .fill
        // 页面有明确的高度约束，使用 fill 避免 fillEqually 造成约束冲突。
        stackView.distribution = .fill

        view.addSubview(scrollView)
        scrollView.addSubview(stackView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stackView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            stackView.widthAnchor.constraint(equalTo: scrollView.widthAnchor)
        ])
    }

    private func reloadPages() {
        stackView.arrangedSubviews.forEach {
            stackView.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        pageViews.removeAll()

        for text in pages {
            let pageView = PageContentView(text: text, config: config)
            pageView.reviewEnabled = reviewEnabled
            pageView.onReviewTap = onReviewTap
            pageView.reviewCounts = reviewCounts
            pageView.translatesAutoresizingMaskIntoConstraints = false
            stackView.addArrangedSubview(pageView)
            pageView.heightAnchor.constraint(equalTo: scrollView.heightAnchor).isActive = true
            pageViews.append(pageView)
        }

        view.setNeedsLayout()
        view.layoutIfNeeded()

        let safeIndex = min(max(currentIndex, 0), max(pages.count - 1, 0))
        currentIndex = safeIndex
        if scrollView.bounds.height > 0 {
            scrollView.setContentOffset(
                CGPoint(x: 0, y: CGFloat(safeIndex) * scrollView.bounds.height),
                animated: false
            )
        }
    }

    func updatePages(_ newPages: [String], keepIndex: Int) {
        pages = newPages
        let safeIndex = min(max(keepIndex, 0), max(newPages.count - 1, 0))
        currentIndex = safeIndex
        reloadPages()
    }

    func goToPage(_ index: Int, animated: Bool) {
        guard index >= 0, index < pageViews.count else { return }
        guard scrollView.bounds.height > 0 else {
            currentIndex = index
            return
        }
        guard index != currentIndex || abs(scrollView.contentOffset.y - CGFloat(index) * scrollView.bounds.height) > 1 else {
            return
        }
        let targetY = CGFloat(index) * scrollView.bounds.height
        scrollView.setContentOffset(CGPoint(x: 0, y: targetY), animated: animated)
        if !animated {
            currentIndex = index
            onPageChanged?(index)
        }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        notifyCurrentPage()
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        notifyCurrentPage()
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate { notifyCurrentPage() }
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        // 只在自然滚动结束时通知外部，避免拖动过程中连续触发 SwiftUI 重绘。
    }

    private func notifyCurrentPage() {
        let pageHeight = scrollView.bounds.height
        guard pageHeight > 0, !pages.isEmpty else { return }
        let approximateIndex = Int((scrollView.contentOffset.y + pageHeight / 2) / pageHeight)
        let clampedIndex = min(max(approximateIndex, 0), pages.count - 1)
        if clampedIndex != currentIndex {
            currentIndex = clampedIndex
            onPageChanged?(currentIndex)
        }
    }
}

// MARK: - 无动画翻页

final class NonePageReader: UIViewController, PageReaderContainer {
    var pages: [String] = []
    let config: ReaderConfig
    var currentIndex: Int = 0
    var onPageChanged: ((Int) -> Void)?
    var reviewEnabled: Bool = false
    var onReviewTap: ((Int) -> Void)?
    var reviewCounts: [Int: Int] = [:]

    private var currentPageView: PageContentView?

    init(pages: [String], config: ReaderConfig, initialIndex: Int) {
        self.pages = pages
        self.config = config
        self.currentIndex = initialIndex
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        if !pages.isEmpty {
            showPage(at: min(currentIndex, pages.count - 1))
        }
    }

    private func showPage(at index: Int) {
        currentPageView?.removeFromSuperview()

        let pageView = PageContentView(text: pages[safe: index] ?? "", config: config)
        pageView.reviewEnabled = reviewEnabled
        pageView.onReviewTap = onReviewTap
        pageView.reviewCounts = reviewCounts
        pageView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(pageView)
        NSLayoutConstraint.activate([
            pageView.topAnchor.constraint(equalTo: view.topAnchor),
            pageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pageView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        currentPageView = pageView
        currentIndex = index
    }

    func updatePages(_ newPages: [String], keepIndex: Int) {
        pages = newPages
        let safeIndex = min(max(keepIndex, 0), max(newPages.count - 1, 0))
        showPage(at: safeIndex)
    }

    func goToPage(_ index: Int, animated: Bool) {
        guard index >= 0, index < pages.count, index != currentIndex else { return }
        showPage(at: index)
        onPageChanged?(index)
    }
}

// MARK: - SwiftUI 包装（UIViewControllerRepresentable）

struct PageReaderViewRepresentable: UIViewControllerRepresentable {
    let pages: [String]
    let config: ReaderConfig
    @Binding var currentIndex: Int
    var onPageChanged: ((Int) -> Void)?
    /// 是否启用段评按钮
    var reviewEnabled: Bool = false
    /// 点击评论按钮的回调
    var onReviewTap: ((Int) -> Void)?
    /// 各段落的评论数
    var reviewCounts: [Int: Int] = [:]

    func makeUIViewController(context: Context) -> UIViewController {
        let reader = makeReader(for: config.currentPageAnim)
        reader.reviewEnabled = reviewEnabled
        reader.onReviewTap = onReviewTap
        reader.reviewCounts = reviewCounts
        reader.onPageChanged = { index in
            DispatchQueue.main.async {
                currentIndex = index
                onPageChanged?(index)
            }
        }
        return reader as! UIViewController
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        guard let reader = uiViewController as? PageReaderContainer else { return }

        // 先更新回调和页面配置，再重载页面；否则 updatePages 期间发生的页码变化
        // 会丢失回调，导致 SwiftUI 的 pageIndex 与 UIKit 容器不同步。
        reader.reviewEnabled = reviewEnabled
        reader.onReviewTap = onReviewTap
        reader.reviewCounts = reviewCounts
        reader.onPageChanged = { index in
            DispatchQueue.main.async {
                guard currentIndex != index else { return }
                currentIndex = index
                onPageChanged?(index)
            }
        }

        if reader.pages != pages {
            reader.updatePages(pages, keepIndex: currentIndex)
        } else if reader.currentIndex != currentIndex {
            // 外部状态变化（底部按钮、进度滑块、自动阅读）必须驱动真实的
            // UIKit 容器，否则只会改变计数而不会播放翻页动画。
            reader.goToPage(currentIndex, animated: true)
        }
    }

    private func makeReader(for anim: PageAnimationType) -> PageReaderContainer {
        switch anim {
        case .slide:
            return HorizontalSlideReader(pages: pages, config: config, initialIndex: currentIndex)
        case .cover:
            return CoverPageReader(pages: pages, config: config, initialIndex: currentIndex)
        case .simulation:
            return CurlPageReader(pages: pages, config: config, initialIndex: currentIndex)
        case .scroll:
            return VerticalScrollReader(pages: pages, config: config, initialIndex: currentIndex)
        case .none:
            return NonePageReader(pages: pages, config: config, initialIndex: currentIndex)
        }
    }
}

// MARK: - Array safe subscript

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard index >= 0, index < count else { return nil }
        return self[index]
    }
}
