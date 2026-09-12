import SwiftUI
import UIKit
import LegadoRuleEngine

// MARK: - 单页内容视图

final class PageContentView: UIView, UITextViewDelegate, UIGestureRecognizerDelegate {
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
    /// 点击页面上除段评入口以外的任意位置（用于收起段评弹层），回传点击坐标。
    var onOutsideTap: ((CGPoint) -> Void)?
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
        // 捕获阶段监听所有触摸：段评入口由 shouldInteractWith 正常处理，
        // 其余位置冒泡到 onOutsideTap 用于收起段评弹层。
        let tap = UITapGestureRecognizer(target: self, action: #selector(handlePageTap(_:)))
        tap.cancelsTouchesInView = false
        tap.delegate = self
        textView.addGestureRecognizer(tap)

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

    // MARK: - 整页点击（区分段评入口与普通区域）

    @objc private func handlePageTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else { return }
        let location = gesture.location(in: textView)
        // 命中段评链接时交给 UITextView 自己处理（不冒泡）。
        let index = textView.layoutManager.characterIndex(
            for: location,
            in: textView.textContainer,
            fractionOfDistanceBetweenInsertionPoints: nil
        )
        if index < textView.textStorage.length,
           textView.textStorage.attribute(.link, at: index, effectiveRange: nil) != nil {
            return
        }
        onOutsideTap?(location)
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool { true }

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
    /// 点击页面上除段评入口以外的任意位置（收起段评弹层）。
    var onOutsideTap: ((CGPoint) -> Void)? { get set }
    /// 刷新每个独立页面的背景和文字样式。
    func refreshAppearance()
    func goToPage(_ index: Int, animated: Bool)
    func updatePages(_ newPages: [String], keepIndex: Int)
}

// MARK: - 共用页面构造

func configureReaderPage(
    _ pageView: PageContentView,
    reviewEnabled: Bool,
    onReviewTap: ((Int) -> Void)?,
    reviewCounts: [Int: Int],
    inlineReviewMarkers: [InlineReviewMarker],
    onInlineReviewTap: ((Int) -> Void)?,
    onOutsideTap: ((CGPoint) -> Void)? = nil
) {
    pageView.reviewEnabled = reviewEnabled
    pageView.onReviewTap = onReviewTap
    pageView.reviewCounts = reviewCounts
    pageView.inlineReviewMarkers = inlineReviewMarkers
    pageView.onInlineReviewTap = onInlineReviewTap
    pageView.onOutsideTap = onOutsideTap
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
    var onOutsideTap: ((CGPoint) -> Void)?

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
                onInlineReviewTap: onInlineReviewTap,
                onOutsideTap: onOutsideTap
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
    var onOutsideTap: ((CGPoint) -> Void)?

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
            onInlineReviewTap: onInlineReviewTap,
            onOutsideTap: onOutsideTap
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

// MARK: - 4. 滑动（参考图一：整页平移覆盖式）

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
    var onOutsideTap: ((CGPoint) -> Void)?

    private var currentPageView: PageContentView?
    private var isTransitioning = false
    private var interactiveOldPage: PageContentView?
    private var interactiveNextPage: PageContentView?
    private var interactiveDirection = 0
    private var interactiveTargetIndex = 0
    /// 覆盖动画三件套（参考项目 CoreTextPagedView 同款）：
    /// 新页快照(带屏幕圆角) / 其下方投影 / 后退时的旧页渐暗层。
    private let coverIncomingImageView = UIImageView()
    private let coverShadowView = UIView()
    private let coverDimView = UIView()
    private var coverOverlayInstalled = false

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

    /// 屏幕物理圆角（参考项目取 displayCornerRadius 的做法）。
    private var screenCornerRadius: CGFloat {
        let r = (UIScreen.main.value(forKey: "displayCornerRadius") as? CGFloat) ?? 0
        return r > 0 ? r : 12
    }

    /// 搭建覆盖层：新页快照（圆角裁切）+ 下方投影 + 旧页渐暗层。
    private func setupCoverOverlay() {
        guard !coverOverlayInstalled else { return }
        coverOverlayInstalled = true
        let radius = screenCornerRadius

        coverShadowView.backgroundColor = .clear
        coverShadowView.layer.shadowColor = UIColor.black.cgColor
        coverShadowView.layer.shadowOpacity = 0.3
        coverShadowView.layer.shadowRadius = 14
        coverShadowView.layer.shadowOffset = .zero

        coverIncomingImageView.contentMode = .scaleAspectFill
        coverIncomingImageView.clipsToBounds = true
        coverIncomingImageView.layer.cornerRadius = radius

        coverDimView.backgroundColor = .black
        coverDimView.alpha = 0
        coverDimView.isUserInteractionEnabled = false
    }

    /// 从页面内容页截快照。
    private func snapshotImage(of pageView: UIView) -> UIImage? {
        pageView.layoutIfNeeded()
        return UIGraphicsImageRenderer(bounds: pageView.bounds).image { _ in
            pageView.drawHierarchy(in: pageView.bounds, afterScreenUpdates: true)
        }
    }

    /// 收起覆盖动画层（快照/投影/渐暗），恢复静止显示。
    private func removeCoverOverlay() {
        coverIncomingImageView.removeFromSuperview()
        coverShadowView.removeFromSuperview()
        coverDimView.removeFromSuperview()
        coverShadowView.addSubview(coverIncomingImageView) // 复位层级供下次使用
        coverDimView.alpha = 0
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

            // 参考项目覆盖动画层级搭建：
            // 前进：快照层(圆角+投影)盖在当前页上，真页暂不加视图；
            // 后退：上一页插到当前页下层，当前页滑出时渐暗。
            setupCoverOverlay()
            if direction > 0 {
                guard let old = interactiveOldPage else { return }
                let snap = snapshotImage(of: interactiveNextPage!)
                coverIncomingImageView.image = snap
                coverIncomingImageView.frame = view.bounds
                coverShadowView.frame = view.bounds
                coverShadowView.addSubview(coverIncomingImageView)
                view.addSubview(coverShadowView)
                _ = old
            } else if let old = interactiveOldPage {
                view.insertSubview(interactiveNextPage!, belowSubview: old)
                coverDimView.frame = view.bounds
                view.addSubview(coverDimView)
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
            let finish = progress > 0.32 || abs(gesture.velocity(in: view).x) > 700
            completeInteractivePan(
                progress: progress,
                finish: finish,
                cancelled: gesture.state != .ended
            )

        default:
            break
        }
    }

    /// 参考项目 CoreTextPagedView 的覆盖动画：
    /// 前进：新页（快照，带屏幕圆角+投影）从右侧整页滑入盖住静止当前页；
    /// 后退：当前页向右滑出，下层上一页原位露出，同时旧页逐渐变暗。
    private func applyInteractiveProgress(_ progress: CGFloat) {
        guard let old = interactiveOldPage,
              let next = interactiveNextPage else { return }
        let width = max(view.bounds.width, 1)

        if interactiveDirection > 0 {
            // 前进：新页整页滑入（快照层跟随移动），当前页静止。
            old.frame = view.bounds
            coverShadowView.frame = next.frame.offsetBy(dx: width * (1 - progress), dy: 0)
            coverIncomingImageView.frame = coverShadowView.frame
            coverShadowView.alpha = 1
        } else {
            // 后退：当前页整页滑出 + 渐暗；下层上一页静止。
            next.frame = view.bounds
            old.frame = view.bounds.offsetBy(dx: width * progress, dy: 0)
            coverDimView.frame = view.bounds
            coverDimView.alpha = 0.25 * progress
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
            UIView.animate(
                withDuration: 0.20,
                delay: 0,
                options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction]
            ) {
                self.applyInteractiveProgress(1)
            } completion: { [weak self] _ in
                guard let self else { return }
                old.removeFromSuperview()
                // 快照层退场后让真页上台（此前只在下层等待）。
                if next.superview == nil { self.view.addSubview(next) }
                next.frame = self.view.bounds
                self.removeCoverOverlay()
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
                self.removeCoverOverlay()
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
        page.onOutsideTap = onOutsideTap
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
        // 程序化翻页与手势一致：覆盖式整页平移（圆角快照+投影/渐暗）。
        setupCoverOverlay()
        if direction >= 0 {
            let snap = snapshotImage(of: next)
            coverIncomingImageView.image = snap
            coverIncomingImageView.frame = view.bounds.offsetBy(dx: width, dy: 0)
            coverShadowView.frame = coverIncomingImageView.frame
            coverShadowView.addSubview(coverIncomingImageView)
            view.addSubview(coverShadowView)
            UIView.animate(
                withDuration: 0.30,
                delay: 0,
                options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction]
            ) {
                self.coverIncomingImageView.frame = self.view.bounds
                self.coverShadowView.frame = self.view.bounds
            } completion: { [weak self] _ in
                guard let self else { return }
                old?.removeFromSuperview()
                next.frame = self.view.bounds
                self.view.addSubview(next)
                self.removeCoverOverlay()
                self.currentPageView = next
                self.currentIndex = index
                self.isTransitioning = false
                self.onPageChanged?(index)
            }
        } else {
            view.insertSubview(next, belowSubview: old!)
            coverDimView.frame = view.bounds
            view.addSubview(coverDimView)
            UIView.animate(
                withDuration: 0.30,
                delay: 0,
                options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction]
            ) {
                old?.frame = self.view.bounds.offsetBy(dx: width, dy: 0)
                self.coverDimView.alpha = 0.25
            } completion: { [weak self] _ in
                guard let self else { return }
                old?.removeFromSuperview()
                next.frame = self.view.bounds
                self.removeCoverOverlay()
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
    var onOutsideTap: ((CGPoint) -> Void)?

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
            onInlineReviewTap: onInlineReviewTap,
            onOutsideTap: onOutsideTap
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
    /// 点击页面除段评入口外的任意位置（收起段评弹层）。
    var onOutsideTap: ((CGPoint) -> Void)?

    func makeUIViewController(context: Context) -> UIViewController {
        let reader = makeReader(for: config.currentPageAnim)
        reader.reviewEnabled = reviewEnabled
        reader.onReviewTap = onReviewTap
        reader.reviewCounts = reviewCounts
        reader.inlineReviewMarkers = inlineReviewMarkers
        reader.onInlineReviewTap = onInlineReviewTap
        reader.onOutsideTap = onOutsideTap
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
        reader.onOutsideTap = onOutsideTap
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
            // 档位2：系统 UIPageViewController .pageCurl + 双面页 ——
            // iPhone 自带 Books App 同款书页翻卷，带纸张弯曲弧度与折痕阴影。
            return NativePageReader(
                pages: pages,
                config: config,
                initialIndex: currentIndex,
                transitionStyle: .pageCurl,
                doubleSided: true
            )
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
