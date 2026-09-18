import SwiftUI
import UIKit

// MARK: - PDF 单页

final class PDFPageViewController: UIViewController {
    let pageIndex: Int
    private let viewModel: PDFReaderViewModel
    private let imageView = UIImageView()
    private var requestedSize = CGSize.zero
    private var background: UIColor
    var onTap: ((CGPoint, CGFloat) -> Void)?

    init(pageIndex: Int, viewModel: PDFReaderViewModel, background: UIColor) {
        self.pageIndex = pageIndex
        self.viewModel = viewModel
        self.background = background
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = background
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        view.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: view.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let size = view.bounds.size
        guard size.width > 1, size.height > 1, size != requestedSize else { return }
        requestedSize = size
        viewModel.image(for: pageIndex, targetSize: size) { [weak self] page, image in
            guard let self, page == self.pageIndex else { return }
            self.imageView.image = image
        }
    }

    func apply(background: UIColor) {
        self.background = background
        view.backgroundColor = background
    }

    @objc private func tapped(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: view)
        onTap?(point, view.bounds.width)
    }
}

// MARK: - PDF 仿真翻页

struct PDFPageCurlView: UIViewControllerRepresentable {
    let viewModel: PDFReaderViewModel
    let background: UIColor
    var onPageChanged: (Int) -> Void
    var onTap: (CGPoint, CGFloat) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIPageViewController {
        let controller = UIPageViewController(
            transitionStyle: .pageCurl,
            navigationOrientation: .horizontal,
            options: nil
        )
        controller.dataSource = context.coordinator
        controller.delegate = context.coordinator
        context.coordinator.parent = self
        if viewModel.pageCount > 0 {
            let index = min(max(viewModel.currentPage, 0), viewModel.pageCount - 1)
            controller.setViewControllers([context.coordinator.makePage(index)], direction: .forward, animated: false)
        }
        return controller
    }

    func updateUIViewController(_ controller: UIPageViewController, context: Context) {
        context.coordinator.parent = self
        for case let page as PDFPageViewController in controller.viewControllers ?? [] {
            page.apply(background: background)
        }
        guard viewModel.pageCount > 0,
              let visible = controller.viewControllers?.first as? PDFPageViewController else { return }
        let target = min(max(viewModel.currentPage, 0), viewModel.pageCount - 1)
        if visible.pageIndex != target {
            controller.setViewControllers(
                [context.coordinator.makePage(target)],
                direction: target > visible.pageIndex ? .forward : .reverse,
                animated: true
            )
        }
    }

    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        var parent: PDFPageCurlView

        init(_ parent: PDFPageCurlView) { self.parent = parent }

        func makePage(_ index: Int) -> PDFPageViewController {
            let page = PDFPageViewController(pageIndex: index, viewModel: parent.viewModel, background: parent.background)
            page.onTap = { [weak self] point, width in self?.parent.onTap(point, width) }
            return page
        }

        func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
            guard let page = viewController as? PDFPageViewController, page.pageIndex > 0 else { return nil }
            return makePage(page.pageIndex - 1)
        }

        func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
            guard let page = viewController as? PDFPageViewController, page.pageIndex + 1 < parent.viewModel.pageCount else { return nil }
            return makePage(page.pageIndex + 1)
        }

        func pageViewController(
            _ pageViewController: UIPageViewController,
            didFinishAnimating finished: Bool,
            previousViewControllers: [UIViewController],
            transitionCompleted completed: Bool
        ) {
            guard completed, let page = pageViewController.viewControllers?.first as? PDFPageViewController else { return }
            parent.viewModel.goToPage(page.pageIndex)
            parent.onPageChanged(page.pageIndex)
        }
    }
}

// MARK: - PDF 阅读页

/// PDF 保持独立的 PDFKit 渲染，但采用与正文一致的极简阅读外壳和 pageCurl。
struct PDFReaderView: View {
    @Environment(\.dismiss) private var dismiss
    let book: PDFBook
    @StateObject private var viewModel: PDFReaderViewModel
    @ObservedObject private var style = BookReaderStyle.shared
    @State private var pageIndex = 0
    @State private var showControls = false

    init(book: PDFBook) {
        self.book = book
        _viewModel = StateObject(wrappedValue: PDFReaderViewModel(book: book))
    }

    private var background: UIColor { UIColor(style.theme.background) }
    private var progress: Double {
        guard viewModel.pageCount > 1 else { return 0 }
        return Double(min(pageIndex + 1, viewModel.pageCount)) / Double(viewModel.pageCount)
    }

    var body: some View {
        ZStack {
            style.theme.background.ignoresSafeArea()
            if let error = viewModel.errorMessage {
                Text(error).foregroundStyle(.red).multilineTextAlignment(.center).padding()
            } else {
                PDFPageCurlView(
                    viewModel: viewModel,
                    background: background,
                    onPageChanged: { pageIndex = $0 },
                    onTap: handleTap
                )
                .ignoresSafeArea(.container, edges: .all)
            }
            if showControls {
                VStack {
                    HStack {
                        Button { dismiss() } label: {
                            Image(systemName: "chevron.left")
                                .frame(width: 36, height: 36)
                        }
                        Text(book.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                        Spacer()
                        Text("\(pageIndex + 1) / \(max(viewModel.pageCount, 1))")
                            .font(.caption.monospacedDigit())
                    }
                    .foregroundStyle(style.theme.text)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial)
                    Spacer()
                }
                .ignoresSafeArea(edges: .top)
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(style.theme.text.opacity(0.18))
                .frame(height: 2)
                .overlay(alignment: .leading) {
                    GeometryReader { geometry in
                        Rectangle()
                            .fill(style.theme.text.opacity(0.75))
                            .frame(width: geometry.size.width * progress)
                    }
                }
                .allowsHitTesting(false)
        }
        .statusBarHidden(!showControls)
        .preferredColorScheme(style.nightMode ? .dark : .light)
        .toolbar(.hidden, for: .tabBar)
        .onAppear { pageIndex = viewModel.currentPage }
    }

    private func handleTap(_ point: CGPoint, _ width: CGFloat) {
        let edge = max(72, width * 0.24)
        if point.x <= edge, viewModel.currentPage > 0 {
            viewModel.goToPage(viewModel.currentPage - 1)
            pageIndex = viewModel.currentPage
        } else if point.x >= width - edge, viewModel.currentPage + 1 < viewModel.pageCount {
            viewModel.goToPage(viewModel.currentPage + 1)
            pageIndex = viewModel.currentPage
        } else {
            withAnimation(.easeInOut(duration: 0.16)) { showControls.toggle() }
        }
    }
}
