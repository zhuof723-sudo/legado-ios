import Foundation
import PDFKit
import UIKit

/// PDF 阅读驱动：PDFKit 文档 + 按需渲染页面图像 + NSCache 缓存。
/// 渲染在后台队列进行，主线程只做 UIImage 赋值。
@MainActor
final class PDFReaderViewModel: ObservableObject, Identifiable {
    let id = UUID()
    let bookName: String
    /// 书架用的唯一标识（书签存储命名空间 pdf://id）
    let bookID: String
    @Published private(set) var pageCount = 0
    @Published private(set) var currentPage = 0
    @Published var errorMessage: String?

    private let document: PDFDocument?
    private let renderQueue = DispatchQueue(label: "pdf.render", qos: .userInitiated)
    /// 页面图像缓存：按页号存 UIImage
    private var cache: [Int: UIImage] = [:]
    /// 渲染任务去重：同一页只有一个任务在跑
    private var inFlight: Set<Int> = []

    init(book: PDFBook) {
        self.bookName = book.name
        self.bookID = book.id
        self.document = PDFDocument(url: book.fileURL)
        self.pageCount = document?.pageCount ?? 0
        if document == nil {
            errorMessage = "无法打开 PDF 文件"
        }
    }

    /// 取某一页图像。命中缓存直接返回；否则后台渲染后回填。
    func image(for page: Int, targetSize: CGSize, completion: @escaping (Int, UIImage?) -> Void) {
        guard page >= 0, page < pageCount else {
            completion(page, nil)
            return
        }
        if let cached = cache[page] {
            completion(page, cached)
            return
        }
        guard !inFlight.contains(page) else {
            // 已在渲染中：先回占位，渲染完成的那次回调会更新自己那页。
            completion(page, nil)
            return
        }
        inFlight.insert(page)

        let doc = document
        renderQueue.async { [weak self] in
            let image = Self.renderPage(doc, page: page, targetSize: targetSize)
            DispatchQueue.main.async {
                guard let self else { return }
                self.inFlight.remove(page)
                if let image {
                    self.cache[page] = image
                }
                completion(page, image)
            }
        }
    }

    /// 当前页文本（TTS / 复制用）。PDFKit 的文本抽取质量取决于文档本身。
    var currentPageText: String? {
        guard let doc = document, currentPage < doc.pageCount else { return nil }
        return doc.page(at: currentPage)?.string
    }

    func goToPage(_ page: Int) {
        guard page >= 0, page < pageCount else { return }
        currentPage = page
    }

    /// 从 PDF 副本提取书名/作者（尽力而为）。
    static func metadata(from url: URL) -> (title: String?, author: String?) {
        guard let doc = PDFDocument(url: url) else { return (nil, nil) }
        var title = doc.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String
        var author = doc.documentAttributes?[PDFDocumentAttribute.authorAttribute] as? String
        if title == nil, let first = doc.page(at: 0)?.string {
            // 首页开头几行常是书名
            let lines = first.components(separatedBy: .newlines).map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }.filter { !$0.isEmpty }
            if let l = lines.first, l.count < 40 { title = l }
        }
        if title?.isEmpty != false { title = nil }
        if author?.isEmpty != false { author = nil }
        return (title, author)
    }

    // MARK: - 渲染

    /// 在后台线程把 PDF 页渲染成指定尺寸的位图。
    nonisolated private static func renderPage(_ document: PDFDocument?, page: Int, targetSize: CGSize) -> UIImage? {
        guard let document, page < document.pageCount, let pdfPage = document.page(at: page),
              let pageRef = pdfPage.pageRef else { return nil }

        let bounds = pdfPage.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        let scale = min(targetSize.width / bounds.width, targetSize.height / bounds.height)
        // 3x 上限：屏幕密度足够，避免超大 PDF 页吃爆内存
        let renderScale = min(max(scale, 1), 3)
        let pixelSize = CGSize(width: bounds.width * renderScale, height: bounds.height * renderScale)
        guard pixelSize.width > 1, pixelSize.height > 1 else { return nil }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: pixelSize, format: format)
        return renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: pixelSize))
            ctx.cgContext.interpolationQuality = .high
            ctx.cgContext.saveGState()
            ctx.cgContext.translateBy(x: 0, y: pixelSize.height)
            ctx.cgContext.scaleBy(x: renderScale, y: -renderScale)
            ctx.cgContext.drawPDFPage(pageRef)
            ctx.cgContext.restoreGState()
        }
    }
}