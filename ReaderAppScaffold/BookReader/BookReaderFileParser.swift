import Foundation
import Fuzi

struct BookReaderChapter: Codable {
    let title: String
    let content: String
}

enum BookReaderFileParser {
    struct EPUBBook {
        let title: String
        let author: String
        let chapters: [BookReaderChapter]
    }

    enum ParserError: LocalizedError {
        case emptyFile
        case unreadableText
        case invalidEPUB
        case missingContainer
        case missingPackage
        case emptyEPUB

        var errorDescription: String? {
            switch self {
            case .emptyFile: return "文件是空的，没有可导入的内容"
            case .unreadableText: return "无法识别文本编码"
            case .invalidEPUB: return "文件不是有效 EPUB"
            case .missingContainer: return "EPUB 缺少 META-INF/container.xml"
            case .missingPackage: return "EPUB 缺少 OPF 包文件"
            case .emptyEPUB: return "EPUB 没有可读取的正文章节"
            }
        }
    }

    static func readText(url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        guard !data.isEmpty else { throw ParserError.emptyFile }
        for encoding in [String.Encoding.utf8, .utf16, .utf16LittleEndian, .utf16BigEndian] {
            if let text = String(data: data, encoding: encoding) { return text }
        }
        let gb18030 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(0x0632)))
        if let text = String(data: data, encoding: gb18030) { return text }
        throw ParserError.unreadableText
    }

    static func encode(_ chapters: [BookReaderChapter]) -> String {
        guard let data = try? JSONEncoder().encode(chapters) else { return "[]" }
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    static func decode(_ data: String) -> [BookReaderChapter] {
        guard let raw = data.data(using: .utf8),
              let result = try? JSONDecoder().decode([BookReaderChapter].self, from: raw) else { return [] }
        return result
    }

    static func chapters(from text: String) -> [BookReaderChapter] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let chapterPattern = "^\\s{0,4}(第[0-9零〇一二三四五六七八九十百千万两]+[章节卷回部集篇话幕][^\\n]{0,40}|序章|楔子|引子|尾声|终章|后记|番外[^\\n]{0,24}|Chapter\\s+\\d+[^\\n]{0,40})\\s*$"
        let regex = try? NSRegularExpression(pattern: chapterPattern, options: [.caseInsensitive])
        let lines = normalized.components(separatedBy: "\n")
        var chapters: [BookReaderChapter] = []
        var title = "卷首"
        var paragraphs: [String] = []

        func flush() {
            let body = paragraphs.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty { chapters.append(BookReaderChapter(title: title, content: body)) }
            paragraphs.removeAll(keepingCapacity: true)
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let range = NSRange(location: 0, length: (line as NSString).length)
            if !trimmed.isEmpty, regex?.firstMatch(in: line, range: range) != nil, !paragraphs.isEmpty {
                flush()
                title = trimmed
            } else if !trimmed.isEmpty {
                paragraphs.append(trimmed)
            }
        }
        flush()

        if chapters.count >= 3 { return chapters }
        let all = chapters.flatMap { $0.content.components(separatedBy: "\n") }
        guard !all.isEmpty else {
            return [BookReaderChapter(title: "全文", content: normalized.trimmingCharacters(in: .whitespacesAndNewlines))]
        }
        var chunks: [BookReaderChapter] = []
        var buffer: [String] = []
        var length = 0
        for paragraph in all {
            buffer.append(paragraph)
            length += paragraph.count
            if length >= 8000 {
                chunks.append(BookReaderChapter(title: "第 \(chunks.count + 1) 部分", content: buffer.joined(separator: "\n")))
                buffer.removeAll(keepingCapacity: true)
                length = 0
            }
        }
        if !buffer.isEmpty {
            chunks.append(BookReaderChapter(title: "第 \(chunks.count + 1) 部分", content: buffer.joined(separator: "\n")))
        }
        return chunks
    }

    static func parseEPUB(url: URL) throws -> EPUBBook {
        let entries: [String: Data]
        do { entries = try MiniZIP.entries(in: url) }
        catch { throw ParserError.invalidEPUB }
        return try parseEPUB(entries: entries)
    }

    static func parseEPUB(entries: [String: Data]) throws -> EPUBBook {
        guard let container = entry(entries, named: "META-INF/container.xml"),
              let containerDoc = try? XMLDocument(data: container),
              let rootfile = localElements(containerDoc, named: "rootfile").first,
              let rawPackagePath = rootfile.attributes["full-path"] else {
            throw ParserError.missingContainer
        }
        let packagePath = normalize(rawPackagePath)
        guard let packageData = entry(entries, named: packagePath),
              let packageDoc = try? XMLDocument(data: packageData) else {
            throw ParserError.missingPackage
        }
        let packageDirectory = (packagePath as NSString).deletingLastPathComponent
        let title = firstText(packageDoc, named: "title") ?? "未命名"
        let author = firstText(packageDoc, named: "creator") ?? "未知作者"

        var manifest: [String: (href: String, type: String)] = [:]
        for item in localElements(packageDoc, named: "item") {
            guard let id = item.attributes["id"], let href = item.attributes["href"] else { continue }
            manifest[id] = (href, item.attributes["media-type"] ?? "")
        }
        let spine = localElements(packageDoc, named: "itemref").compactMap { $0.attributes["idref"] }
        var chapters: [BookReaderChapter] = []
        for (index, id) in spine.enumerated() {
            guard let item = manifest[id], item.type.contains("html") || item.href.lowercased().hasSuffix(".xhtml") else { continue }
            let path = resolve(item.href, relativeTo: packageDirectory)
            guard let data = entry(entries, named: path), let html = try? HTMLDocument(data: data) else { continue }
            let title = heading(in: html) ?? ((path as NSString).deletingPathExtension as String)
            let paragraphs = paragraphText(in: html)
            let content = paragraphs.isEmpty ? (html.body?.stringValue ?? "") : paragraphs.joined(separator: "\n")
            let cleaned = content.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty {
                chapters.append(BookReaderChapter(title: title.isEmpty ? "第 \(index + 1) 章" : title, content: cleaned))
            }
        }
        guard !chapters.isEmpty else { throw ParserError.emptyEPUB }
        return EPUBBook(title: title, author: author, chapters: chapters)
    }

    private static func entry(_ entries: [String: Data], named name: String) -> Data? {
        if let value = entries[name] { return value }
        let target = normalize(name).lowercased()
        return entries.first { normalize($0.key).lowercased() == target }?.value
    }

    private static func normalize(_ path: String) -> String {
        let decoded = path.removingPercentEncoding ?? path
        var result: [String] = []
        for component in decoded.split(separator: "/") {
            if component == "." { continue }
            if component == ".." { if !result.isEmpty { result.removeLast() } }
            else { result.append(String(component)) }
        }
        return result.joined(separator: "/")
    }

    private static func resolve(_ href: String, relativeTo directory: String) -> String {
        let clean = href.split(separator: "#", maxSplits: 1).first.map(String.init) ?? href
        return normalize(directory.isEmpty ? clean : "\(directory)/\(clean)")
    }

    private static func localElements(_ document: XMLDocument, named name: String) -> [XMLElement] {
        guard let root = document.root else { return [] }
        var result: [XMLElement] = []
        func walk(_ element: XMLElement) {
            if element.tag?.split(separator: ":").last.map(String.init) == name { result.append(element) }
            for child in element.children { walk(child) }
        }
        walk(root)
        return result
    }

    private static func firstText(_ document: XMLDocument, named name: String) -> String? {
        localElements(document, named: name).compactMap { element in
            let text = element.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        }.first
    }

    private static func heading(in document: HTMLDocument) -> String? {
        for name in ["h1", "h2", "h3"] {
            if let element = document.body?.firstChild(tag: name) {
                let text = element.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { return text }
            }
        }
        return nil
    }

    private static func paragraphText(in document: HTMLDocument) -> [String] {
        guard let body = document.body else { return [] }
        let blockTags: Set<String> = ["p", "h1", "h2", "h3", "h4", "h5", "h6", "li", "blockquote", "pre"]
        let ignored: Set<String> = ["script", "style", "nav", "head", "svg"]
        var result: [String] = []
        func walk(_ element: XMLElement) {
            guard let rawTag = element.tag else { return }
            let tag = rawTag.lowercased()
            if ignored.contains(tag) { return }
            if tag == "br" { result.append(""); return }
            if blockTags.contains(tag) {
                let text = element.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { result.append(text) }
                return
            }
            for child in element.children { walk(child) }
        }
        walk(body)
        return result
    }
}
