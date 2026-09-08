import Foundation

/// 正文中的 `style: "TEXT"` 图片段评标记。
///
/// Legado Android 会保留这类图片，并在排版时把它替换成专用字符 `꧁`；
/// 这个模型在 iOS 侧保留同一份“段评图 → 可点击入口”元数据。
public struct InlineReviewMarker: Codable, Equatable, Sendable, Identifiable {
    public let id: Int
    /// 已按正文页面 URL 解析为绝对地址的图片/动作来源。
    public let source: String
    /// 图片 URL 选项中的 `click` 或 `js` 脚本。
    public let action: String?
    /// 段评图所在的正文段落序号。
    public let paragraphIndex: Int

    public init(id: Int, source: String, action: String? = nil, paragraphIndex: Int = 0) {
        self.id = id
        self.source = source
        self.action = action
        self.paragraphIndex = paragraphIndex
    }

    /// 私有使用区字符：分页时占一个字符宽度，渲染时替换为可点击段评图标。
    public var token: String {
        guard let scalar = UnicodeScalar(UInt32(0xE000 + id)), scalar.value <= 0xF8FF else { return "" }
        return String(Character(scalar))
    }
}

/// 一章已经格式化完成、但尚未分页的正文。
public struct ReaderChapterContent: Codable, Equatable, Sendable {
    public let text: String
    public let inlineReviewMarkers: [InlineReviewMarker]

    public init(text: String, inlineReviewMarkers: [InlineReviewMarker] = []) {
        self.text = text
        self.inlineReviewMarkers = inlineReviewMarkers
    }
}

/// HTML 正文格式化器。它保留 Legado 段评图的动作信息，其他 HTML 仍转换为纯文本。
public enum ReaderContentFormatter {
    public static func format(
        _ html: String,
        baseURL: String,
        markerStart: Int = 0,
        paragraphStart: Int = 0
    ) -> ReaderChapterContent {
        guard !html.isEmpty else { return ReaderChapterContent(text: "") }

        let imagePattern = try! NSRegularExpression(
            pattern: "(?is)<img\\b[^>]*>", options: []
        )
        let ns = html as NSString
        let matches = imagePattern.matches(
            in: html, range: NSRange(location: 0, length: ns.length)
        )

        var output = ""
        var cursor = 0
        var markerID = markerStart
        var paragraphIndex = paragraphStart
        var markers: [InlineReviewMarker] = []

        for match in matches {
            let before = ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            output += before
            paragraphIndex += paragraphBreakCount(in: before)
            let tag = ns.substring(with: match.range)
            if let source = imageSource(from: tag) {
                let decoded = decodeHTMLEntities(source)
                    .replacingOccurrences(of: "\\\"", with: "\"")
                let (urlPart, options) = splitURLAndOptions(decoded)
                let isTextStyle = (options["style"] ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .caseInsensitiveCompare("TEXT") == .orderedSame
                if isTextStyle,
                   let absolute = absoluteURL(urlPart, baseURL: baseURL),
                   !absolute.isEmpty,
                   markerID <= 0x18FF {
                    let action = options["click"] ?? options["js"]
                    let marker = InlineReviewMarker(
                        id: markerID,
                        source: absolute,
                        action: action,
                        paragraphIndex: paragraphIndex
                    )
                    output += marker.token
                    markers.append(marker)
                    markerID += 1
                }
            }
            cursor = match.range.location + match.range.length
        }
        output += ns.substring(from: cursor)

        let text = stripRemainingHTML(output)
        return ReaderChapterContent(text: text, inlineReviewMarkers: markers)
    }

    /// 供旧版纯文本 API 使用：不向调试页或其他非阅读调用方泄露私有 marker 字符。
    public static func removingMarkers(from text: String) -> String {
        text.replacingOccurrences(of: "[\\u{E000}-\\u{F8FF}]", with: "", options: .regularExpression)
    }

    private static func imageSource(from tag: String) -> String? {
        let pattern = try! NSRegularExpression(
            pattern: "(?i)(?:^|\\s)(?:src|data-src|data-original|data-srcset)\\s*=\\s*([\\\"'])",
            options: []
        )
        let ns = tag as NSString
        let whole = NSRange(location: 0, length: ns.length)
        guard let match = pattern.firstMatch(in: tag, range: whole), match.numberOfRanges > 1 else {
            return nil
        }
        let quote = ns.substring(with: match.range(at: 1))
        let start = match.range.location + match.range.length
        guard start < ns.length else { return nil }
        let suffix = ns.substring(from: start)
        guard let end = closingQuote(in: suffix, quote: quote) else { return nil }
        return String(suffix[..<end])
    }

    /// JSON URL 选项含有未转义双引号，因此不能简单取第一个引号。
    /// 仅接受后面是标签结尾或下一个属性的引号作为真正结束引号。
    private static func closingQuote(in value: String, quote: String) -> String.Index? {
        var cursor = value.startIndex
        while let found = value.range(of: quote, range: cursor..<value.endIndex)?.lowerBound {
            let after = value.index(after: found)
            let tail = String(value[after...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if tail.isEmpty || tail.hasPrefix(">") || tail.range(of: "^[A-Za-z_:][-A-Za-z0-9_:.]*\\s*=", options: .regularExpression) != nil {
                return found
            }
            cursor = after
        }
        return nil
    }

    private static func paragraphBreakCount(in text: String) -> Int {
        var normalized = text
        normalized = normalized.replacingOccurrences(
            of: "(?i)</(?:p|div|li|article|dd|dl|h[1-6])\\s*>|<br\\s*/?\\s*>",
            with: "\n",
            options: .regularExpression
        )
        return normalized.reduce(into: 0) { count, character in
            if character == "\n" { count += 1 }
        }
    }

    private static func splitURLAndOptions(_ source: String) -> (String, [String: String]) {
        guard let range = source.range(of: ",", options: []),
              String(source[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") else {
            return (source.trimmingCharacters(in: .whitespacesAndNewlines), [:])
        }
        let url = String(source[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        let rawOptions = String(source[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = rawOptions.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (url, [:])
        }
        var options: [String: String] = [:]
        for (key, value) in object { options[key] = "\(value)" }
        return (url, options)
    }

    private static func absoluteURL(_ source: String, baseURL: String) -> String? {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") || trimmed.hasPrefix("data:") {
            return trimmed
        }
        if trimmed.hasPrefix("//") {
            return "\(URL(string: baseURL)?.scheme ?? "https"):\(trimmed)"
        }
        guard let base = URL(string: baseURL),
              let resolved = URL(string: trimmed, relativeTo: base)?.absoluteURL else { return trimmed }
        return resolved.absoluteString
    }

    private static func stripRemainingHTML(_ input: String) -> String {
        var text = input
        text = text.replacingOccurrences(of: "(?i)<br\\s*/?\\s*>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?i)</(?:p|div|li|article|dd|dl|h[1-6])\\s*>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?i)<li\\b[^>]*>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?is)<!--.*?-->", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?is)<[^>]+>", with: "", options: .regularExpression)
        text = decodeHTMLEntities(text)
        text = text.replacingOccurrences(of: "\\r\\n?", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "[\\t \\u{00A0}]*\\n[\\t \\u{00A0}]*", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decodeHTMLEntities(_ input: String) -> String {
        var text = input
        let entities = [
            "&nbsp;": " ", "&#160;": " ", "&amp;": "&", "&lt;": "<",
            "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&apos;": "'"
        ]
        for (entity, value) in entities { text = text.replacingOccurrences(of: entity, with: value) }
        return text
    }
}
