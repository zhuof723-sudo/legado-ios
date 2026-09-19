import UIKit
import SwiftUI

struct BookReaderCallbacks {
    var onTurn: ((BookReaderTurnIntent) -> Void)?
    var onLink: ((BookReaderLink) -> Void)?
    var onCenter: (() -> Void)?
}

final class BookReaderPageViewController: UIViewController {
    let index: Int
    let canvas: BookReaderCanvas

    init(index: Int, canvas: BookReaderCanvas) {
        self.index = index
        self.canvas = canvas
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
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

final class BookReaderFlowController: UIPageViewController, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
    var pages: [BookReaderPage]
    let style: BookReaderStyle
    var currentIndex: Int
    var callbacks = BookReaderCallbacks()
    var onPageChanged: ((Int) -> Void)?
    var contentOffset: CGPoint
    var contentSize: CGSize

    init(pages: [BookReaderPage], style: BookReaderStyle, index: Int, transition: UIPageViewController.TransitionStyle, contentOffset: CGPoint, contentSize: CGSize) {
        self.pages = pages
        self.style = style
        currentIndex = index
        self.contentOffset = contentOffset
        self.contentSize = contentSize
        super.init(transitionStyle: transition, navigationOrientation: .horizontal, options: nil)
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
        setViewControllers([makePage(currentIndex)], direction: .forward, animated: false)
    }

    private func makePage(_ index: Int) -> BookReaderPageViewController {
        let canvas = BookReaderCanvas(page: pages[index], style: style, contentOffset: contentOffset, contentSize: contentSize)
        canvas.onTurn = { [weak self] intent in self?.callbacks.onTurn?(intent) }
        canvas.onLink = { [weak self] link in self?.callbacks.onLink?(link) }
        return BookReaderPageViewController(index: index, canvas: canvas)
    }

    func update(pages: [BookReaderPage], index: Int) {
        self.pages = pages
        guard !pages.isEmpty else { return }
        currentIndex = min(max(index, 0), pages.count - 1)
        setViewControllers([makePage(currentIndex)], direction: .forward, animated: false)
    }

    func go(to index: Int, animated: Bool) {
        guard pages.indices.contains(index), index != currentIndex else { return }
        let direction: UIPageViewController.NavigationDirection = index > currentIndex ? .forward : .reverse
        setViewControllers([makePage(index)], direction: direction, animated: animated) { [weak self] _ in self?.finish(index) }
    }

    func refresh() {
        view.backgroundColor = UIColor(style.theme.background)
        viewControllers?.compactMap { $0 as? BookReaderPageViewController }.forEach { $0.canvas.refreshTheme() }
    }

    private func finish(_ index: Int) {
        guard currentIndex != index else { return }
        currentIndex = index
        onPageChanged?(index)
    }

    func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
        guard let page = viewController as? BookReaderPageViewController, page.index > 0 else { return nil }
        return makePage(page.index - 1)
    }

    func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
        guard let page = viewController as? BookReaderPageViewController, page.index + 1 < pages.count else { return nil }
        return makePage(page.index + 1)
    }

    func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
        guard completed, let page = pageViewController.viewControllers?.first as? BookReaderPageViewController else { return }
        finish(page.index)
    }
}

final class BookReaderFadeController: UIViewController {
    var pages: [BookReaderPage]
    let style: BookReaderStyle
    var currentIndex: Int
    var callbacks = BookReaderCallbacks()
    var contentOffset: CGPoint
    var contentSize: CGSize
    private var canvas: BookReaderCanvas?

    init(pages: [BookReaderPage], style: BookReaderStyle, index: Int, contentOffset: CGPoint, contentSize: CGSize) {
        self.pages = pages
        self.style = style
        currentIndex = index
        self.contentOffset = contentOffset
        self.contentSize = contentSize
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(style.theme.background)
        show(index: currentIndex, animated: false)
        let left = UISwipeGestureRecognizer(target: self, action: #selector(handlePreviousSwipe))
        left.direction = .right
        let right = UISwipeGestureRecognizer(target: self, action: #selector(handleNextSwipe))
        right.direction = .left
        view.addGestureRecognizer(left)
        view.addGestureRecognizer(right)
    }

    private func show(index: Int, animated: Bool) {
        guard pages.indices.contains(index) else { return }
        let nextCanvas = BookReaderCanvas(page: pages[index], style: style, contentOffset: contentOffset, contentSize: contentSize)
        nextCanvas.onTurn = { [weak self] intent in self?.callbacks.onTurn?(intent) }
        nextCanvas.onLink = { [weak self] link in self?.callbacks.onLink?(link) }
        nextCanvas.frame = view.bounds
        nextCanvas.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        if animated, let oldCanvas = canvas {
            oldCanvas.isUserInteractionEnabled = false
            nextCanvas.alpha = 0
            view.addSubview(nextCanvas)
            UIView.animate(withDuration: 0.18, animations: {
                oldCanvas.alpha = 0
                nextCanvas.alpha = 1
            }, completion: { _ in oldCanvas.removeFromSuperview() })
        } else {
            canvas?.removeFromSuperview()
            view.addSubview(nextCanvas)
        }
        canvas = nextCanvas
        currentIndex = index
    }

    @objc private func handlePreviousSwipe() { callbacks.onTurn?(.previous) }
    @objc private func handleNextSwipe() { callbacks.onTurn?(.next) }

    func update(pages: [BookReaderPage], index: Int) {
        self.pages = pages
        show(index: min(max(index, 0), max(pages.count - 1, 0)), animated: false)
    }

    func go(to index: Int) { show(index: index, animated: true) }
    func refresh() { view.backgroundColor = UIColor(style.theme.background); canvas?.refreshTheme() }
}

/// 滚动模式专用连续排版：独立 UITextView/TextKit 管线，不读取分页结果。
final class BookReaderScrollController: UIViewController, UITextViewDelegate {
    let style: BookReaderStyle
    var document: BookReaderDocument?
    var callbacks = BookReaderCallbacks()
    var contentOffset: CGPoint
    var contentSize: CGSize
    private let textView = UITextView()
    private var lastWidth: CGFloat = 0
    private var renderedSignature = ""
    private var pendingRebuild = false
    private var lastReportedOffset = -1
    var onCharacterOffset: ((Int) -> Void)?
    var initialCharacterOffset = 0

    init(document: BookReaderDocument?, style: BookReaderStyle, contentOffset: CGPoint, contentSize: CGSize) {
        self.document = document
        self.style = style
        self.contentOffset = contentOffset
        self.contentSize = contentSize
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(style.theme.background)
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.backgroundColor = .clear
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = true
        textView.delegate = self
        textView.textContainerInset = UIEdgeInsets(top: contentOffset.y, left: contentOffset.x, bottom: contentOffset.y, right: contentOffset.x)
        textView.textContainer.lineFragmentPadding = 0
        textView.linkTextAttributes = [.foregroundColor: UIColor.systemGray, .underlineStyle: 0]
        view.addSubview(textView)
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: view.topAnchor),
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        let tap = UITapGestureRecognizer(target: self, action: #selector(centerTapped(_:)))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
        rebuild()
    }

    @objc private func centerTapped(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else { return }
        callbacks.onTurn?(.center)
    }

    func rebuild() {
        guard let document else {
            if textView.attributedText?.length != 0 { textView.attributedText = nil }
            renderedSignature = ""
            return
        }
        let signature = "\(document.fingerprint)|\(style.font.fontName)|\(style.font.pointSize)|\(style.lineSpacing)|\(style.paragraphSpacing)|\(style.titleSpacing)|\(style.firstLineIndent)|\(contentSize.width)"
        guard signature != renderedSignature || abs(lastWidth - contentSize.width) > 0.5 else { return }
        if textView.isTracking || textView.isDecelerating { pendingRebuild = true; return }
        pendingRebuild = false

        let oldHeight = max(textView.contentSize.height - textView.bounds.height, 1)
        let oldOffset = max(textView.contentOffset.y, 0)
        let fraction = min(max(oldOffset / oldHeight, 0), 1)
        let text = document.continuousText(
            font: style.font,
            lineSpacing: style.lineSpacing,
            paragraphSpacing: style.paragraphSpacing,
            indent: style.firstLineIndent,
            titleSpacing: style.titleSpacing
        )
        textView.attributedText = text
        textView.textColor = UIColor(style.theme.text)
        textView.layoutIfNeeded()
        let newHeight = max(textView.contentSize.height - textView.bounds.height, 0)
        textView.setContentOffset(CGPoint(x: 0, y: newHeight * fraction), animated: false)
        if let position = textView.position(from: textView.beginningOfDocument, offset: initialCharacterOffset) {
            textView.scrollRangeToVisible(NSRange(location: textView.offset(from: textView.beginningOfDocument, to: position), length: 0))
        }
        renderedSignature = signature
        lastWidth = contentSize.width
    }

    func refresh() {
        view.backgroundColor = UIColor(style.theme.background)
        textView.textColor = UIColor(style.theme.text)
        textView.setNeedsDisplay()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView.isTracking || scrollView.isDecelerating else { return }
        let point = CGPoint(x: textView.textContainerInset.left + 1, y: max(textView.contentOffset.y + textView.textContainerInset.top, 0))
        let position = textView.closestPosition(to: point)
        if let position {
            let offset = textView.offset(from: textView.beginningOfDocument, to: position)
            if abs(offset - lastReportedOffset) >= 64 { lastReportedOffset = offset }
        }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { finishScrolling() }
    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) { if !decelerate { finishScrolling() } }

    private func finishScrolling() {
        if lastReportedOffset >= 0 { onCharacterOffset?(lastReportedOffset) }
        if pendingRebuild { rebuild() }
    }

    func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
        if let link = BookReaderLink.resolve(URL) { callbacks.onLink?(link) }
        return false
    }
}

struct BookReaderModeView: UIViewControllerRepresentable {
    let mode: BookReaderTurnMode
    let pages: [BookReaderPage]
    let document: BookReaderDocument?
    let style: BookReaderStyle
    @Binding var pageIndex: Int
    let contentOffset: CGPoint
    let contentSize: CGSize
    var onTurn: (BookReaderTurnIntent) -> Void
    var onLink: (BookReaderLink) -> Void
    let initialScrollOffset: Int
    var onScrollOffset: (Int) -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        let controller: UIViewController
        switch mode {
        case .curl:
            controller = BookReaderFlowController(pages: pages, style: style, index: pageIndex, transition: .pageCurl, contentOffset: contentOffset, contentSize: contentSize)
        case .slide:
            controller = BookReaderFlowController(pages: pages, style: style, index: pageIndex, transition: .scroll, contentOffset: contentOffset, contentSize: contentSize)
        case .fade:
            controller = BookReaderFadeController(pages: pages, style: style, index: pageIndex, contentOffset: contentOffset, contentSize: contentSize)
        case .scroll:
            controller = BookReaderScrollController(document: document, style: style, contentOffset: contentOffset, contentSize: contentSize)
        }
        apply(controller)
        return controller
    }

    private func apply(_ controller: UIViewController) {
        let callbacks = BookReaderCallbacks(onTurn: onTurn, onLink: onLink, onCenter: nil)
        switch controller {
        case let flow as BookReaderFlowController:
            flow.callbacks = callbacks
            flow.onPageChanged = { index in DispatchQueue.main.async { if self.pageIndex != index { self.pageIndex = index } } }
        case let fade as BookReaderFadeController:
            fade.callbacks = callbacks
        case let scroll as BookReaderScrollController:
            scroll.callbacks = callbacks
            scroll.onCharacterOffset = onScrollOffset
            scroll.initialCharacterOffset = initialScrollOffset
        default: break
        }
    }

    func updateUIViewController(_ controller: UIViewController, context: Context) {
        apply(controller)
        switch controller {
        case let flow as BookReaderFlowController:
            flow.contentOffset = contentOffset
            flow.contentSize = contentSize
            flow.refresh()
            if flow.pages != pages { flow.update(pages: pages, index: pageIndex) }
            else if flow.currentIndex != pageIndex { flow.go(to: pageIndex, animated: true) }
        case let fade as BookReaderFadeController:
            fade.contentOffset = contentOffset
            fade.contentSize = contentSize
            fade.refresh()
            if fade.pages != pages { fade.update(pages: pages, index: pageIndex) }
            else if fade.currentIndex != pageIndex { fade.go(to: pageIndex) }
        case let scroll as BookReaderScrollController:
            scroll.contentOffset = contentOffset
            scroll.contentSize = contentSize
            if scroll.document?.fingerprint != document?.fingerprint { scroll.document = document }
            scroll.rebuild()
            scroll.refresh()
        default: break
        }
    }
}
