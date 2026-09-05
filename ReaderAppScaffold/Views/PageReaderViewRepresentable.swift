import SwiftUI
import UIKit

// MARK: - 单页内容视图控制器

final class PageContentViewController: UIViewController {
    let text: String
    let config: ReaderConfig
    private let textView = UITextView()

    init(text: String, config: ReaderConfig) {
        self.text = text
        self.config = config
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        setupTextView()
    }

    private func setupTextView() {
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.backgroundColor = .clear
        textView.isEditable = false
        textView.isScrollEnabled = false
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.showsVerticalScrollIndicator = false
        textView.showsHorizontalScrollIndicator = false
        textView.text = text

        // 应用排版配置
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = config.lineSpacing
        paragraphStyle.paragraphSpacing = config.paragraphSpacing
        paragraphStyle.lineBreakMode = .byWordWrapping
        paragraphStyle.alignment = config.coreTextAlignment
        paragraphStyle.firstLineHeadIndent = config.fontSize * CGFloat(config.paragraphIndent)

        let attributes: [NSAttributedString.Key: Any] = [
            .font: config.uiFont,
            .foregroundColor: UIColor(config.currentTheme.textColor),
            .paragraphStyle: paragraphStyle
        ]
        textView.attributedText = NSAttributedString(string: text, attributes: attributes)

        view.addSubview(textView)
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: view.topAnchor),
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
}

// MARK: - 分页视图控制器（UIPageViewController 包装）

final class PageReaderViewController: UIPageViewController {
    var pages: [String] = []
    var config: ReaderConfig
    var onPageChanged: ((Int) -> Void)?
    private var currentIndex = 0

    init(pages: [String], config: ReaderConfig, initialIndex: Int = 0) {
        self.pages = pages
        self.config = config
        self.currentIndex = initialIndex
        super.init(transitionStyle: .scroll, navigationOrientation: .horizontal, options: [
            .interPageSpacing: 0
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        dataSource = self
        delegate = self
        view.backgroundColor = .clear

        if !pages.isEmpty {
            let initial = min(currentIndex, pages.count - 1)
            let vc = makeViewController(at: initial)
            setViewControllers([vc], direction: .forward, animated: false)
            currentIndex = initial
        }
    }

    func updatePages(_ newPages: [String], keepIndex: Int) {
        pages = newPages
        let safeIndex = min(max(keepIndex, 0), max(newPages.count - 1, 0))
        currentIndex = safeIndex
        if !newPages.isEmpty {
            let vc = makeViewController(at: safeIndex)
            setViewControllers([vc], direction: .forward, animated: false)
        }
    }

    func goToPage(_ index: Int, animated: Bool = true) {
        guard index >= 0, index < pages.count, index != currentIndex else { return }
        let direction: UIPageViewController.NavigationDirection = index > currentIndex ? .forward : .reverse
        let vc = makeViewController(at: index)
        setViewControllers([vc], direction: direction, animated: animated) { [weak self] _ in
            self?.currentIndex = index
            self?.onPageChanged?(index)
        }
    }

    func goNext(animated: Bool = true) {
        goToPage(currentIndex + 1, animated: animated)
    }

    func goPrev(animated: Bool = true) {
        goToPage(currentIndex - 1, animated: animated)
    }

    private func makeViewController(at index: Int) -> PageContentViewController {
        PageContentViewController(text: pages[safe: index] ?? "", config: config)
    }
}

// MARK: - UIPageViewControllerDataSource

extension PageReaderViewController: UIPageViewControllerDataSource {
    func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
        guard currentIndex > 0 else { return nil }
        return makeViewController(at: currentIndex - 1)
    }

    func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
        guard currentIndex < pages.count - 1 else { return nil }
        return makeViewController(at: currentIndex + 1)
    }
}

// MARK: - UIPageViewControllerDelegate

extension PageReaderViewController: UIPageViewControllerDelegate {
    func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
        guard completed,
              let vc = pageViewController.viewControllers?.first as? PageContentViewController,
              let index = pages.firstIndex(of: vc.text) else { return }
        currentIndex = index
        onPageChanged?(index)
    }
}

// MARK: - SwiftUI 包装

struct PageReaderViewRepresentable: UIViewControllerRepresentable {
    let pages: [String]
    let config: ReaderConfig
    @Binding var currentIndex: Int
    var onPageChanged: ((Int) -> Void)?

    func makeUIViewController(context: Context) -> PageReaderViewController {
        let vc = PageReaderViewController(pages: pages, config: config, initialIndex: currentIndex)
        vc.onPageChanged = { index in
            DispatchQueue.main.async {
                currentIndex = index
                onPageChanged?(index)
            }
        }
        return vc
    }

    func updateUIViewController(_ uiViewController: PageReaderViewController, context: Context) {
        if uiViewController.pages != pages {
            uiViewController.updatePages(pages, keepIndex: currentIndex)
        }
        uiViewController.onPageChanged = { index in
            DispatchQueue.main.async {
                currentIndex = index
                onPageChanged?(index)
            }
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
