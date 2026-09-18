import UIKit
import SwiftUI

struct ReaderPageTurnCallbacks {
    var onTap: ((ReaderPageTap) -> Void)?
    var onLink: ((ReaderPageLink) -> Void)?
}

final class ReaderPageViewController: UIViewController {
    let index: Int
    let canvas: ReaderPageCanvas

    init(index: Int, canvas: ReaderPageCanvas) {
        self.index = index
        self.canvas = canvas
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = canvas.backgroundColor
        canvas.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(canvas)
        NSLayoutConstraint.activate([
            canvas.topAnchor.constraint(equalTo: view.topAnchor),
            canvas.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            canvas.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
}

/// 唯一正文翻页容器：仿真翻页。
/// 平移与无动画不再属于正文阅读页的实现范围。
final class ReaderPageCurlController: UIPageViewController,
                                     UIPageViewControllerDataSource,
                                     UIPageViewControllerDelegate {
    var pages: [ReaderBookPage] = []
    let style: ReaderPageStyle
    var currentIndex: Int = 0
    var callbacks = ReaderPageTurnCallbacks()
    var onPageChanged: ((Int) -> Void)?
    var contentOffset: CGPoint
    var contentSize: CGSize

    init(
        pages: [ReaderBookPage],
        style: ReaderPageStyle,
        initialIndex: Int,
        contentOffset: CGPoint,
        contentSize: CGSize
    ) {
        self.pages = pages
        self.style = style
        self.currentIndex = initialIndex
        self.contentOffset = contentOffset
        self.contentSize = contentSize
        super.init(transitionStyle: .pageCurl, navigationOrientation: .horizontal, options: nil)
        isDoubleSided = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        dataSource = self
        delegate = self
        view.backgroundColor = UIColor(style.theme.background)
        guard !pages.isEmpty else { return }
        currentIndex = min(max(currentIndex, 0), pages.count - 1)
        setViewControllers([makePage(at: currentIndex)], direction: .forward, animated: false)
    }

    private func makePage(at index: Int) -> ReaderPageViewController {
        let canvas = ReaderPageCanvas(
            page: pages[index],
            style: style,
            contentOffset: contentOffset,
            contentSize: contentSize
        )
        canvas.onTap = { [weak self] tap in self?.callbacks.onTap?(tap) }
        canvas.onLink = { [weak self] link in self?.callbacks.onLink?(link) }
        return ReaderPageViewController(index: index, canvas: canvas)
    }

    func update(pages: [ReaderBookPage], index: Int) {
        self.pages = pages
        guard !pages.isEmpty else { return }
        currentIndex = min(max(index, 0), pages.count - 1)
        setViewControllers([makePage(at: currentIndex)], direction: .forward, animated: false)
    }

    func go(to index: Int, animated: Bool) {
        guard pages.indices.contains(index), index != currentIndex else { return }
        let direction: UIPageViewController.NavigationDirection = index > currentIndex ? .forward : .reverse
        setViewControllers([makePage(at: index)], direction: direction, animated: animated) { [weak self] _ in
            self?.finish(index)
        }
    }

    func refreshTheme() {
        view.backgroundColor = UIColor(style.theme.background)
        viewControllers?.compactMap { $0 as? ReaderPageViewController }.forEach { $0.canvas.refreshTheme() }
    }

    private func finish(_ index: Int) {
        guard currentIndex != index else { return }
        currentIndex = index
        onPageChanged?(index)
    }

    func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
        guard let page = viewController as? ReaderPageViewController, page.index > 0 else { return nil }
        return makePage(at: page.index - 1)
    }

    func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
        guard let page = viewController as? ReaderPageViewController, page.index + 1 < pages.count else { return nil }
        return makePage(at: page.index + 1)
    }

    func pageViewController(
        _ pageViewController: UIPageViewController,
        didFinishAnimating finished: Bool,
        previousViewControllers: [UIViewController],
        transitionCompleted completed: Bool
    ) {
        guard completed, let page = pageViewController.viewControllers?.first as? ReaderPageViewController else { return }
        finish(page.index)
    }
}

struct ReaderPageCurlView: UIViewControllerRepresentable {
    let pages: [ReaderBookPage]
    let style: ReaderPageStyle
    @Binding var pageIndex: Int
    let contentOffset: CGPoint
    let contentSize: CGSize
    var onTap: (ReaderPageTap) -> Void
    var onLink: (ReaderPageLink) -> Void

    func makeUIViewController(context: Context) -> ReaderPageCurlController {
        let controller = ReaderPageCurlController(
            pages: pages,
            style: style,
            initialIndex: pageIndex,
            contentOffset: contentOffset,
            contentSize: contentSize
        )
        apply(controller)
        return controller
    }

    private func apply(_ controller: ReaderPageCurlController) {
        controller.callbacks = ReaderPageTurnCallbacks(onTap: onTap, onLink: onLink)
        controller.onPageChanged = { index in
            DispatchQueue.main.async {
                if pageIndex != index { pageIndex = index }
            }
        }
    }

    func updateUIViewController(_ controller: ReaderPageCurlController, context: Context) {
        apply(controller)
        controller.contentOffset = contentOffset
        controller.contentSize = contentSize
        controller.refreshTheme()
        if controller.pages != pages {
            controller.update(pages: pages, index: pageIndex)
        } else if controller.currentIndex != pageIndex {
            controller.go(to: pageIndex, animated: true)
        }
    }
}
