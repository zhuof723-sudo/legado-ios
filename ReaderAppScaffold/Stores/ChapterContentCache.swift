import Foundation
import CryptoKit
import LegadoRuleEngine

/// 已入架书籍的正文磁盘缓存。只按明确传入的 shelf book URL 启用，不为临时阅读落盘。
public actor ChapterContentCache {
    public static let shared = ChapterContentCache()

    private let root: URL

    public var directoryURL: URL { root }

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        root = support.appendingPathComponent("ShelfChapterContent", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var directory = root
        try? directory.setResourceValues(values)
    }

    public func load(bookURL: String, chapterURL: String) -> String? {
        loadDocument(bookURL: bookURL, chapterURL: chapterURL)?.text
    }

    /// 读取包含段评图元数据的正文；旧版纯文本缓存仍可正常读取。
    public func loadDocument(bookURL: String, chapterURL: String) -> ReaderChapterContent? {
        let file = fileURL(bookURL: bookURL, chapterURL: chapterURL)
        guard let data = try? Data(contentsOf: file), !data.isEmpty else { return nil }
        if let document = try? JSONDecoder().decode(ReaderChapterContent.self, from: data) {
            return document
        }
        guard let text = String(data: data, encoding: .utf8), !text.isEmpty else { return nil }
        return ReaderChapterContent(text: text)
    }

    public func save(_ text: String, bookURL: String, chapterURL: String) {
        saveDocument(ReaderChapterContent(text: text), bookURL: bookURL, chapterURL: chapterURL)
    }

    public func saveDocument(_ document: ReaderChapterContent, bookURL: String, chapterURL: String) {
        guard !document.text.isEmpty else { return }
        let folder = bookFolder(bookURL)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(document) else { return }
        try? data.write(to: fileURL(bookURL: bookURL, chapterURL: chapterURL), options: .atomic)
    }

    public func clear(bookURL: String) {
        try? FileManager.default.removeItem(at: bookFolder(bookURL))
    }

    public func clearAll() {
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    private func bookFolder(_ bookURL: String) -> URL {
        root.appendingPathComponent(hash(bookURL), isDirectory: true)
    }

    private func fileURL(bookURL: String, chapterURL: String) -> URL {
        bookFolder(bookURL).appendingPathComponent(hash(chapterURL)).appendingPathExtension("txt")
    }

    private func hash(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
