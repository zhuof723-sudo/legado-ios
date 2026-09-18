import Foundation
import SwiftData

/// 本地导入的 PDF 书籍：文件副本存放在 Documents/PDFs/ 下，
/// fileName 记录相对路径，打开时拼出完整 URL。
@Model
final class PDFBook {
    @Attribute(.unique) var id: String
    var name: String
    var author: String
    var fileName: String
    var pageCount: Int
    var createdAt: Date

    init(name: String, author: String, fileName: String, pageCount: Int) {
        self.id = UUID().uuidString
        self.name = name
        self.author = author
        self.fileName = fileName
        self.pageCount = pageCount
        self.createdAt = Date()
    }

    /// 复制的文件统一放这里（App 沙盒内，用户可随时从书架删除）。
    static var pdfDirectory: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PDFs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    var fileURL: URL {
        Self.pdfDirectory.appendingPathComponent(fileName)
    }
}