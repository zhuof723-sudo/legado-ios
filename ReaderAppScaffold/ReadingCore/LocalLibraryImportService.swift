import Foundation
import SwiftData
import PDFKit

enum LocalLibraryImportError: LocalizedError {
    case unsupportedFormat(String)
    case emptyBook(String)
    case invalidPDF

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let ext): return "暂不支持 \(ext.uppercased()) 格式"
        case .emptyBook(let name): return "没能从「\(name)」中解析出可阅读章节"
        case .invalidPDF: return "PDF 无法解析（可能已损坏）"
        }
    }
}

struct LocalLibraryImportResult {
    let title: String
    let detail: String
}

/// 本地书库唯一导入管线。界面文件选择与系统外部打开均通过此服务处理，
/// 避免 TXT、EPUB、PDF 在多个入口各自维护一套解析与持久化逻辑。
@MainActor
enum LocalLibraryImportService {
    static func importBook(from url: URL, context: ModelContext) throws -> LocalLibraryImportResult {
        let fallbackName = url.deletingPathExtension().lastPathComponent
        switch url.pathExtension.lowercased() {
        case "txt":
            let text = try FileTextReader.readText(from: url)
            return try importText(text, title: fallbackName, context: context)
        case "epub":
            let parsed = try BookReaderFileParser.parseEPUB(url: url)
            guard !parsed.chapters.isEmpty else {
                throw LocalLibraryImportError.emptyBook(url.lastPathComponent)
            }
            let title = parsed.title.isEmpty ? fallbackName : parsed.title
            let book = LocalBook(
                name: title,
                author: parsed.author,
                chaptersData: BookReaderFileParser.encode(parsed.chapters),
                coverData: parsed.coverData
            )
            context.insert(book)
            try context.save()
            return LocalLibraryImportResult(title: title, detail: "共 \(parsed.chapters.count) 章")
        case "pdf":
            return try importPDF(url, title: fallbackName, context: context)
        default:
            throw LocalLibraryImportError.unsupportedFormat(url.pathExtension)
        }
    }

    static func importText(_ text: String, title: String, context: ModelContext) throws -> LocalLibraryImportResult {
        let chapters = BookReaderFileParser.chapters(from: text)
        guard !chapters.isEmpty else { throw LocalLibraryImportError.emptyBook(title) }
        let book = LocalBook(
            name: title,
            author: "本地导入",
            chaptersData: BookReaderFileParser.encode(chapters)
        )
        context.insert(book)
        try context.save()
        return LocalLibraryImportResult(title: title, detail: "共 \(chapters.count) 章")
    }

    private static func importPDF(_ url: URL, title: String, context: ModelContext) throws -> LocalLibraryImportResult {
        let fileName = UUID().uuidString + ".pdf"
        let destination = PDFBook.pdfDirectory.appendingPathComponent(fileName)
        try FileManager.default.copyItem(at: url, to: destination)
        let metadata = PDFReaderViewModel.metadata(from: destination)
        let pageCount = PDFDocument(url: destination)?.pageCount ?? 0
        guard pageCount > 0 else {
            try? FileManager.default.removeItem(at: destination)
            throw LocalLibraryImportError.invalidPDF
        }
        let book = PDFBook(
            name: metadata.title ?? title,
            author: metadata.author ?? "未知作者",
            fileName: fileName,
            pageCount: pageCount
        )
        context.insert(book)
        do {
            try context.save()
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
        return LocalLibraryImportResult(title: book.name, detail: "共 \(pageCount) 页")
    }
}
