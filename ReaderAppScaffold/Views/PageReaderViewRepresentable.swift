import SwiftUI
import UIKit

// MARK: - 单页内容视图

final class PageContentView: UIView {
    let text: String
    let config: ReaderConfig
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
        textView.attributedText = NSAttributedString(string: text, attributes: attributes)

        addSubview(textView)
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: topAnchor),
            textView.leadingAnchor.constraint(equalTo: leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
}

// MARK: - 翻页容器协议

protocol PageReaderContainer: AnyObject {
    var pages: [String] { get set }
    var config: ReaderConfig { get }
    var currentIndex: Int { get set }
    var onPageChanged: ((Int) -> Void)? { get set }
    func goToPage(_ index: Int, animated: Bool)
    func updatePages(_ newPages: [String], keepIndex: Int)
}

// MARK: - 水平滑动翻页（UIScrollView + pagingEnabled，最流畅）

final class HorizontalSlideReader: UIViewController, PageReaderContainer, UIScrollViewDelegate {
    var pages: [String] = []
    let config: ReaderConfig
    var currentIndex: Int = 0
    var onPageChanged: ((Int) -> Void)?

    private let scrollView = UIScrollView()
    private let stackView = UIStackView()
    private var pageViews: [PageContentView] = []
    private var isProgrammaticScroll = false

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
        if !isProgrammaticScroll {
            let targetX = CGFloat(currentIndex) * scrollView.bounds.width
            if abs(scrollView.contentOffset.x - targetX) > 1 {
                scrollView.contentOffset = CGPoint(x: targetX, y: 0)
            }
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

        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.spacing = 0
        stackView.alignment = .fill
        stackView.distribution = .fillEqually

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
        pageViews.forEach { $0.removeFromSuperview() }
        pageViews.removeAll()

        for text in pages {
            let pageView = PageContentView(text: text, config: config)
            pageView.translatesAutoresizingMaskIntoConstraints = false
            stackView.addArrangedSubview(pageView)
            pageView.widthAnchor.constraint(equalTo: scrollView.widthAnchor).isActive = true
            pageViews.append(pageView)
        }

        view.setNeedsLayout()
        view.layoutIfNeeded()

        let safeIndex = min(max(currentIndex, 0), max(pages.count - 1, 0))
        currentIndex = safeIndex
        isProgrammaticScroll = true
        scrollView.contentOffset = CGPoint(x: CGFloat(safeIndex) * scrollView.bounds.width, y: 0)
        isProgrammaticScroll = false
    }

    func updatePages(_ newPages: [String], keepIndex: Int) {
        pages = newPages
        let safeIndex = min(max(keepIndex, 0), max(newPages.count - 1, 0))
        currentIndex = safeIndex
        reloadPages()
    }

    func goToPage(_ index: Int, animated: Bool) {
        guard index >= 0, index < pages.count else { return }
        currentIndex = index
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

// MARK: - 仿真翻页（UIPageViewController pageCurl）

final class CurlPageReader: UIPageViewController, PageReaderContainer, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
    var pages: [String] = []
    let config: ReaderConfig
    var currentIndex: Int = 0
    var onPageChanged: ((Int) -> Void)?

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
        let vc = UIViewController()
        vc.view.backgroundColor = .clear
        let pageView = PageContentView(text: pages[safe: index] ?? "", config: config)
        pageView.translatesAutoresizingMaskIntoConstraints = false
        vc.view.addSubview(pageView)
        NSLayoutConstraint.activate([
            pageView.topAnchor.constraint(equalTo: vc.view.topAnchor),
            pageView.leadingAnchor.constraint(equalTo: vc.view.leadingAnchor),
            pageView.trailingAnchor.constraint(equalTo: vc.view.trailingAnchor),
            pageView.bottomAnchor.constraint(equalTo: vc.view.bottomAnchor)
        ])
        return vc
    }

    func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
        guard currentIndex > 0 else { return nil }
        return makeVC(at: currentIndex - 1)
    }

    func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
        guard currentIndex < pages.count - 1 else { return nil }
        return makeVC(at: currentIndex + 1)
    }

    func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
        guard completed else { return }
        if let vc = pageViewController.viewControllers?.first,
           let pageView = vc.view.subviews.first as? PageContentView,
           let index = pages.firstIndex(of: pageView.text) {
            currentIndex = index
            onPageChanged?(index)
        }
    }
}

// MARK: - 垂直滚动翻页

final class VerticalScrollReader: UIViewController, PageReaderContainer, UIScrollViewDelegate {
    var pages: [String] = []
    let config: ReaderConfig
    var currentIndex: Int = 0
    var onPageChanged: ((Int) -> Void)?

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
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.alwaysBounceVertical = true
        scrollView.scrollsToTop = false

        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.spacing = 0
        stackView.alignment = .fill
        stackView.distribution = .fillEqually

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
        pageViews.forEach { $0.removeFromSuperview() }
        pageViews.removeAll()

        for text in pages {
            let pageView = PageContentView(text: text, config: config)
            pageView.translatesAutoresizingMaskIntoConstraints = false
            stackView.addArrangedSubview(pageView)
            pageView.heightAnchor.constraint(equalTo: scrollView.heightAnchor).isActive = true
            pageViews.append(pageView)
        }

        view.setNeedsLayout()
        view.layoutIfNeeded()

        let safeIndex = min(max(currentIndex, 0), max(pages.count - 1, 0))
        currentIndex = safeIndex
        scrollView.contentOffset = CGPoint(x: 0, y: CGFloat(safeIndex) * scrollView.bounds.height)
    }

    func updatePages(_ newPages: [String], keepIndex: Int) {
        pages = newPages
        let safeIndex = min(max(keepIndex, 0), max(newPages.count - 1, 0))
        currentIndex = safeIndex
        reloadPages()
    }

    func goToPage(_ index: Int, animated: Bool) {
        guard index >= 0, index < pageViews.count else { return }
        let targetY = CGFloat(index) * scrollView.bounds.height
        scrollView.setContentOffset(CGPoint(x: 0, y: targetY), animated: animated)
        currentIndex = index
        onPageChanged?(index)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let pageHeight = scrollView.bounds.height
        guard pageHeight > 0 else { return }
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

    func makeUIViewController(context: Context) -> UIViewController {
        let reader = makeReader(for: config.currentPageAnim)
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
        if reader.pages != pages {
            reader.updatePages(pages, keepIndex: currentIndex)
        }
        reader.onPageChanged = { index in
            DispatchQueue.main.async {
                currentIndex = index
                onPageChanged?(index)
            }
        }
    }

    private func makeReader(for anim: PageAnimationType) -> PageReaderContainer {
        switch anim {
        case .slide, .cover:
            return HorizontalSlideReader(pages: pages, config: config, initialIndex: currentIndex)
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
