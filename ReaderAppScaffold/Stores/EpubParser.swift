import Foundation
import Fuzi

// MARK: - EPUB 解析（原生，无第三方依赖）

/// EPUB 读取管线：MiniZIP 解包 → container.xml 定位 OPF → 解析
/// manifest/spine → 逐章 XHTML 抽取正文 → 产出与 TXT 相同的 [LocalChapter]，
/// 与 TXT 一样产出 [LocalChapter]，统一进入阅读引擎（ReaderPageScreen）。
enum EpubParser {

    struct Book {
        let title: String
        let author: String
        let chapters: [LocalChapter]
    }

    enum EpubError: LocalizedError {
        case notEpub
        case missingContainer
        case missingOpf
        case emptyBook

        var errorDescription: String? {
            switch self {
            case .notEpub: return "文件不是有效的 EPUB（缺少 ZIP 容器）"
            case .missingContainer: return "EPUB 缺少 META-INF/container.xml"
            case .missingOpf: return "EPUB 缺少 OPF 出版物描述文件"
            case .emptyBook: return "EPUB 没有可读取的正文章节"
            }
        }
    }

    static func parse(url: URL) throws -> Book {
        let entries: [String: Data]
        do { entries = try MiniZIP.entries(in: url) }
        catch let e as MiniZIP.ZipError { throw e }
        catch { throw EpubError.notEpub }
        return try parse(entries: entries)
    }

    static func parse(entries: [String: Data]) throws -> Book {
        // 1. container.xml → OPF 路径
        guard let containerData = entries["META-INF/container.xml"] ??
                                  entries["meta-inf/container.xml"] else {
            throw EpubError.missingContainer
        }
        guard let opfPath = rootfilePath(from: containerData) else {
            throw EpubError.missingOpf
        }
        let normalizedOPF = opfPath.hasPrefix("/") ? String(opfPath.dropFirst()) : opfPath
        guard let opfData = entries[normalizedOPF] else { throw EpubError.missingOpf }

        // 2. OPF：标题/作者 + manifest + spine
        let opfDir = (normalizedOPF as NSString).deletingLastPathComponent
        guard let opfDoc = try? XMLDocument(data: opfData) else { throw EpubError.missingOpf }

        let title = firstText(in: opfDoc, tag: "title") ?? "未命名"
        let author = firstText(in: opfDoc, tag: "creator") ?? "未知作者"

        var manifest: [String: (href: String, mediaType: String)] = [:]
        for item in elements(in: opfDoc, tag: "item") {
            guard let id = item.attributes["id"], let href = item.attributes["href"] else { continue }
            let media = item.attributes["media-type"] ?? ""
            manifest[id] = (href: href, mediaType: media)
        }

        var spineIDs: [String] = []
        for ref in elements(in: opfDoc, tag: "itemref") {
            guard let idref = ref.attributes["idref"] else { continue }
            spineIDs.append(idref)
        }
        // 兜底：有些 EPUB 的 spine 顺序信息在 manifest 里（极少见），
        // 按 manifest 顺序兜底。
        if spineIDs.isEmpty { spineIDs = Array(manifest.keys) }

        // 3. 逐章抽取正文
        var chapters: [LocalChapter] = []
        var index = 0
        for idref in spineIDs {
            guard let item = manifest[idref] else { continue }
            let isHTML = item.mediaType.contains("xhtml") || item.mediaType.contains("html")
            let isXML = item.mediaType == "application/xml" && item.href.lowercased().hasSuffix(".xhtml")
            guard isHTML || isXML else { continue }

            let resolved = resolve(href: item.href, relativeTo: opfDir)
            guard let chapterData = entries[resolved] else { continue }

            let extracted = extractChapter(from: chapterData, fallbackName: item.href)
            let text = extracted.text
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }

            chapters.append(LocalChapter(
                title: extracted.title ?? "第 \(index + 1) 章",
                content: text
            ))
            index += 1
        }

        guard !chapters.isEmpty else { throw EpubError.emptyBook }
        return Book(title: title, author: author, chapters: chapters)
    }

    // MARK: - container.xml / OPF 解析

    /// 从 container.xml 里取 rootfile 的 full-path。
    private static func rootfilePath(from data: Data) -> String? {
        guard let doc = try? XMLDocument(data: data) else { return nil }
        return elements(in: doc, tag: "rootfile").first?.attributes["full-path"]
    }

    /// 命名空间无关的本地名遍历：Fuzi 的 xpath 需要注册命名空间前缀，
    /// 而 EPUB 各书的 OPF 命名空间/前缀千奇百怪，直接按 local tag 找最稳。
    private static func elements(in doc: XMLDocument, tag target: String) -> [XMLElement] {
        guard let root = doc.root else { return [] }
        var result: [XMLElement] = []
        collectLocalTag(root, target: target, into: &result)
        return result
    }

    private static func collectLocalTag(_ element: XMLElement, target: String, into result: inout [XMLElement]) {
        if element.tag == target { result.append(element) }
        for child in element.children {
            collectLocalTag(child, target: target, into: &result)
        }
    }

    private static func firstText(in doc: XMLDocument, tag: String) -> String? {
        for el in elements(in: doc, tag: tag) {
            let t = el.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { return t }
        }
        return nil
    }

    // MARK: - XHTML → 正文

    private struct Extracted {
        let title: String?
        let text: String
    }

    /// 把一章 XHTML 抽成纯文本：块级文本元素断行，标题取首个 h1-h3。
    private static func extractChapter(from data: Data, fallbackName: String) -> Extracted {
        guard let doc = try? HTMLDocument(data: data) else {
            return Extracted(title: nil, text: "")
        }

        var title: String?
        let root = doc.root
        for heading in ["h1", "h2", "h3"] {
            if let el = root?.firstChild(tag: heading) ?? doc.body?.firstChild(tag: heading) {
                let t = el.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty { title = t; break }
            }
        }
        if title == nil {
            let fallback = (fallbackName as NSString).deletingPathExtension
            let cleaned = fallback.components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            title = cleaned.isEmpty ? nil : cleaned
        }

        let paragraphs = collectParagraphs(doc)
        let text: String
        if paragraphs.isEmpty {
            // 兜底：无块级结构（纯文本型 XHTML），按行粗提取。
            text = (doc.body?.stringValue ?? "")
                .replacingOccurrences(of: "\r\n", with: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            text = paragraphs.joined(separator: "\n")
        }
        return Extracted(title: title, text: text)
    }

    /// 只采集"文本承载块"（p/h/li/blockquote/pre），取 stringValue（含后代文本）
    /// 后停止下沉，避免 div/section 容器重复采集整个子树。
    /// br 单独产出一个空行，保证段内强制换行不丢失。
    private static let textBlockTags: Set<String> = [
        "p", "h1", "h2", "h3", "h4", "h5", "h6",
        "li", "blockquote", "pre"
    ]
    private static let skipTags: Set<String> = ["script", "style", "nav", "head", "svg"]

    private static func collectParagraphs(_ doc: HTMLDocument) -> [String] {
        guard let body = doc.body else { return [] }
        var parts: [String] = []
        var lastWasBlock = true // 开头不留空行

        func walk(_ element: XMLElement) {
            if let tag = element.tag {
                let lower = tag.lowercased()
                if skipTags.contains(lower) { return }
                if lower == "br" {
                    parts.append("")
                    lastWasBlock = true
                    return
                }
                if textBlockTags.contains(lower) {
                    let t = element.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !t.isEmpty {
                        if !lastWasBlock { parts.append("") }
                        parts.append(t)
                        lastWasBlock = false
                    }
                    return // stringValue 已含后代，不再下沉
                }
            }
            for child in element.children {
                walk(child)
            }
        }

        walk(body)
        return parts
    }

    // MARK: - 路径

    /// OPF 里 href 相对 OPF 所在目录解析。
    private static func resolve(href: String, relativeTo dir: String) -> String {
        let cleaned = href.removingPercentEncoding ?? href
        if cleaned.hasPrefix("/") {
            return String(cleaned.dropFirst())
        }
        if dir.isEmpty { return cleaned }
        return (dir as NSString).appendingPathComponent(cleaned)
    }
}