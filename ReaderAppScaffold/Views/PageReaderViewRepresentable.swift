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
    private let contentView = UIView()
    private let textView = UITextView()
    private var contentTopConstraint: NSLayoutConstraint?
    private var contentLeadingConstraint: NSLayoutConstraint?
    private var contentTrailingConstraint: NSLayoutConstraint?
    private var contentBottomConstraint: NSLayoutConstraint?

    init(text: String, config: ReaderConfig) {
        self.text = text
        self.config = config
        super.init(frame: .zero)
        setupTextView()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setupTextView() {
        // 每个 PageContentView 是一个独立页面：背景必须和文字放在
        // 同一个会被翻页容器 transform 的视图上，不能依赖父容器背景。
        backgroundColor = UIColor(config.currentTheme.background)
        isOpaque = true
        // 页面背景层铺满，不设置外部 inset；只有内容层拥有阅读边距。
        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.backgroundColor = .clear
        addSubview(contentView)
        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: topAnchor),
            contentView.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

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

        contentView.addSubview(textView)
        contentTopConstraint = textView.topAnchor.constraint(
            equalTo: contentView.topAnchor, constant: CGFloat(config.paddingTop)
        )
        contentLeadingConstraint = textView.leadingAnchor.constraint(
            equalTo: contentView.leadingAnchor, constant: CGFloat(config.paddingH)
        )
        contentTrailingConstraint = textView.trailingAnchor.constraint(
            equalTo: contentView.trailingAnchor, constant: -CGFloat(config.paddingH)
        )
        contentBottomConstraint = textView.bottomAnchor.constraint(
            equalTo: contentView.bottomAnchor, constant: -CGFloat(config.paddingBottom)
        )
        NSLayoutConstraint.activate([
            contentTopConstraint!, contentLeadingConstraint!,
            contentTrailingConstraint!, contentBottomConstraint!
        ])

        updateAttributedText()
    }

    /// 更新页面背景和文字样式。
    func refreshAppearance() {
        backgroundColor = UIColor(config.currentTheme.background)
        contentTopConstraint?.constant = CGFloat(config.paddingTop)
        contentLeadingConstraint?.constant = CGFloat(config.paddingH)
        contentTrailingConstraint?.constant = -CGFloat(config.paddingH)
        contentBottomConstraint?.constant = -CGFloat(config.paddingBottom)
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
    /// 刷新每个独立页面的背景和文字样式。
    func refreshAppearance()
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

    func refreshAppearance() {
        pageViews.forEach { $0.refreshAppearance() }
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

final class CoverPageReader: UIViewController, PageReaderContainer, UIGestureRecognizerDelegate {
    var pages: [String] = []
    let config: ReaderConfig
    var currentIndex: Int = 0
    var onPageChanged: ((Int) -> Void)?
    var reviewEnabled: Bool = false
    var onReviewTap: ((Int) -> Void)?
    var reviewCounts: [Int: Int] = [:]

    private var currentPageView: PageContentView?
    private var isTransitioning = false
    private var interactiveOldPage: PageContentView?
    private var interactiveNextPage: PageContentView?
    private var interactiveDirection = 0

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
        installPanGesture()
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

    private func installPanGesture() {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.maximumNumberOfTouches = 1
        pan.cancelsTouchesInView = false
        pan.delegate = self
        view.addGestureRecognizer(pan)
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
        let velocity = pan.velocity(in: view)
        // 只把明显的左右手势当作翻页，避免上下滚动/拖动文字时触发覆盖动画。
        return abs(velocity.x) > abs(velocity.y) * 1.15
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: view)
        let width = max(view.bounds.width, 1)

        switch gesture.state {
        case .began:
            guard !isTransitioning else { return }
            let velocity = gesture.velocity(in: view).x
            let translationX = gesture.translation(in: view).x
            let direction = (velocity != 0 ? velocity : translationX) < 0 ? 1 : -1
            let target = currentIndex + direction
            guard target >= 0, target < pages.count else {
                gesture.isEnabled = false
                gesture.isEnabled = true
                return
            }
            let next = makePage(at: target)
            let old = currentPageView
            interactiveOldPage = old
            interactiveNextPage = next
            interactiveDirection = direction
            isTransitioning = true
            // 下一页先铺在底层，当前页向左右滑走，形成截图中的“左右覆盖”效果。
            next.frame = view.bounds
            if let old {
                old.layer.shadowColor = UIColor.black.cgColor
                old.layer.shadowOpacity = 0.22
                old.layer.shadowRadius = 14
                old.layer.shadowOffset = CGSize(width: 0, height: 0)
                view.insertSubview(next, belowSubview: old)
            } else {
                view.addSubview(next)
            }

        case .changed:
            guard let old = interactiveOldPage, interactiveNextPage != nil else { return }
            let offset = translation.x
            old.frame = view.bounds.offsetBy(dx: offset, dy: 0)
            old.layer.shadowOpacity = 0.22

        case .ended, .cancelled, .failed:
            guard let old = interactiveOldPage, let next = interactiveNextPage else {
                isTransitioning = false
                return
            }
            let progress = min(max((interactiveDirection > 0 ? -translation.x : translation.x) / width, 0), 1)
            let finish = progress > 0.28 || abs(gesture.velocity(in: view).x) > 650
            let direction = interactiveDirection
            let target = currentIndex + direction
            // 下一页已经在旧页下面；左右滑走的是当前页。
            let finalX = finish ? (direction > 0 ? -width : width) : 0
            UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
                old.frame = self.view.bounds.offsetBy(dx: finalX, dy: 0)
                old.layer.shadowOpacity = finish ? 0 : 0.22
            } completion: { [weak self, weak old, weak next] _ in
                guard let self else { return }
                if finish {
                    old?.removeFromSuperview()
                    next?.frame = self.view.bounds
                    self.currentPageView = next
                    self.currentIndex = target
                    self.onPageChanged?(target)
                } else {
                    next?.removeFromSuperview()
                    old?.frame = self.view.bounds
                    old?.layer.shadowOpacity = 0
                    self.currentPageView = old
                }
                self.interactiveOldPage = nil
                self.interactiveNextPage = nil
                self.interactiveDirection = 0
                self.isTransitioning = false
            }

        default:
            break
        }
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
        // 非交互式覆盖：下一页铺在底层，当前页向左右滑出，
        // 与手势拖拽及参考图中的左右覆盖效果保持一致。
        next.frame = view.bounds
        if let old {
            old.layer.shadowColor = UIColor.black.cgColor
            old.layer.shadowOpacity = 0.22
            old.layer.shadowRadius = 14
            old.layer.shadowOffset = .zero
            view.insertSubview(next, belowSubview: old)
        } else {
            view.addSubview(next)
        }
        UIView.animate(
            withDuration: 0.30,
            delay: 0,
            options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction]
        ) {
            old?.frame = self.view.bounds.offsetBy(dx: direction > 0 ? -width : width, dy: 0)
            old?.layer.shadowOpacity = 0
        } completion: { [weak self, weak old, weak next] finished in
            guard let self, let next else { return }
            guard finished else {
                next.removeFromSuperview()
                old?.frame = self.view.bounds
                old?.layer.shadowOpacity = 0
                self.isTransitioning = false
                return
            }
            old?.removeFromSuperview()
            next.frame = self.view.bounds
            self.currentPageView = next
            self.currentIndex = index
            self.isTransitioning = false
            self.onPageChanged?(index)
        }
    }

    func refreshAppearance() {
        currentPageView?.refreshAppearance()
        interactiveOldPage?.refreshAppearance()
        interactiveNextPage?.refreshAppearance()
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
        view.backgroundColor = UIColor(pageView.config.currentTheme.background)
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
        isDoubleSided = false
        view.backgroundColor = .clear
        if !pages.isEmpty {
            let initial = min(currentIndex, pages.count - 1)
            setViewControllers([makeVC(at: initial)], direction: .forward, animated: false)
            currentIndex = initial
        }
    }

    func refreshAppearance() {
        viewControllers?.compactMap { $0 as? IndexedPageViewController }
            .forEach { $0.pageView.refreshAppearance() }
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
    private var needsInitialOffset = true
    private var lastBoundsSize: CGSize = .zero
    private var pendingAnimatedIndex: Int?
    private let bottomContentPadding: CGFloat = 60

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
        guard size.width > 0, size.height > 0, !pages.isEmpty else { return }

        // 只在首次布局或屏幕尺寸变化时校准位置。不要在每次布局时
        // 重置 contentOffset，否则滚动中的页面会被自动拉回，形成跳动。
        if needsInitialOffset || lastBoundsSize != size {
            let targetIndex = pendingAnimatedIndex ?? currentIndex
            let safeIndex = min(max(targetIndex, 0), pages.count - 1)
            scrollView.setContentOffset(
                CGPoint(x: 0, y: pageOffset(for: safeIndex)),
                animated: false
            )
            needsInitialOffset = false
            lastBoundsSize = size
        }
    }

    private func setupScrollView() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.delegate = self
        // 自由滚动：关闭分页吸附，松手后保留用户实际拖拽位置。
        // bounces=false 防止滚动链和边界回弹把正文位置拉回。
        scrollView.isPagingEnabled = false
        scrollView.decelerationRate = .normal
        scrollView.isDirectionalLockEnabled = true
        scrollView.canCancelContentTouches = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.bounces = false
        scrollView.alwaysBounceVertical = false
        scrollView.alwaysBounceHorizontal = false
        scrollView.scrollsToTop = false
        // 对应网页阅读器的 overflow-anchor: none / overscroll-behavior-y: contain：
        // 禁止滚动链和自动锚定把正文位置向上拉回。
        scrollView.contentInset = UIEdgeInsets(
            top: 0,
            left: 0,
            bottom: bottomContentPadding,
            right: 0
        )
        scrollView.verticalScrollIndicatorInsets = UIEdgeInsets(
            top: 0,
            left: 0,
            bottom: bottomContentPadding,
            right: 0
        )
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
        pendingAnimatedIndex = nil
        needsInitialOffset = true
        lastBoundsSize = .zero
        if scrollView.bounds.height > 0 {
            scrollView.setContentOffset(
                CGPoint(x: 0, y: pageOffset(for: safeIndex)),
                animated: false
            )
            needsInitialOffset = false
            lastBoundsSize = scrollView.bounds.size
        }
    }

    func refreshAppearance() {
        pageViews.forEach { $0.refreshAppearance() }
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
        let targetY = pageOffset(for: index)
        guard abs(scrollView.contentOffset.y - targetY) > 1 else { return }

        // 向下翻页始终增加 contentOffset.y；不用负方向或依赖锚点修正，
        // 避免正文在动画过程中向上跳动。
        pendingAnimatedIndex = animated ? index : nil
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

    private func pageOffset(for index: Int) -> CGFloat {
        CGFloat(index) * scrollView.bounds.height
    }

    private func notifyCurrentPage() {
        let pageHeight = scrollView.bounds.height
        guard pageHeight > 0, !pages.isEmpty else { return }
        let approximateIndex = Int((scrollView.contentOffset.y + pageHeight / 2) / pageHeight)
        let clampedIndex = min(max(approximateIndex, 0), pages.count - 1)
        pendingAnimatedIndex = nil
        if clampedIndex != currentIndex {
            currentIndex = clampedIndex
            onPageChanged?(currentIndex)
        }
    }
}

// MARK: - 无动画翻页

final class NonePageReader: UIViewController, PageReaderContainer, UIGestureRecognizerDelegate {
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
        installNoAnimationGestures()
        if !pages.isEmpty {
            showPage(at: min(currentIndex, pages.count - 1))
        }
    }

    private func installNoAnimationGestures() {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handleNoAnimationPan(_:)))
        pan.delegate = self
        pan.cancelsTouchesInView = false
        view.addGestureRecognizer(pan)
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
        let velocity = pan.velocity(in: view)
        return abs(velocity.x) > abs(velocity.y) * 1.15
    }

    @objc private func handleNoAnimationPan(_ gesture: UIPanGestureRecognizer) {
        guard gesture.state == .ended else { return }
        let velocity = gesture.velocity(in: view).x
        let translation = gesture.translation(in: view).x
        guard abs(velocity) > 250 || abs(translation) > 50 else { return }
        if velocity < 0 || translation < 0 {
            goToPage(currentIndex + 1, animated: false)
        } else {
            goToPage(currentIndex - 1, animated: false)
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

    func refreshAppearance() {
        currentPageView?.refreshAppearance()
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

        // 每个页面自己持有背景；配置变化时同步刷新所有正在显示的页面，
        // 保证覆盖/仿真翻页使用的 transform 层始终是完整的“背景+文字”页面。
        reader.refreshAppearance()

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
