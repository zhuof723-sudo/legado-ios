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
    private let pageBackgroundImageView = UIImageView()
    private let contentView = UIView()
    private let textView = UITextView()
    /// 预留给后续阅读背景图。背景属于整张页面，而不是父级容器。
    var backgroundImage: UIImage? {
        get { pageBackgroundImageView.image }
        set { pageBackgroundImageView.image = newValue }
    }
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
        backgroundColor = UIColor(config.currentTheme.background)
        isOpaque = true

        // 背景图层与文字同属于这一张页面；以后接入阅读背景图时，
        // 只需给这一层设置 image，所有翻页转场都会把它一起带走。
        pageBackgroundImageView.translatesAutoresizingMaskIntoConstraints = false
        pageBackgroundImageView.backgroundColor = .clear
        pageBackgroundImageView.contentMode = .scaleAspectFill
        pageBackgroundImageView.clipsToBounds = true
        pageBackgroundImageView.isUserInteractionEnabled = false
        addSubview(pageBackgroundImageView)
        NSLayoutConstraint.activate([
            pageBackgroundImageView.topAnchor.constraint(equalTo: topAnchor),
            pageBackgroundImageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            pageBackgroundImageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            pageBackgroundImageView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

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

// MARK: - 4. React-style 仿真翻页（折叠裁剪 + 透视 + 背面 + 阴影）

private enum ReactFlipDirection {
    case forward
    case backward
}

/// 参考 StPageFlip / react-pageflip 的页面折叠模型。
///
/// 与简单的左右平移不同，这里每次翻页都维护：
/// 1. 当前页的静态裁剪区域；
/// 2. 当前页正在翻起的多边形区域；
/// 3. 下一页/上一页的底层页面；
/// 4. 带 m34 透视的 3D 折叠层；
/// 5. 折痕渐变阴影。
///
/// PageContentView 本身是完整页面，所以未来加入背景图后，快照、裁剪、旋转
/// 都会自动把背景和文字作为一个整体处理。
final class ReactStylePageFlipReader: UIViewController, PageReaderContainer, UIGestureRecognizerDelegate {
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
    private var pendingPageView: PageContentView?
    private var pendingIndex = 0
    private var flipDirection: ReactFlipDirection?
    private var flipContainer: UIView?
    private var flippingSnapshot: UIView?
    private var flippingBackSnapshot: UIView?
    private var foldShadowLayer: CAGradientLayer?
    private var flipProgress: CGFloat = 0
    private var flipTouchY: CGFloat = 0

    private var displayLink: CADisplayLink?
    private var animationStartTime: CFTimeInterval = 0
    private var animationStartProgress: CGFloat = 0
    private var animationTargetProgress: CGFloat = 0
    private var animationDuration: CFTimeInterval = 0

    private var isFlipping: Bool { flipDirection != nil }

    init(pages: [String], config: ReaderConfig, initialIndex: Int) {
        self.pages = pages
        self.config = config
        self.currentIndex = initialIndex
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        displayLink?.invalidate()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(config.currentTheme.background)
        view.clipsToBounds = true
        installPanGesture()
        if !pages.isEmpty {
            showPage(at: min(max(currentIndex, 0), pages.count - 1))
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard !isFlipping else { return }
        currentPageView?.frame = view.bounds
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
        guard !isFlipping else { return false }
        let velocity = pan.velocity(in: view)
        return abs(velocity.x) > abs(velocity.y) * 1.15
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let width = max(view.bounds.width, 1)
        let translation = gesture.translation(in: view)
        let location = gesture.location(in: view)

        switch gesture.state {
        case .began:
            flipTouchY = min(max(location.y, 0), view.bounds.height)

        case .changed:
            if flipDirection == nil {
                let velocity = gesture.velocity(in: view).x
                let horizontal = abs(translation.x) > 6 ? translation.x : velocity
                let direction: ReactFlipDirection = horizontal < 0 ? .forward : .backward
                guard beginFlip(
                    to: direction == .forward ? currentIndex + 1 : currentIndex - 1,
                    direction: direction,
                    touchY: location.y
                ) else { return }
            }
            guard let direction = flipDirection else { return }
            flipTouchY = min(max(location.y, 0), view.bounds.height)
            let rawProgress: CGFloat
            switch direction {
            case .forward:
                rawProgress = -translation.x / width
            case .backward:
                rawProgress = translation.x / width
            }
            applyFlip(progress: min(max(rawProgress, 0), 1))

        case .ended, .cancelled, .failed:
            guard let direction = flipDirection else { return }
            let velocity = gesture.velocity(in: view).x
            let progress = flipProgress
            let shouldFinish: Bool
            switch direction {
            case .forward:
                shouldFinish = gesture.state == .ended && (progress > 0.34 || velocity < -650)
            case .backward:
                shouldFinish = gesture.state == .ended && (progress > 0.34 || velocity > 650)
            }
            animateFlip(to: shouldFinish ? 1 : 0, duration: shouldFinish ? 0.24 : 0.20)

        default:
            break
        }
    }

    private func makePage(at index: Int) -> PageContentView {
        let page = PageContentView(text: pages[index], config: config)
        configureReaderPage(
            page,
            reviewEnabled: reviewEnabled,
            onReviewTap: onReviewTap,
            reviewCounts: reviewCounts,
            inlineReviewMarkers: inlineReviewMarkers,
            onInlineReviewTap: onInlineReviewTap
        )
        page.frame = view.bounds
        page.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        return page
    }

    private func beginFlip(
        to index: Int,
        direction: ReactFlipDirection,
        touchY: CGFloat
    ) -> Bool {
        guard !isFlipping,
              index >= 0,
              index < pages.count,
              let current = currentPageView,
              view.bounds.width > 1,
              view.bounds.height > 1 else { return false }

        view.layoutIfNeeded()
        displayLink?.invalidate()
        displayLink = nil
        current.layer.mask = nil

        let next = makePage(at: index)
        next.isUserInteractionEnabled = false
        view.insertSubview(next, belowSubview: current)

        guard let snapshot = current.snapshotView(afterScreenUpdates: true) else {
            next.removeFromSuperview()
            return false
        }

        let container = UIView(frame: view.bounds)
        container.backgroundColor = .clear
        container.isUserInteractionEnabled = false
        container.layer.allowsEdgeAntialiasing = true
        container.layer.isDoubleSided = true
        snapshot.frame = container.bounds
        snapshot.layer.isDoubleSided = false

        // 翻起后的背面使用当前页的复制体，保持纸张背面与整张背景一致；
        // 通过局部 180° 旋转，在父页面翻到背面时重新朝向阅读者。
        let backSnapshot = current.snapshotView(afterScreenUpdates: true)
        backSnapshot?.frame = container.bounds
        backSnapshot?.layer.isDoubleSided = false
        backSnapshot?.layer.transform = CATransform3DMakeRotation(.pi, 0, 1, 0)
        backSnapshot?.alpha = 0.98
        if let backSnapshot {
            container.addSubview(backSnapshot)
            flippingBackSnapshot = backSnapshot
        }
        container.addSubview(snapshot)
        view.addSubview(container)

        let shadow = CAGradientLayer()
        shadow.colors = [
            UIColor.black.withAlphaComponent(0.02).cgColor,
            UIColor.black.withAlphaComponent(0.26).cgColor,
            UIColor.clear.cgColor
        ]
        shadow.locations = [0, 0.45, 1]
        shadow.startPoint = direction == .forward
            ? CGPoint(x: 1, y: 0.5)
            : CGPoint(x: 0, y: 0.5)
        shadow.endPoint = direction == .forward
            ? CGPoint(x: 0, y: 0.5)
            : CGPoint(x: 1, y: 0.5)
        container.layer.addSublayer(shadow)

        pendingPageView = next
        pendingIndex = index
        flipDirection = direction
        flipContainer = container
        flippingSnapshot = snapshot
        foldShadowLayer = shadow
        flipProgress = 0
        flipTouchY = min(max(touchY, 0), view.bounds.height)
        applyFlip(progress: 0)
        return true
    }

    /// 更新 StPageFlip 风格的折叠几何。
    private func applyFlip(progress: CGFloat) {
        guard let direction = flipDirection,
              let current = currentPageView,
              let container = flipContainer,
              let snapshot = flippingSnapshot else { return }

        let p = min(max(progress, 0), 1)
        flipProgress = p

        let width = max(view.bounds.width, 1)
        let height = max(view.bounds.height, 1)
        let foldX: CGFloat = direction == .forward ? width * (1 - p) : width * p
        let normalizedY = (flipTouchY - height / 2) / max(height, 1)
        let bend = normalizedY * min(width * 0.22, 120) * sin(.pi * p)
        let topX = min(max(foldX + bend, 0), width)
        let bottomX = min(max(foldX - bend, 0), width)

        let staticPath = UIBezierPath()
        let turningPath = UIBezierPath()
        if direction == .forward {
            staticPath.move(to: CGPoint(x: 0, y: 0))
            staticPath.addLine(to: CGPoint(x: topX, y: 0))
            staticPath.addLine(to: CGPoint(x: bottomX, y: height))
            staticPath.addLine(to: CGPoint(x: 0, y: height))
            staticPath.close()

            turningPath.move(to: CGPoint(x: topX, y: 0))
            turningPath.addLine(to: CGPoint(x: width, y: 0))
            turningPath.addLine(to: CGPoint(x: width, y: height))
            turningPath.addLine(to: CGPoint(x: bottomX, y: height))
            turningPath.close()
        } else {
            staticPath.move(to: CGPoint(x: topX, y: 0))
            staticPath.addLine(to: CGPoint(x: width, y: 0))
            staticPath.addLine(to: CGPoint(x: width, y: height))
            staticPath.addLine(to: CGPoint(x: bottomX, y: height))
            staticPath.close()

            turningPath.move(to: CGPoint(x: 0, y: 0))
            turningPath.addLine(to: CGPoint(x: topX, y: 0))
            turningPath.addLine(to: CGPoint(x: bottomX, y: height))
            turningPath.addLine(to: CGPoint(x: 0, y: height))
            turningPath.close()
        }

        setMask(on: current, path: staticPath.cgPath)
        setMask(on: snapshot, path: turningPath.cgPath)
        if let backSnapshot = flippingBackSnapshot {
            setMask(on: backSnapshot, path: turningPath.cgPath)
        }

        let anchorX = min(max(foldX / width, 0), 1)
        let anchorY = min(max(flipTouchY / height, 0.18), 0.82)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        container.bounds = CGRect(origin: .zero, size: view.bounds.size)
        container.layer.anchorPoint = CGPoint(x: anchorX, y: anchorY)
        container.layer.position = CGPoint(x: foldX, y: flipTouchY)

        var transform = CATransform3DIdentity
        transform.m34 = -1 / max(width * 2.2, 1)
        let angle: CGFloat = direction == .forward ? -.pi * p : .pi * p
        let axisZ = normalizedY * 0.28
        transform = CATransform3DRotate(transform, angle, 0, 1, axisZ)
        transform = CATransform3DRotate(transform, normalizedY * 0.10 * p, 0, 0, 1)
        container.layer.transform = transform

        let shadowWidth = max(16, width * 0.045)
        let shadowX = min(max(foldX - shadowWidth / 2, 0), max(width - shadowWidth, 0))
        foldShadowLayer?.frame = CGRect(x: shadowX, y: 0, width: shadowWidth, height: height)
        foldShadowLayer?.opacity = Float(sin(Double.pi * Double(p)) * 0.95)
        CATransaction.commit()
    }

    private func setMask(on view: UIView, path: CGPath) {
        let mask = (view.layer.mask as? CAShapeLayer) ?? CAShapeLayer()
        mask.frame = view.bounds
        mask.path = path
        view.layer.mask = mask
    }

    private func animateFlip(to target: CGFloat, duration: TimeInterval) {
        guard flipDirection != nil else { return }
        displayLink?.invalidate()
        animationStartTime = CACurrentMediaTime()
        animationStartProgress = flipProgress
        animationTargetProgress = target
        animationDuration = max(duration, 0.01)
        let link = CADisplayLink(target: self, selector: #selector(handleFlipDisplayLink(_:)))
        displayLink = link
        link.add(to: .main, forMode: .common)
    }

    @objc private func handleFlipDisplayLink(_ link: CADisplayLink) {
        guard flipDirection != nil else {
            link.invalidate()
            displayLink = nil
            return
        }
        let elapsed = link.timestamp - animationStartTime
        let t = min(max(elapsed / animationDuration, 0), 1)
        let eased: CGFloat
        if t < 0.5 {
            eased = CGFloat(2 * t * t)
        } else {
            let shifted = -2 * t + 2
            eased = CGFloat(1 - shifted * shifted / 2)
        }
        let value = animationStartProgress
            + (animationTargetProgress - animationStartProgress) * eased
        applyFlip(progress: value)
        if t >= 1 {
            link.invalidate()
            displayLink = nil
            finishFlip(committed: animationTargetProgress > 0.5, notify: true)
        }
    }

    private func finishFlip(committed: Bool, notify: Bool) {
        displayLink?.invalidate()
        displayLink = nil

        let current = currentPageView
        let next = pendingPageView
        let target = pendingIndex
        current?.layer.mask = nil
        flippingSnapshot?.layer.mask = nil
        flippingBackSnapshot?.layer.mask = nil
        flipContainer?.removeFromSuperview()

        if committed, let next {
            current?.removeFromSuperview()
            next.frame = view.bounds
            next.isUserInteractionEnabled = true
            currentPageView = next
            currentIndex = target
            if notify { onPageChanged?(target) }
        } else {
            next?.removeFromSuperview()
            current?.frame = view.bounds
            current?.isUserInteractionEnabled = true
        }

        pendingPageView = nil
        flipDirection = nil
        flipContainer = nil
        flippingSnapshot = nil
        flippingBackSnapshot = nil
        foldShadowLayer = nil
        flipProgress = 0
    }

    private func showPage(at index: Int) {
        guard index >= 0, index < pages.count else { return }
        let page = makePage(at: index)
        currentPageView?.removeFromSuperview()
        view.addSubview(page)
        currentPageView = page
        currentIndex = index
    }

    func refreshAppearance() {
        view.backgroundColor = UIColor(config.currentTheme.background)
        currentPageView?.refreshAppearance()
        pendingPageView?.refreshAppearance()
    }

    func updatePages(_ newPages: [String], keepIndex: Int) {
        if isFlipping { finishFlip(committed: false, notify: false) }
        pages = newPages
        guard !newPages.isEmpty else {
            currentPageView?.removeFromSuperview()
            currentPageView = nil
            currentIndex = 0
            return
        }
        showPage(at: min(max(keepIndex, 0), newPages.count - 1))
    }

    func goToPage(_ index: Int, animated: Bool) {
        guard index >= 0, index < pages.count, index != currentIndex, !isFlipping else { return }
        if !animated || view.bounds.width <= 1 || view.bounds.height <= 1 {
            showPage(at: index)
            onPageChanged?(index)
            return
        }
        let direction: ReactFlipDirection = index > currentIndex ? .forward : .backward
        guard beginFlip(to: index, direction: direction, touchY: view.bounds.midY) else { return }
        animateFlip(to: 1, duration: 0.42)
    }
}

// MARK: - 4. 滑动（新页面覆盖式滑入，跟手）

final class SlidePageReader: UIViewController, PageReaderContainer, UIGestureRecognizerDelegate {
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
    private var interactiveOldPage: PageContentView?
    private var interactiveNextPage: PageContentView?
    private var interactiveDirection = 0
    private var interactiveTargetIndex = 0

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
        view.clipsToBounds = true
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

            interactiveOldPage = currentPageView
            interactiveNextPage = makePage(at: target)
            interactiveDirection = direction
            interactiveTargetIndex = target
            isTransitioning = true

            // UINavigationController push/pop 的层级关系：
            // 前进时新页在最上层；后退时旧页在最上层滑出。
            if direction > 0 {
                view.addSubview(interactiveNextPage!)
            } else if let old = interactiveOldPage {
                view.insertSubview(interactiveNextPage!, belowSubview: old)
            } else {
                view.addSubview(interactiveNextPage!)
            }
            applyInteractiveProgress(0)

        case .changed:
            guard interactiveOldPage != nil, interactiveNextPage != nil else { return }
            let progress: CGFloat
            if interactiveDirection > 0 {
                progress = min(max(-translation.x / width, 0), 1)
            } else {
                progress = min(max(translation.x / width, 0), 1)
            }
            applyInteractiveProgress(progress)

        case .ended, .cancelled, .failed:
            guard interactiveOldPage != nil,
                  interactiveNextPage != nil else {
                isTransitioning = false
                return
            }
            let progress: CGFloat
            if interactiveDirection > 0 {
                progress = min(max(-translation.x / width, 0), 1)
            } else {
                progress = min(max(translation.x / width, 0), 1)
            }
            let finish = progress > 0.28 || abs(gesture.velocity(in: view).x) > 650
            completeInteractivePan(
                progress: progress,
                finish: finish,
                cancelled: gesture.state != .ended
            )

        default:
            break
        }
    }

    /// 手势进度映射到 UINavigationController push/pop 的位移：
    /// 前进：新页从右侧完整滑入，旧页向左视差移动 30%。
    /// 后退：旧页滑回右侧， underneath 页从 -30% 回到原位。
    private func applyInteractiveProgress(_ progress: CGFloat) {
        guard let old = interactiveOldPage,
              let next = interactiveNextPage else { return }
        let width = max(view.bounds.width, 1)
        let parallax = width * 0.30

        if interactiveDirection > 0 {
            next.frame = view.bounds.offsetBy(dx: width * (1 - progress), dy: 0)
            old.frame = view.bounds.offsetBy(dx: -parallax * progress, dy: 0)
            next.layer.shadowOpacity = Float(0.16 * progress)
        } else {
            next.frame = view.bounds.offsetBy(dx: -parallax * progress, dy: 0)
            old.frame = view.bounds.offsetBy(dx: width * progress, dy: 0)
            old.layer.shadowOpacity = Float(0.16 * progress)
        }
    }

    private func completeInteractivePan(progress: CGFloat, finish: Bool, cancelled: Bool) {
        guard let old = interactiveOldPage,
              let next = interactiveNextPage else {
            isTransitioning = false
            return
        }
        let shouldFinish = finish && !cancelled
        let target = interactiveTargetIndex

        if shouldFinish {
            applyInteractiveProgress(1)
            let animationDuration = progress < 0.08 ? 0.28 : 0.18
            UIView.animate(
                withDuration: animationDuration,
                delay: 0,
                options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction]
            ) {
                self.applyInteractiveProgress(1)
            } completion: { [weak self] _ in
                guard let self else { return }
                old.removeFromSuperview()
                next.frame = self.view.bounds
                next.layer.shadowOpacity = 0
                self.currentPageView = next
                self.currentIndex = target
                self.onPageChanged?(target)
                self.interactiveOldPage = nil
                self.interactiveNextPage = nil
                self.interactiveDirection = 0
                self.isTransitioning = false
            }
        } else {
            UIView.animate(
                withDuration: 0.20,
                delay: 0,
                options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction]
            ) {
                self.applyInteractiveProgress(0)
            } completion: { [weak self] _ in
                guard let self else { return }
                next.removeFromSuperview()
                old.frame = self.view.bounds
                old.layer.shadowOpacity = 0
                self.currentPageView = old
                self.interactiveOldPage = nil
                self.interactiveNextPage = nil
                self.interactiveDirection = 0
                self.isTransitioning = false
            }
        }
    }

    private func makePage(at index: Int) -> PageContentView {
        let page = PageContentView(text: pages[index], config: config)
        page.reviewEnabled = reviewEnabled
        page.onReviewTap = onReviewTap
        page.reviewCounts = reviewCounts
        page.inlineReviewMarkers = inlineReviewMarkers
        page.onInlineReviewTap = onInlineReviewTap
        page.frame = view.bounds
        page.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        page.layer.shadowColor = UIColor.black.cgColor
        page.layer.shadowRadius = 12
        page.layer.shadowOffset = .zero
        page.layer.shadowOpacity = 0
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
        // 与 UINavigationController push/pop 一致：
        // 前进是上层页从右侧进入 + 旧页 30% 视差；后退方向相反。
        if direction >= 0 {
            next.frame = view.bounds.offsetBy(dx: width, dy: 0)
            view.addSubview(next)
            next.layer.shadowOpacity = 0.16
            UIView.animate(
                withDuration: 0.32,
                delay: 0,
                options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction]
            ) {
                next.frame = self.view.bounds
                old?.frame = self.view.bounds.offsetBy(dx: -width * 0.30, dy: 0)
            } completion: { [weak self] _ in
                guard let self else { return }
                old?.removeFromSuperview()
                next.frame = self.view.bounds
                next.layer.shadowOpacity = 0
                self.currentPageView = next
                self.currentIndex = index
                self.isTransitioning = false
                self.onPageChanged?(index)
            }
        } else {
            next.frame = view.bounds.offsetBy(dx: -width * 0.30, dy: 0)
            view.insertSubview(next, belowSubview: old!)
            old?.layer.shadowOpacity = 0.16
            UIView.animate(
                withDuration: 0.32,
                delay: 0,
                options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction]
            ) {
                next.frame = self.view.bounds
                old?.frame = self.view.bounds.offsetBy(dx: width, dy: 0)
            } completion: { [weak self] _ in
                guard let self else { return }
                old?.removeFromSuperview()
                next.layer.shadowOpacity = 0
                next.frame = self.view.bounds
                self.currentPageView = next
                self.currentIndex = index
                self.isTransitioning = false
                self.onPageChanged?(index)
            }
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


// MARK: - 5. 无动画（瞬时切换）

final class InstantPageReader: UIViewController, PageReaderContainer, UIGestureRecognizerDelegate {
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
            showPage(at: min(max(currentIndex, 0), pages.count - 1))
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
        // 只响应明显的水平滑动。
        return abs(velocity.x) > abs(velocity.y) * 1.15
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
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

    private func showPage(at index: Int) {
        guard index >= 0, index < pages.count else { return }
        let page = makePage(at: index)
        currentPageView?.removeFromSuperview()
        view.addSubview(page)
        currentPageView = page
        currentIndex = index
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
        showPage(at: min(max(keepIndex, 0), newPages.count - 1))
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
        case .pageCurl:
            return ReactStylePageFlipReader(pages: pages, config: config, initialIndex: currentIndex)
        case .cover:
            return SlidePageReader(pages: pages, config: config, initialIndex: currentIndex)
        case .pageScroll:
            return NativePageReader(
                pages: pages,
                config: config,
                initialIndex: currentIndex,
                transitionStyle: .scroll,
                doubleSided: false
            )
        case .freeScroll:
            return FreeScrollReader(pages: pages, config: config, initialIndex: currentIndex)
        case .none:
            return InstantPageReader(pages: pages, config: config, initialIndex: currentIndex)
        }
    }
}
