import SwiftUI
import UIKit
import LegadoRuleEngine

// MARK: - 单页内容视图

/// 单张书页。文字直接取自分页产出的 ReaderPage.attributed（TextKit1 测量与
/// 渲染同源），上屏零改动，杜绝分页/显示排版不一致引起的字体错位。
/// 注意：正文 run 不带 foregroundColor，颜色由 textView.textColor 供给，
/// 主题/夜间切换只改 textColor 即可热刷新，不需要重新分页。
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
    /// 显式 TextKit1 栈：与分页器共用同一排版引擎，断行完全一致，
    /// 也避开 iOS16+ UITextView 访问 layoutManager 触发的 TextKit2 混合模式。
    private let textStorage = NSTextStorage()
    private let layoutManager = NSLayoutManager()
    private let textContainer: NSTextContainer
    private let textView: UITextView
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
        let container = NSTextContainer(size: CGSize(
            width: 1,
            height: CGFloat.greatestFiniteMagnitude
        ))
        container.lineFragmentPadding = 0
        container.lineBreakMode = NSLineBreakMode.byWordWrapping
        container.widthTracksTextView = true
        container.heightTracksTextView = false
        self.textContainer = container
        // 先接好 TextKit1 链条，再让 UITextView 挂上来（Yuedu 同款做法），
        // 避免 UITextView 收到“无主”container 时自建 NSLayoutManager。
        layoutManager.addTextContainer(container)
        textStorage.addLayoutManager(layoutManager)
        self.textView = UITextView(frame: .zero, textContainer: container)
        super.init(frame: .zero)

        setupViews()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setupViews() {
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

        applyPage(page)
    }

    private func applyPage(_ newPage: ReaderPage) {
        textView.attributedText = newPage.attributed
        // 颜色不烘焙进 attributed run；textColor 是全文默认前景色，
        // 主题切换只需改它（改色不触发重新布局，只重绘）。
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

    /// 离屏快照：翻页拖动时移动的是这张图（参考 Yuedu renderSnapshot），
    /// 拖动期间不再逐帧合成活的 TextKit 视图，这是滑动模式跟手的关键。
    func makeSnapshotImage() -> UIImage? {
        setNeedsLayout()
        layoutIfNeeded()
        guard bounds.width > 1, bounds.height > 1 else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        // 2x 足够：快照只在 0.2s 动画里出现，肉眼看不出与 3x 的差别，
        // 内存和渲染成本减半。
        format.scale = min(UIScreen.main.scale, 2)
        return UIGraphicsImageRenderer(bounds: bounds, format: format).image { renderer in
            layer.render(in: renderer.cgContext)
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
    var reviewCounts: [Int: Int] = [:]
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
    private var containerWidth: CGFloat = 0

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

        let container = NSTextContainer(size: CGSize(
            width: 1,
            height: CGFloat.greatestFiniteMagnitude
        ))
        container.lineFragmentPadding = 0
        container.lineBreakMode = NSLineBreakMode.byWordWrapping
        container.heightTracksTextView = false

        let storage = NSTextStorage(attributedString: chapterText)
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(container)

        textView = UITextView(frame: .zero, textContainer: container)
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
        // 颜色由 textColor 供给（不烘焙进 run），主题热刷新可用。
        textView.textColor = UIColor(config.currentTheme.textColor)

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
    /// 文字颜色不参与排版，主题切换不会走到这里。
    func recomputePageOrigins(pageWidth: CGFloat) {
        guard pageWidth > 1, pageWidth != containerWidth else { return }
        containerWidth = pageWidth
        let container = textView.textContainer
        container.size = CGSize(width: pageWidth, height: CGFloat.greatestFiniteMagnitude)

        textView.layoutManager.ensureLayout(for: container)
        var origins: [CGFloat] = []
        origins.reserveCapacity(pageOffsets.count)
        for offset in pageOffsets {
            if offset < chapterText.length {
                let glyphIndex = textView.layoutManager.glyphIndexForCharacter(at: offset)
                let rect = textView.layoutManager.boundingRect(
                    forGlyphRange: NSRange(location: glyphIndex, length: 0),
                    in: container
                )
                origins.append(max(0, rect.minY))
            } else if let last = origins.last {
                origins.append(last)
            } else {
                origins.append(0)
            }
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

        // 页宽变化才重算起点（rotate/分栏）；主题切换不再触发这里。
        let pageWidth = size.width - config.paddingH * 2
        if lastBoundsSize != size {
            lastBoundsSize = size
            flow?.recomputePageOrigins(pageWidth: pageWidth)
        }
        if needsInitialScroll, let flow {
            let safe = min(max(currentIndex, 0), pages.count - 1)
            flow.scrollTo(page: safe, animated: false)
            currentIndex = safe
            needsInitialScroll = false
        }
    }

    private func rebuildFlow() {
        if let old = flow {
            old.willMove(toParent: nil)
            old.view.removeFromSuperview()
            old.removeFromParent()
        }
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

// MARK: - 滑动（左右跟手推书页，快照驱动）

/// 滑动翻页：屏幕就是书缝，手指推的是屏幕边缘那张书页。
/// 左滑 = 把当前页往左推走，右边露出下一页（下一页永远在右）；
/// 右滑 = 把上一页从左边推回来盖住当前页（上一页永远在左）。
///
/// 性能要点（参考 Yuedu CoreTextPagedView）：拖动期间移动的是**预渲染快照**
/// （UIGraphicsImageRenderer 一次出图），不是活的 TextKit 视图。
/// 每帧只做 frame 位移，没有离屏文字合成，拖动因此不掉帧。
/// 快照在方向确定时一次生成，中途换向时重建一次，均为一次性成本。
final class SlidePageReader: UIViewController, PageReaderContainer, UIGestureRecognizerDelegate {
    var pages: [ReaderPage] = []
    let config: ReaderConfig
    var currentIndex: Int = 0
    var onPageChanged: ((Int) -> Void)?
    var callbacks = ReaderPageCallbacks()

    private var currentPageView: PageContentView?

    // 覆盖动画三件套（Yuedu 同款）：快照层(圆角) / 投影容器 / 旧页渐暗层。
    private let coverOverlayView = UIView()
    private let coverIncomingImageView = UIImageView()
    private let coverShadowView = UIView()
    private let coverDimView = UIView()
    private var overlayInstalled = false

    private var interactivePage: PageContentView?
    private var interactiveDirection = 0
    private var interactiveTargetIndex = 0
    private var isTransitioning = false
    private var isTrackingPan = false

    private enum GestureConstants {
        static let initialTranslationThreshold: CGFloat = 18.0
        static let commitProgressRatio: CGFloat = 0.34
        static let commitVelocityThreshold: CGFloat = 560.0
        static let settleAnimationDuration: TimeInterval = 0.22
        static let maxDimmingAlpha: CGFloat = 0.35
    }

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
        installCoverOverlay()
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

    /// 屏幕物理圆角（Yuedu 同款 displayCornerRadius）。
    private var screenCornerRadius: CGFloat {
        let r = (UIScreen.main.value(forKey: "displayCornerRadius") as? CGFloat) ?? 0
        return r > 0 ? r : 12
    }

    // MARK: 覆盖层搭建（一次性，常驻隐藏）

    private func installCoverOverlay() {
        guard !overlayInstalled else { return }
        overlayInstalled = true

        coverOverlayView.frame = view.bounds
        coverOverlayView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        coverOverlayView.isHidden = true
        coverOverlayView.backgroundColor = .clear
        coverOverlayView.isUserInteractionEnabled = false
        view.addSubview(coverOverlayView)

        // Shadow view 在快照下面，不被裁剪，允许投影溢出到屏幕外。
        coverShadowView.backgroundColor = .clear
        coverShadowView.layer.shadowColor = UIColor.black.cgColor
        coverShadowView.layer.shadowOpacity = 0.3
        coverShadowView.layer.shadowRadius = 14
        coverShadowView.layer.shadowOffset = .zero
        coverShadowView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        coverOverlayView.addSubview(coverShadowView)

        coverIncomingImageView.contentMode = .scaleToFill
        coverIncomingImageView.clipsToBounds = true
        coverIncomingImageView.layer.cornerRadius = screenCornerRadius
        coverIncomingImageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        coverShadowView.addSubview(coverIncomingImageView)

        // 渐暗层盖在“旧页快照”上（后退时旧页逐渐变暗）。
        coverDimView.backgroundColor = .black
        coverDimView.alpha = 0
        coverDimView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        coverDimView.isUserInteractionEnabled = false
        coverOverlayView.addSubview(coverDimView)
    }

    private func showOverlay() {
        coverOverlayView.isHidden = false
    }

    private func hideOverlay() {
        coverOverlayView.isHidden = true
        coverIncomingImageView.image = nil
        coverShadowView.layer.shadowPath = nil
        coverDimView.alpha = 0
    }

    // MARK: 手势

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let width = max(view.bounds.width, 1)
        let translationX = gesture.translation(in: view).x
        let velocityX = gesture.velocity(in: view).x

        switch gesture.state {
        case .began:
            guard !isTransitioning else {
                gesture.state = .cancelled
                return
            }
            isTrackingPan = true
            // 取消残留动画，方向未定前不显示覆盖层。
            coverOverlayView.layer.removeAllAnimations()
            coverIncomingImageView.layer.removeAllAnimations()
            coverDimView.layer.removeAllAnimations()
            coverDimView.alpha = 0

        case .changed:
            guard !isTransitioning, isTrackingPan else { return }
            if interactivePage == nil {
                // 方向阈值确认后才启动（Yuedu initialTranslationThreshold），
                // 避免轻触或极小位移就生成快照。
                guard abs(translationX) >= GestureConstants.initialTranslationThreshold else { return }
                let direction: Int = translationX < 0 ? 1 : -1
                let target = currentIndex + direction
                guard target >= 0, target < pages.count else { return }
                beginInteractive(direction: direction, target: target)
            } else {
                updateInteractiveProgress(translationX: translationX, width: width)
            }

        case .ended, .cancelled, .failed:
            defer { isTrackingPan = false }
            guard !isTransitioning, interactivePage != nil else {
                hideOverlay()
                return
            }
            let progress = currentProgress(translationX: translationX, width: width)
            let shouldCommit = progress > GestureConstants.commitProgressRatio
                || abs(velocityX) > GestureConstants.commitVelocityThreshold
            completeInteractive(
                commit: shouldCommit && gesture.state == .ended,
                translationX: translationX,
                width: width
            )

        default:
            break
        }
    }

    /// 启动交互翻页：构建目标页真视图（备用）+ 快照 + 覆盖层。
    private func beginInteractive(direction: Int, target: Int) {
        interactiveDirection = direction
        interactiveTargetIndex = target
        interactivePage = makePage(at: target)
        isTransitioning = true
        showOverlay()

        let width = max(view.bounds.width, 1)
        if direction > 0 {
            // 前进：目标页快照从右缘进入，压在当前页上。
            let snap = interactivePage?.makeSnapshotImage()
            coverIncomingImageView.image = snap
            coverIncomingImageView.frame = view.bounds
            coverDimView.frame = view.bounds
            coverDimView.alpha = 0
            // 起始位置在屏幕右侧外。
            coverIncomingImageView.frame.origin.x = width
            // 投影路径跟随快照（shadowPath 让投影不用实时计算形状）。
            coverShadowView.frame = coverIncomingImageView.frame
            let shadowHeight = coverIncomingImageView.frame.height
            coverShadowView.layer.shadowPath = UIBezierPath(
                roundedRect: coverIncomingImageView.bounds,
                cornerRadius: screenCornerRadius
            ).cgPath
            _ = shadowHeight
        } else {
            // 后退：目标页快照从左缘进入；当前页渐暗。
            let snap = interactivePage?.makeSnapshotImage()
            coverIncomingImageView.image = snap
            coverIncomingImageView.frame = view.bounds
            coverDimView.frame = view.bounds
            coverDimView.alpha = 0
            coverIncomingImageView.frame.origin.x = -width
            coverShadowView.frame = coverIncomingImageView.frame
            coverShadowView.layer.shadowPath = UIBezierPath(
                roundedRect: coverIncomingImageView.bounds,
                cornerRadius: screenCornerRadius
            ).cgPath
        }
    }

    private func currentProgress(translationX: CGFloat, width: CGFloat) -> CGFloat {
        guard interactivePage != nil else { return 0 }
        if interactiveDirection > 0 {
            return min(max(-translationX / width, 0), 1)
        }
        return min(max(translationX / width, 0), 1)
    }

    /// 快照层跟随手指：每帧只改 frame 和 alpha，无任何文字排版。
    private func updateInteractiveProgress(translationX: CGFloat, width: CGFloat) {
        let progress: CGFloat
        if interactiveDirection > 0 {
            progress = min(max(-translationX / width, 0), 1)
        } else {
            progress = min(max(translationX / width, 0), 1)
        }

        if interactiveDirection > 0 {
            // 前进：快照从右缘滑入。
            coverIncomingImageView.frame.origin.x = width * (1 - progress)
        } else {
            // 后退：快照从左缘滑入，渐暗层加深。
            coverIncomingImageView.frame.origin.x = -width * (1 - progress)
            coverDimView.alpha = progress * GestureConstants.maxDimmingAlpha
        }
        coverShadowView.frame.origin.x = coverIncomingImageView.frame.origin.x
    }

    private func completeInteractive(commit: Bool, translationX: CGFloat, width: CGFloat) {
        guard let page = interactivePage else {
            isTransitioning = false
            hideOverlay()
            return
        }
        let target = interactiveTargetIndex
        let direction = interactiveDirection

        let destX: CGFloat
        var destAlpha: CGFloat = 0
        if interactiveDirection > 0 {
            destX = commit ? 0 : width
        } else {
            destX = commit ? 0 : -width
            destAlpha = commit ? GestureConstants.maxDimmingAlpha : 0
        }
        if interactiveDirection > 0, !commit {
            destAlpha = 0
        }

        UIView.animate(
            withDuration: GestureConstants.settleAnimationDuration,
            delay: 0,
            options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction]
        ) {
            self.coverIncomingImageView.frame.origin.x = destX
            self.coverShadowView.frame.origin.x = destX
            self.coverDimView.alpha = destAlpha
        } completion: { [weak self] _ in
            guard let self else { return }
            defer {
                self.interactivePage = nil
                self.interactiveDirection = 0
                self.isTransitioning = false
                self.hideOverlay()
            }
            guard commit else { return }

            // 快照退场，真页上台（此时只需一次布局，不在拖动帧里）。
            page.frame = self.view.bounds
            page.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            self.view.addSubview(page)
            self.currentPageView?.removeFromSuperview()
            self.currentPageView = page
            self.currentIndex = target
            self.onPageChanged?(target)
            _ = direction
        }
    }

    // MARK: 程序化翻页（点击翻页区）

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
        showOverlay()
        guard let snap = next.makeSnapshotImage() else {
            // 快照失败（极小概率）直接切换，不阻塞阅读。
            isTransitioning = false
            hideOverlay()
            old?.removeFromSuperview()
            next.frame = view.bounds
            view.addSubview(next)
            currentPageView = next
            currentIndex = index
            onPageChanged?(index)
            return
        }
        coverIncomingImageView.image = snap
        coverIncomingImageView.layer.cornerRadius = screenCornerRadius
        coverIncomingImageView.frame = view.bounds
        coverShadowView.frame = view.bounds
        coverShadowView.layer.shadowPath = UIBezierPath(
            roundedRect: coverIncomingImageView.bounds,
            cornerRadius: screenCornerRadius
        ).cgPath
        coverDimView.frame = view.bounds
        coverDimView.alpha = 0
        coverIncomingImageView.frame.origin.x = direction >= 0 ? width : -width

        UIView.animate(
            withDuration: GestureConstants.settleAnimationDuration,
            delay: 0,
            options: [.curveEaseOut, .allowUserInteraction]
        ) {
            self.coverIncomingImageView.frame.origin.x = 0
            self.coverShadowView.frame.origin.x = 0
        } completion: { [weak self] _ in
            guard let self else { return }
            old?.removeFromSuperview()
            next.frame = self.view.bounds
            self.view.addSubview(next)
            self.currentPageView = next
            self.currentIndex = index
            self.isTransitioning = false
            self.hideOverlay()
            self.onPageChanged?(index)
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
