import SwiftUI
import UIKit
import LegadoRuleEngine

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
    /// 由正文内嵌段评图生成的 marker。
    var inlineReviewMarkers: [InlineReviewMarker] = [] {
        didSet { updateAttributedText() }
    }
    /// 点击内嵌段评图时回传 marker id。
    var onInlineReviewTap: ((Int) -> Void)?
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
        // UITextView 只有在 selectable 时才会把 NSLink 交给 delegate。
        textView.isSelectable = true
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

        if !inlineReviewMarkers.isEmpty {
            textView.attributedText = ReviewLinkHelper.attachInlineReviewLinks(
                to: text,
                markers: inlineReviewMarkers,
                attributes: attributes,
                reviewCounts: reviewCounts
            )
        } else if reviewEnabled {
            // 兼容旧书源：没有内嵌段评图时，仍给普通段落附加可点击入口。
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
        // 处理兼容模式的段落链接。
        if let paragraphIndex = ReviewLinkHelper.paragraphIndex(from: URL) {
            onReviewTap?(paragraphIndex)
            return false
        }
        // Legado 原版 style:"TEXT" 段评图入口。
        if let markerID = ReviewLinkHelper.markerID(from: URL) {
            onInlineReviewTap?(markerID)
            return false
        }
        return false
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
    /// 正文内嵌段评图 marker。
    var inlineReviewMarkers: [InlineReviewMarker] { get set }
    /// 点击内嵌段评图。
    var onInlineReviewTap: ((Int) -> Void)? { get set }
    /// 刷新每个独立页面的背景和文字样式。
    func refreshAppearance()
    func goToPage(_ index: Int, animated: Bool)
    func updatePages(_ newPages: [String], keepIndex: Int)
}

// MARK: - 共用页面构造

private func configureReaderPage(
    _ pageView: PageContentView,
    reviewEnabled: Bool,
    onReviewTap: ((Int) -> Void)?,
    reviewCounts: [Int: Int],
    inlineReviewMarkers: [InlineReviewMarker],
    onInlineReviewTap: ((Int) -> Void)?
) {
    pageView.reviewEnabled = reviewEnabled
    pageView.onReviewTap = onReviewTap
    pageView.reviewCounts = reviewCounts
    pageView.inlineReviewMarkers = inlineReviewMarkers
    pageView.onInlineReviewTap = onInlineReviewTap
}

// MARK: - 1. 自由垂直滚动：UIScrollView + UITextView

final class FreeScrollReader: UIViewController, PageReaderContainer, UIScrollViewDelegate {
    var pages: [String] = []
    let config: ReaderConfig
    var currentIndex: Int = 0
    var onPageChanged: ((Int) -> Void)?
    var reviewEnabled: Bool = false
    var onReviewTap: ((Int) -> Void)?
    var reviewCounts: [Int: Int] = [:]
    var inlineReviewMarkers: [InlineReviewMarker] = []
    var onInlineReviewTap: ((Int) -> Void)?

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
        // 自由连续滚动：关闭分页吸附，松手后保留用户实际拖拽位置。
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
        scrollView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: bottomContentPadding, right: 0)
        scrollView.verticalScrollIndicatorInsets = UIEdgeInsets(top: 0, left: 0, bottom: bottomContentPadding, right: 0)
        scrollView.contentInsetAdjustmentBehavior = .never

        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.spacing = 0
        stackView.alignment = .fill
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
            configureReaderPage(
                pageView,
                reviewEnabled: reviewEnabled,
                onReviewTap: onReviewTap,
                reviewCounts: reviewCounts,
                inlineReviewMarkers: inlineReviewMarkers,
                onInlineReviewTap: onInlineReviewTap
            )
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

// MARK: - UIPageViewController 页面包装

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

// MARK: - 2/3. 原生平移滑动与书本卷曲

final class NativePageReader: UIPageViewController, PageReaderContainer, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
    var pages: [String] = []
    let config: ReaderConfig
    var currentIndex: Int = 0
    var onPageChanged: ((Int) -> Void)?
    var reviewEnabled: Bool = false
    var onReviewTap: ((Int) -> Void)?
    var reviewCounts: [Int: Int] = [:]
    var inlineReviewMarkers: [InlineReviewMarker] = []
    var onInlineReviewTap: ((Int) -> Void)?

    init(
        pages: [String],
        config: ReaderConfig,
        initialIndex: Int,
        transitionStyle: UIPageViewController.TransitionStyle,
        doubleSided: Bool
    ) {
        self.pages = pages
        self.config = config
        self.currentIndex = initialIndex
        super.init(transitionStyle: transitionStyle, navigationOrientation: .horizontal, options: nil)
        isDoubleSided = doubleSided
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        dataSource = self
        delegate = self
        view.backgroundColor = UIColor(config.currentTheme.background)
        if !pages.isEmpty {
            let initial = min(max(currentIndex, 0), pages.count - 1)
            setViewControllers([makeViewController(at: initial)], direction: .forward, animated: false)
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
            setViewControllers([makeViewController(at: safeIndex)], direction: .forward, animated: false)
        }
    }

    func goToPage(_ index: Int, animated: Bool) {
        guard index >= 0, index < pages.count, index != currentIndex else { return }
        let direction: UIPageViewController.NavigationDirection = index > currentIndex ? .forward : .reverse
        setViewControllers(
            [makeViewController(at: index)],
            direction: direction,
            animated: animated
        ) { [weak self] _ in
            self?.finishTransition(to: index)
        }
    }

    private func makeViewController(at index: Int) -> UIViewController {
        guard index >= 0, index < pages.count else { return UIViewController() }
        let pageView = PageContentView(text: pages[index], config: config)
        configureReaderPage(
            pageView,
            reviewEnabled: reviewEnabled,
            onReviewTap: onReviewTap,
            reviewCounts: reviewCounts,
            inlineReviewMarkers: inlineReviewMarkers,
            onInlineReviewTap: onInlineReviewTap
        )
        return IndexedPageViewController(index: index, pageView: pageView)
    }

    private func finishTransition(to index: Int) {
        guard currentIndex != index else { return }
        currentIndex = index
        onPageChanged?(index)
    }

    func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerBefore viewController: UIViewController
    ) -> UIViewController? {
        guard let indexed = viewController as? IndexedPageViewController else { return nil }
        let index = indexed.pageIndex - 1
        return index >= 0 ? makeViewController(at: index) : nil
    }

    func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerAfter viewController: UIViewController
    ) -> UIViewController? {
        guard let indexed = viewController as? IndexedPageViewController else { return nil }
        let index = indexed.pageIndex + 1
        return index < pages.count ? makeViewController(at: index) : nil
    }

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

// MARK: - 4. 快速淡入淡出（UIKit CATransition）

final class FadePageReader: UIViewController, PageReaderContainer, UIGestureRecognizerDelegate {
    var pages: [String] = []
    let config: ReaderConfig
    var currentIndex: Int = 0
    var onPageChanged: ((Int) -> Void)?
    var reviewEnabled: Bool = false
    var onReviewTap: ((Int) -> Void)?
    var reviewCounts: [Int: Int] = [:]
    var inlineReviewMarkers: [InlineReviewMarker] = []
    var onInlineReviewTap: ((Int) -> Void)?

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
        view.backgroundColor = UIColor(config.currentTheme.background)
        installPanGesture()
        if !pages.isEmpty {
            showPage(at: min(max(currentIndex, 0), pages.count - 1), animated: false)
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
        // 每种模式只有自己的手势；这里只响应明显的水平滑动。
        return abs(velocity.x) > abs(velocity.y) * 1.15
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard gesture.state == .ended else { return }
        let velocity = gesture.velocity(in: view).x
        let translation = gesture.translation(in: view).x
        guard abs(velocity) > 250 || abs(translation) > 50 else { return }
        if velocity < 0 || translation < 0 {
            goToPage(currentIndex + 1, animated: true)
        } else {
            goToPage(currentIndex - 1, animated: true)
        }
    }

    private func makePage(at index: Int) -> PageContentView {
        let pageView = PageContentView(text: pages[index], config: config)
        configureReaderPage(
            pageView,
            reviewEnabled: reviewEnabled,
            onReviewTap: onReviewTap,
            reviewCounts: reviewCounts,
            inlineReviewMarkers: inlineReviewMarkers,
            onInlineReviewTap: onInlineReviewTap
        )
        pageView.frame = view.bounds
        pageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        return pageView
    }

    private func showPage(at index: Int, animated: Bool) {
        guard index >= 0, index < pages.count else { return }
        let next = makePage(at: index)
        let old = currentPageView

        guard animated, old != nil, view.bounds.width > 1, view.bounds.height > 1, !isTransitioning else {
            old?.removeFromSuperview()
            view.addSubview(next)
            currentPageView = next
            currentIndex = index
            isTransitioning = false
            return
        }

        isTransitioning = true
        let transition = CATransition()
        transition.type = CATransitionType.fade
        transition.duration = 0.25
        transition.timingFunction = CAMediaTimingFunction(name: .easeOut)
        transition.fillMode = .both
        transition.isRemovedOnCompletion = true

        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            old?.removeFromSuperview()
            self?.currentPageView = next
            self?.currentIndex = index
            self?.isTransitioning = false
            self?.onPageChanged?(index)
        }
        view.layer.add(transition, forKey: "reader.pageFade")
        view.addSubview(next)
        CATransaction.commit()
    }

    func refreshAppearance() {
        currentPageView?.refreshAppearance()
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
        showPage(at: safeIndex, animated: false)
    }

    func goToPage(_ index: Int, animated: Bool) {
        guard index >= 0, index < pages.count, index != currentIndex else { return }
        showPage(at: index, animated: animated)
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
    var inlineReviewMarkers: [InlineReviewMarker] = []
    var onInlineReviewTap: ((Int) -> Void)?

    func makeUIViewController(context: Context) -> UIViewController {
        let reader = makeReader(for: config.currentPageAnim)
        reader.reviewEnabled = reviewEnabled
        reader.onReviewTap = onReviewTap
        reader.reviewCounts = reviewCounts
        reader.inlineReviewMarkers = inlineReviewMarkers
        reader.onInlineReviewTap = onInlineReviewTap
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

        // 每个页面自己持有背景；配置变化时同步刷新所有正在显示的页面。
        reader.refreshAppearance()

        // 先更新回调和页面配置，再重载页面；否则 updatePages 期间发生的页码变化
        // 会丢失回调，导致 SwiftUI 的 pageIndex 与 UIKit 容器不同步。
        reader.reviewEnabled = reviewEnabled
        reader.onReviewTap = onReviewTap
        reader.reviewCounts = reviewCounts
        reader.inlineReviewMarkers = inlineReviewMarkers
        reader.onInlineReviewTap = onInlineReviewTap
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
            reader.goToPage(currentIndex, animated: true)
        }
    }

    private func makeReader(for anim: PageAnimationType) -> PageReaderContainer {
        switch anim {
        case .freeScroll:
            return FreeScrollReader(pages: pages, config: config, initialIndex: currentIndex)
        case .pageScroll:
            return NativePageReader(
                pages: pages,
                config: config,
                initialIndex: currentIndex,
                transitionStyle: .scroll,
                doubleSided: false
            )
        case .pageCurl:
            return NativePageReader(
                pages: pages,
                config: config,
                initialIndex: currentIndex,
                transitionStyle: .pageCurl,
                doubleSided: true
            )
        case .fade:
            return FadePageReader(pages: pages, config: config, initialIndex: currentIndex)
        }
    }
}
