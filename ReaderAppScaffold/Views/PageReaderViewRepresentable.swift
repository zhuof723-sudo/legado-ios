import SwiftUI
import UIKit
import LegadoRuleEngine

// MARK: - 单页内容视图

/// 单张书页。文字直接取自分页产出的 ReaderPage.attributed（TextKit1 测量与
/// 渲染同源），上屏零改动，杜绝分页/显示排版不一致引起的字体错位。
final class PageContentView: UIView, UITextViewDelegate, UIGestureRecognizerDelegate {
    private let page: ReaderPage
    let config: ReaderConfig
    /// 点击评论按钮的回调（参数：段落索引）
    var onReviewTap: ((Int) -> Void)?
    /// 点击内嵌段评图时回传 marker id。
    var onInlineReviewTap: ((Int) -> Void)?
    /// 点击页面上除段评入口以外的任意位置（用于收起段评弹层/呼出菜单），回传点击坐标。
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

    init(page: ReaderPage, config: ReaderConfig) {
        self.page = page
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
        _ = textView.layoutManager // 强制 TextKit1：与分页器共用同一排版引擎

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

        applyPage(page)
    }

    private func applyPage(_ newPage: ReaderPage) {
        textView.attributedText = newPage.attributed
        textView.textColor = UIColor(config.currentTheme.textColor)
    }

    /// 仅刷新主题背景与边距，不触碰文字内容（避免菜单弹出时文字重排闪烁）。
    func refreshAppearance() {
        backgroundColor = UIColor(config.currentTheme.background)
        contentTopConstraint?.constant = CGFloat(config.paddingTop)
        contentLeadingConstraint?.constant = CGFloat(config.paddingH)
        contentTrailingConstraint?.constant = -CGFloat(config.paddingH)
        contentBottomConstraint?.constant = -CGFloat(config.paddingBottom)
        textView.textColor = UIColor(config.currentTheme.textColor)
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

    func textView(
        _ textView: UITextView,
        shouldInteractWith URL: URL,
        in characterRange: NSRange,
        interaction: UITextItemInteraction
    ) -> Bool {
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

/// 容器层的公共回调解包：把 SwiftUI 闭包分发给每张书页。
struct ReaderPageCallbacks {
    var onReviewTap: ((Int) -> Void)?
    var reviewCounts: [Int: Int]
    var onInlineReviewTap: ((Int) -> Void)?
    var onOutsideTap: ((CGPoint) -> Void)?
}

protocol PageReaderContainer: AnyObject {
    var pages: [ReaderPage] { get set }
    var config: ReaderConfig { get }
    var currentIndex: Int { get set }
    var onPageChanged: ((Int) -> Void)? { get set }
    var callbacks: ReaderPageCallbacks { get set }
    /// 刷新每个独立页面的背景和文字颜色（不动文字内容）。
    func refreshAppearance()
    func goToPage(_ index: Int, animated: Bool)
    func updatePages(_ newPages: [ReaderPage], keepIndex: Int)
}

extension PageReaderContainer {
    func makePage(at index: Int) -> PageContentView {
        let pageView = PageContentView(page: pages[index], config: config)
        pageView.onReviewTap = callbacks.onReviewTap
        pageView.onInlineReviewTap = callbacks.onInlineReviewTap
        pageView.onOutsideTap = callbacks.onOutsideTap
        pageView.frame = viewBoundsForPages()
        pageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        return pageView
    }

    func viewBoundsForPages() -> CGRect {
        (self as? UIViewController)?.view.bounds ?? .zero
    }
}

// MARK: - 1. 自由垂直滚动：整章一个 TextKit1 连续排版流

/// 滚动模式：整章富文本放进一个连续排版的 UITextView，页面起点由分页
/// 产物的 startOffset 换算。不再用“每页一个独立 PageContentView 叠进
/// StackView”的拼法（旧方案页与页之间会叠加出双倍边距的空白断层），
/// 因此滚动模式的断行、段评气泡、页边界都与翻页模式完全一致。
final class FreeScrollFlowController: UIViewController, UITextViewDelegate, UIGestureRecognizerDelegate {
    private(set) var chapterText: NSAttributedString
    private let config: ReaderConfig
    private let pageOffsets: [Int]

    private var textView = UITextView()

    var onOutsideTap: ((CGPoint) -> Void)?
    var onReviewTap: ((Int) -> Void)?
    var onInlineReviewTap: ((Int) -> Void)?
    /// 滚动过程中实时同步页码。
    var onScrollPageChanged: ((Int) -> Void)?
    private(set) var currentIndex = 0
    /// 与分页产物对应的页面起点 Y（layout 完成后由容器写入）。
    private(set) var pageOrigins: [CGFloat] = []

    init(pages: [ReaderPage], config: ReaderConfig) {
        // 拼接整章连续排版流：页与页之间补一个换行，保证跨页段落
        // 在滚动流里有自然的段距，且首页起点计算不受上一页末行影响。
        let joined = NSMutableAttributedString()
        var offsets: [Int] = []
        var consumed = 0
        for (i, page) in pages.enumerated() {
            offsets.append(consumed + page.startOffset)
            consumed += page.startOffset + page.attributed.length
            joined.append(page.attributed)
            if i + 1 < pages.count {
                // 换行会带上一页末段的段落样式，保证段距连续。
                let newline = NSAttributedString(
                    string: "\n",
                    attributes: page.attributed.length > 0
                        ? page.attributed.attributes(at: page.attributed.length - 1, effectiveRange: nil)
                        : nil
                )
                joined.append(newline)
                consumed += 1
            }
        }
        self.chapterText = joined
        self.pageOffsets = offsets
        self.config = config
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(config.currentTheme.background)

        let container = NSTextContainer(size: CGSize(width: 1, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        container.lineBreakMode = .byWordWrapping
        container.heightTracksTextView = false

        let storage = NSTextStorage(attributedString: chapterText)
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(container)

        textView = UITextView(frame: .zero, textContainer: container)
        // UITextView 初始化后仍允许配置属性（frame/textContainer 在 init 时给定）
        textView.backgroundColor = .clear
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = true
        textView.textContainerInset = .zero
        textView.showsVerticalScrollIndicator = false
        textView.showsHorizontalScrollIndicator = false
        textView.alwaysBounceVertical = false
        textView.contentInsetAdjustmentBehavior = .never
        textView.delegate = self
        textView.linkTextAttributes = [
            .foregroundColor: UIColor.systemGray,
            .underlineColor: UIColor.clear
        ]
        _ = textView.layoutManager // TextKit1，与分页器同一排版引擎

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tap.cancelsTouchesInView = false
        tap.delegate = self
        textView.addGestureRecognizer(tap)

        textView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(textView)
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: view.topAnchor),
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    /// 视图几何就绪后：按当前页宽重排并计算每页起点的 Y 坐标。
    func recomputePageOrigins(pageWidth: CGFloat, pageHeight: CGFloat) {
        guard pageWidth > 1 else { return }
        let container = textView.textContainer
        container.size = CGSize(width: pageWidth, height: .greatestFiniteMagnitude)

        textView.layoutManager.ensureLayout(for: container)
        var origins: [CGFloat] = []
        origins.reserveCapacity(pageOffsets.count)
        for offset in pageOffsets {
            guard offset < chapterText.length else
                { origins.append(origins.last ?? 0); continue }
            let glyphIndex = textView.layoutManager.glyphIndexForCharacter(at: offset)
            let rect = textView.layoutManager.boundingRect(
                forGlyphRange: NSRange(location: glyphIndex, length: 0),
                in: container
            )
            origins.append(max(0, rect.minY))
        }
        pageOrigins = origins
    }

    /// 滚动位置 → 页索引（最近一次越过起点即算当前页）。
    private func pageIndex(atOffset y: CGFloat) -> Int {
        guard pageOrigins.count > 1 else { return 0 }
        var index = 0
        for (i, origin) in pageOrigins.enumerated() where origin <= y + 1 {
            index = i
        }
        return index
    }

    func scrollTo(page index: Int, animated: Bool) {
        guard index >= 0, index < pageOrigins.count else { return }
        textView.setContentOffset(CGPoint(x: 0, y: pageOrigins[index]), animated: animated)
        if currentIndex != index {
            currentIndex = index
            onScrollPageChanged?(index)
        }
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let index = pageIndex(atOffset: scrollView.contentOffset.y)
        if index != currentIndex {
            currentIndex = index
            onScrollPageChanged?(index)
        }
    }

    func updateAppearance(background: UIColor, textColor: UIColor) {
        view.backgroundColor = background
        textView.textColor = textColor
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else { return }
        let location = gesture.location(in: textView)
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

    func textView(
        _ textView: UITextView,
        shouldInteractWith URL: URL,
        in characterRange: NSRange,
        interaction: UITextItemInteraction
    ) -> Bool {
        if let paragraphIndex = ReviewLinkHelper.paragraphIndex(from: URL) {
            onReviewTap?(paragraphIndex)
            return false
        }
        if let markerID = ReviewLinkHelper.markerID(from: URL) {
            onInlineReviewTap?(markerID)
            return false
        }
        return false
    }
}

final class FreeScrollReader: UIViewController, PageReaderContainer {
    var pages: [ReaderPage] = []
    let config: ReaderConfig
    var currentIndex: Int = 0
    var onPageChanged: ((Int) -> Void)?
    var callbacks = ReaderPageCallbacks()

    private var flow: FreeScrollFlowController?
    private var needsInitialScroll = true
    private var lastBoundsSize: CGSize = .zero

    init(pages: [ReaderPage], config: ReaderConfig, initialIndex: Int) {
        self.pages = pages
        self.config = config
        self.currentIndex = initialIndex
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        rebuildFlow()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let size = view.bounds.size
        guard size.width > 0, size.height > 0, !pages.isEmpty else { return }

        if lastBoundsSize != size {
            lastBoundsSize = size
            applyFlowGeometry()
        }
        if needsInitialScroll, let flow {
            let safe = min(max(currentIndex, 0), pages.count - 1)
            flow.recomputePageOrigins(
                pageWidth: size.width - config.paddingH * 2,
                pageHeight: size.height - config.paddingTop - config.paddingBottom
            )
            // 重新计算后立即跳到目标页（不触发动画）。
            flow.scrollTo(page: safe, animated: false)
            currentIndex = safe
            needsInitialScroll = false
        }
    }

    private func rebuildFlow() {
        flow?.willMove(toParent: nil)
        flow?.removeFromParent()
        flow = nil
        guard !pages.isEmpty else { return }

        let child = FreeScrollFlowController(pages: pages, config: config)
        child.onOutsideTap = callbacks.onOutsideTap
        child.onReviewTap = callbacks.onReviewTap
        child.onInlineReviewTap = callbacks.onInlineReviewTap
        child.onScrollPageChanged = { [weak self] index in
            guard let self else { return }
            self.currentIndex = index
            self.onPageChanged?(index)
        }
        child.view.frame = view.bounds
        child.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(child.view)
        addChild(child)
        child.didMove(toParent: self)
        flow = child
        lastBoundsSize = .zero
        needsInitialScroll = true
        view.setNeedsLayout()
    }

    private func applyFlowGeometry() {
        guard let flow else { return }
        let size = view.bounds.size
        flow.recomputePageOrigins(
            pageWidth: size.width - config.paddingH * 2,
            pageHeight: size.height - config.paddingTop - config.paddingBottom
        )
    }

    func refreshAppearance() {
        flow?.updateAppearance(
            background: UIColor(config.currentTheme.background),
            textColor: UIColor(config.currentTheme.textColor)
        )
    }

    func updatePages(_ newPages: [ReaderPage], keepIndex: Int) {
        pages = newPages
        let safe = min(max(keepIndex, 0), max(newPages.count - 1, 0))
        currentIndex = safe
        rebuildFlow()
    }

    func goToPage(_ index: Int, animated: Bool) {
        guard index >= 0, index < pages.count else { return }
        flow?.scrollTo(page: index, animated: animated)
        currentIndex = index
        if !animated { onPageChanged?(index) }
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
    var pages: [ReaderPage] = []
    let config: ReaderConfig
    var currentIndex: Int = 0
    var onPageChanged: ((Int) -> Void)?
    var callbacks = ReaderPageCallbacks()

    init(
        pages: [ReaderPage],
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
        view.backgroundColor = UIColor(config.currentTheme.background)
    }

    func updatePages(_ newPages: [ReaderPage], keepIndex: Int) {
        pages = newPages
        let safe = min(max(keepIndex, 0), max(newPages.count - 1, 0))
        currentIndex = safe
        if !newPages.isEmpty {
            setViewControllers([makeViewController(at: safe)], direction: .forward, animated: false)
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
        return IndexedPageViewController(index: index, pageView: makePage(at: index))
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

// MARK: - 滑动（左右跟手推书页）

/// 滑动翻页：屏幕就是书缝，手指推的是屏幕边缘那张真书页。
/// 左滑 = 把当前页往左推走，右边露出下一页（下一页永远在右）；
/// 右滑 = 把上一页从左边推回来盖住当前页（上一页永远在左）。
/// 两个方向都始终有真纸页跟手，方向由手势位移实时决定、可中途换向。
final class SlidePageReader: UIViewController, PageReaderContainer, UIGestureRecognizerDelegate {
    var pages: [ReaderPage] = []
    let config: ReaderConfig
    var currentIndex: Int = 0
    var onPageChanged: ((Int) -> Void)?
    var callbacks = ReaderPageCallbacks()

    private var currentPageView: PageContentView?
    private var isTransitioning = false
    private var interactivePage: PageContentView?
    private var interactiveDirection = 0
    private var interactiveTargetIndex = 0
    private var isTrackingPan = false

    init(pages: [ReaderPage], config: ReaderConfig, initialIndex: Int) {
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
        if !isTransitioning, let page = currentPageView, page.frame != view.bounds {
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
        // 只把明显的左右手势当作翻页，避免上下拖动时误触发。
        return abs(velocity.x) > abs(velocity.y) * 1.15
    }

    /// 屏幕物理圆角（参考项目取 displayCornerRadius 的做法）。
    private var screenCornerRadius: CGFloat {
        let r = (UIScreen.main.value(forKey: "displayCornerRadius") as? CGFloat) ?? 0
        return r > 0 ? r : 12
    }

    private var movingPage: UIView?

    /// 保证跟手的书页视图已加入层级并铺满。
    private func ensureMovingPage() -> UIView? {
        guard let page = interactivePage else { return nil }
        if page.superview == nil {
            view.addSubview(page)
        }
        page.frame = view.bounds
        if let moving = movingPage, moving !== page {
            view.bringSubviewToFront(page)
        }
        return page
    }

    private func beginInteractiveIfNeeded(direction: Int, target: Int) {
        guard interactivePage == nil, !isTransitioning else { return }
        guard target >= 0, target < pages.count else { return }
        interactiveTargetIndex = target
        interactiveDirection = direction
        interactivePage = makePage(at: target)
        isTrackingPan = true
        ensureMovingPage()
        if let moving = interactivePage {
            movingPage = moving
            // 跟手页带屏幕圆角与投影，像一整张真书页。
            moving.layer.cornerRadius = screenCornerRadius
            moving.layer.masksToBounds = true
            moving.layer.shadowColor = UIColor.black.cgColor
            moving.layer.shadowOpacity = 0.3
            moving.layer.shadowRadius = 14
            moving.layer.shadowOffset = .zero
            moving.layer.shouldRasterize = true
            moving.layer.rasterizationScale = UIScreen.main.scale
        }
    }

    /// 断页换向：手指越过起点反向推时，把跟手页换成另一侧的邻居页。
    private func switchInteractiveDirectionIfNeeded(translationX: CGFloat) {
        guard isTrackingPan, let _ = interactivePage else { return }
        let width = max(view.bounds.width, 1)
        var direction = interactiveDirection
        if translationX < 0 && interactiveDirection < 0 {
            direction = 1
        } else if translationX > 0 && interactiveDirection > 0 {
            direction = -1
        }
        guard direction != interactiveDirection else { return }

        let target = currentIndex + direction
        guard target >= 0, target < pages.count else { return }

        // 丢弃当前跟手页，换另一侧邻居页做跟手。
        interactivePage?.removeFromSuperview()
        interactivePage = nil
        interactiveDirection = direction
        interactiveTargetIndex = target
        interactivePage = makePage(at: target)
        ensureMovingPage()
        movingPage = interactivePage
        if let moving = interactivePage {
            moving.layer.cornerRadius = screenCornerRadius
            moving.layer.masksToBounds = true
            moving.layer.shadowColor = UIColor.black.cgColor
            moving.layer.shadowOpacity = 0.3
            moving.layer.shadowRadius = 14
            moving.layer.shadowOffset = .zero
            moving.layer.shouldRasterize = true
            moving.layer.rasterizationScale = UIScreen.main.scale
        }
        // 提示宽度供 applyInteractiveProgress 使用
        _ = width
    }

    private func applyInteractiveProgress(_ progress: CGFloat) {
        guard let moving = interactivePage else { return }
        let width = max(view.bounds.width, 1)

        if interactiveDirection > 0 {
            // 前进：下一页从屏幕右缘推入，当前页原地静止。
            moving.frame = view.bounds.offsetBy(dx: width * (1 - progress), dy: 0)
        } else {
            // 后退：上一页从屏幕左缘推入，盖住当前页。
            moving.frame = view.bounds.offsetBy(dx: -width * (1 - progress), dy: 0)
        }
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let width = max(view.bounds.width, 1)
        let translationX = gesture.translation(in: view).x

        switch gesture.state {
        case .began:
            guard !isTransitioning else { return }
            // .began 阶段位移和速度都为 0，不能在这里预判方向；
            // 等第一个 .changed 事件再决定推哪一页。
            isTrackingPan = true

        case .changed:
            guard !isTransitioning, isTrackingPan else { return }
            if interactivePage == nil {
                let direction: Int = translationX < 0 ? 1 : -1
                let target = currentIndex + direction
                guard target >= 0, target < pages.count else { return }
                beginInteractiveIfNeeded(direction: direction, target: target)
            } else {
                switchInteractiveDirectionIfNeeded(translationX: translationX)
            }
            let progress: CGFloat
            if interactiveDirection > 0 {
                progress = min(max(-translationX / width, 0), 1)
            } else {
                progress = min(max(translationX / width, 0), 1)
            }
            applyInteractiveProgress(progress)

        case .ended, .cancelled, .failed:
            defer {
                isTrackingPan = false
            }
            guard !isTransitioning, let moving = interactivePage else { return }
            let progress: CGFloat
            if interactiveDirection > 0 {
                progress = min(max(-translationX / width, 0), 1)
            } else {
                progress = min(max(translationX / width, 0), 1)
            }
            let finish = progress > 0.32 || abs(gesture.velocity(in: view).x) > 700
            completeInteractivePan(progress: progress, finish: finish && gesture.state == .ended)

        default:
            break
        }
    }

    private func completeInteractivePan(progress: CGFloat, finish: Bool) {
        guard let moving = interactivePage else {
            isTransitioning = false
            return
        }
        let target = interactiveTargetIndex
        let direction = interactiveDirection
        isTransitioning = true

        if finish {
            applyInteractiveProgress(1)
            UIView.animate(
                withDuration: 0.18,
                delay: 0,
                options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction]
            ) {
                self.applyInteractiveProgress(1)
            } completion: { [weak self] _ in
                guard let self else { return }
                self.currentPageView?.removeFromSuperview()
                moving.frame = self.view.bounds
                moving.layer.shadowOpacity = 0
                moving.layer.cornerRadius = 0
                moving.layer.shouldRasterize = false
                self.currentPageView = moving as? PageContentView
                self.currentIndex = target
                self.interactivePage = nil
                self.movingPage = nil
                self.interactiveDirection = 0
                self.isTransitioning = false
                self.onPageChanged?(target)
            }
        } else {
            applyInteractiveProgress(0)
            UIView.animate(
                withDuration: 0.18,
                delay: 0,
                options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction]
            ) {
                self.applyInteractiveProgress(0)
            } completion: { [weak self] _ in
                guard let self else { return }
                moving.removeFromSuperview()
                self.interactivePage = nil
                self.movingPage = nil
                self.interactiveDirection = 0
                self.isTransitioning = false
            }
        }
        _ = direction
    }

    private func makePage(at index: Int) -> PageContentView {
        let pageView = PageContentView(page: pages[index], config: config)
        pageView.onReviewTap = callbacks.onReviewTap
        pageView.onInlineReviewTap = callbacks.onInlineReviewTap
        pageView.onOutsideTap = callbacks.onOutsideTap
        pageView.frame = view.bounds
        pageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        return pageView
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
        if direction >= 0 {
            // 前进：新页从右缘滑入。
            next.layer.cornerRadius = screenCornerRadius
            next.layer.masksToBounds = true
            next.layer.shadowColor = UIColor.black.cgColor
            next.layer.shadowOpacity = 0.3
            next.layer.shadowRadius = 14
            next.layer.shadowOffset = .zero
            view.addSubview(next)
            next.frame = view.bounds.offsetBy(dx: width, dy: 0)
            UIView.animate(
                withDuration: 0.24,
                delay: 0,
                options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction]
            ) {
                next.frame = self.view.bounds
            } completion: { [weak self] _ in
                guard let self else { return }
                old?.removeFromSuperview()
                next.frame = self.view.bounds
                next.layer.shadowOpacity = 0
                next.layer.cornerRadius = 0
                self.currentPageView = next
                self.currentIndex = index
                self.isTransitioning = false
                self.onPageChanged?(index)
            }
        } else {
            // 后退：新页从左缘滑入盖住当前页。
            next.layer.cornerRadius = screenCornerRadius
            next.layer.masksToBounds = true
            view.addSubview(next)
            next.frame = view.bounds.offsetBy(dx: -width, dy: 0)
            UIView.animate(
                withDuration: 0.24,
                delay: 0,
                options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction]
            ) {
                next.frame = self.view.bounds
            } completion: { [weak self] _ in
                guard let self else { return }
                old?.removeFromSuperview()
                next.frame = self.view.bounds
                next.layer.cornerRadius = 0
                self.currentPageView = next
                self.currentIndex = index
                self.isTransitioning = false
                self.onPageChanged?(index)
            }
        }
    }

    func refreshAppearance() {
        view.backgroundColor = UIColor(config.currentTheme.background)
        currentPageView?.refreshAppearance()
        interactivePage?.refreshAppearance()
    }

    func updatePages(_ newPages: [ReaderPage], keepIndex: Int) {
        pages = newPages
        guard !newPages.isEmpty else {
            currentPageView?.removeFromSuperview()
            currentPageView = nil
            currentIndex = 0
            return
        }
        let safe = min(max(keepIndex, 0), newPages.count - 1)
        showPage(at: safe, animated: false, direction: 1)
    }

    func goToPage(_ index: Int, animated: Bool) {
        guard index >= 0, index < pages.count, index != currentIndex, !isTransitioning else { return }
        let direction = index > currentIndex ? 1 : -1
        showPage(at: index, animated: animated, direction: direction)
    }
}

// MARK: - 无动画（瞬时切换）

final class InstantPageReader: UIViewController, PageReaderContainer, UIGestureRecognizerDelegate {
    var pages: [ReaderPage] = []
    let config: ReaderConfig
    var currentIndex: Int = 0
    var onPageChanged: ((Int) -> Void)?
    var callbacks = ReaderPageCallbacks()

    private var currentPageView: PageContentView?

    init(pages: [ReaderPage], config: ReaderConfig, initialIndex: Int) {
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
    }

    func updatePages(_ newPages: [ReaderPage], keepIndex: Int) {
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
    let pages: [ReaderPage]
    let config: ReaderConfig
    @Binding var currentIndex: Int
    var onPageChanged: ((Int) -> Void)?
    /// 是否启用兼容模式段评按钮（无内嵌段评图的书源）
    var legacyReviewEnabled: Bool = false
    var onReviewTap: ((Int) -> Void)?
    var reviewCounts: [Int: Int] = [:]
    var onInlineReviewTap: ((Int) -> Void)?
    /// 点击页面除段评入口外的任意位置（收起段评弹层/呼出菜单）。
    var onOutsideTap: ((CGPoint) -> Void)?

    func makeUIViewController(context: Context) -> UIViewController {
        let reader = makeReader(for: config.currentPageAnim)
        applyCallbacks(to: reader)
        return reader as! UIViewController
    }

    private func applyCallbacks(to reader: PageReaderContainer) {
        reader.callbacks = ReaderPageCallbacks(
            onReviewTap: onReviewTap,
            reviewCounts: reviewCounts,
            onInlineReviewTap: onInlineReviewTap,
            onOutsideTap: onOutsideTap
        )
        reader.onPageChanged = { index in
            DispatchQueue.main.async {
                guard currentIndex != index else { return }
                currentIndex = index
                onPageChanged?(index)
            }
        }
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        guard let reader = uiViewController as? PageReaderContainer else { return }

        // 配置变化只刷新颜色/边距，不重建文字，避免菜单弹出时文字重排闪烁。
        reader.refreshAppearance()

        // 回调可能随 SwiftUI 状态更新（闭包捕获最新值），同步给容器。
        reader.callbacks.onReviewTap = onReviewTap
        reader.callbacks.reviewCounts = reviewCounts
        reader.callbacks.onInlineReviewTap = onInlineReviewTap
        reader.callbacks.onOutsideTap = onOutsideTap
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
            // 仿真：系统 UIPageViewController .pageCurl + 双面页 ——
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
