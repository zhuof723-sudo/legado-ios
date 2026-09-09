import Foundation

/// 正文中的 Legado 段评入口。
public struct InlineReviewMarker: Codable, Equatable, Sendable, Identifiable {
    public let id: Int
    public let source: String
    public let action: String?
    public let paragraphIndex: Int

    public init(id: Int, source: String, action: String? = nil, paragraphIndex: Int = 0) {
        self.id = id
        self.source = source
        self.action = action
        self.paragraphIndex = paragraphIndex
    }

    /// 私有区占位符。分页时占一个字符位置，渲染时替换成可点击气泡。
    public var token: String {
        guard id >= 0, id <= 0x1FFF,
              let scalar = UnicodeScalar(0xE000 + id) else { return "" }
        return String(Character(scalar))
    }
}

/// 已格式化但尚未分页的章节正文。
public struct ReaderChapterContent: Codable, Equatable, Sendable {
    public let text: String
    public let inlineReviewMarkers: [InlineReviewMarker]

    public init(text: String, inlineReviewMarkers: [InlineReviewMarker] = []) {
        self.text = text
        self.inlineReviewMarkers = inlineReviewMarkers
    }
}

/// 对齐 Legado 的正文格式化：保留 `style: TEXT` 图片和 iOS 专用 `<comment>` 标签。
public enum ReaderContentFormatter {
    public static func format(
        _ html: String,
        baseURL: String,
        markerStart: Int = 0,
        paragraphStart: Int = 0
    ) -> ReaderChapterContent {
        guard !html.isEmpty else { return ReaderChapterContent(text: "") }

        let tagRegex = try! NSRegularExpression(
            pattern: "(?is)<(?:img|comment)\\b(?:[^>]|\\n)*?>", options: []
        )
        let source = html as NSString
        let fullRange = NSRange(location: 0, length: source.length)
        let matches = tagRegex.matches(in: html, range: fullRange)

        var output = ""
        var cursor = 0
        var markerID = markerStart
        var paragraphIndex = paragraphStart
        var markers: [InlineReviewMarker] = []

        for match in matches {
            let before = source.substring(with: NSRange(
                location: cursor,
                length: match.range.location - cursor
            ))
            output += before
            paragraphIndex += paragraphBreakCount(in: before)

            let tag = source.substring(with: match.range)
            if tag.lowercased().hasPrefix("<comment"),
               let action = attributeValue("onPress", in: tag),
               let url = firstURL(in: action, baseURL: baseURL),
               markerID <= 0x1FFF {
                let marker = InlineReviewMarker(
                    id: markerID,
                    source: url,
                    action: action,
                    paragraphIndex: paragraphIndex
                )
                output += marker.token
                markers.append(marker)
                markerID += 1
            } else if let image = imageSource(in: tag) {
                let decoded = decodeEntities(image)
                    .replacingOccurrences(of: "\\\"", with: "\"")
                let parts = splitImageSourceAndOptions(decoded)
                let style = (parts.options["style"] ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if style.caseInsensitiveCompare("TEXT") == .orderedSame,
                   let url = absoluteURL(parts.url, baseURL: baseURL),
                   !url.isEmpty,
                   markerID <= 0x1FFF {
                    let marker = InlineReviewMarker(
                        id: markerID,
                        source: url,
                        action: parts.options["click"] ?? parts.options["js"],
                        paragraphIndex: paragraphIndex
                    )
                    output += marker.token
                    markers.append(marker)
                    markerID += 1
                }
            }
            cursor = match.range.location + match.range.length
        }
        output += source.substring(from: cursor)

        return ReaderChapterContent(
            text: stripRemainingHTML(output),
            inlineReviewMarkers: markers
        )
    }

    public static func removingMarkers(from text: String) -> String {
        text.replacingOccurrences(
            of: "[\\u{E000}-\\u{FFFF}]",
            with: "",
            options: .regularExpression
        )
    }

    private static func attributeValue(_ name: String, in tag: String) -> String? {
        let lowerTag = tag.lowercased()
        let lowerName = name.lowercased()
        guard let nameRange = lowerTag.range(of: lowerName) else { return nil }
        var index = nameRange.upperBound
        while index < lowerTag.endIndex,
              lowerTag[index].isWhitespace { index = lowerTag.index(after: index) }
        guard index < lowerTag.endIndex, lowerTag[index] == "=" else { return nil }
        index = lowerTag.index(after: index)
        while index < lowerTag.endIndex,
              lowerTag[index].isWhitespace { index = lowerTag.index(after: index) }
        guard index < tag.endIndex else { return nil }
        let quote = tag[index]
        guard quote == "\"" || quote == "'" else { return nil }
        index = tag.index(after: index)

        var value = ""
        var escaped = false
        while index < tag.endIndex {
            let character = tag[index]
            if escaped {
                value.append(character)
                escaped = false
            } else if character == "\\" {
                value.append(character)
                escaped = true
            } else if character == quote {
                return value
            } else {
                value.append(character)
            }
            index = tag.index(after: index)
        }
        return nil
    }

    private static func imageSource(in tag: String) -> String? {
        for name in ["src", "data-src", "data-original", "data-srcset"] {
            if let value = attributeValue(name, in: tag) { return value }
        }
        return nil
    }

    private static func firstURL(in value: String, baseURL: String) -> String? {
        let candidates = ["https://", "http://"]
        var start: String.Index?
        for candidate in candidates {
            if let found = value.range(of: candidate, options: .caseInsensitive)?.lowerBound {
                if start == nil || found < start! { start = found }
            }
        }
        guard let start else { return absoluteURL(value, baseURL: baseURL) }
        var end = start
        while end < value.endIndex {
            let c = value[end]
            if c == "'" || c == "\"" || c == ")" || c.isWhitespace { break }
            end = value.index(after: end)
        }
        let url = String(value[start..<end])
        return absoluteURL(url, baseURL: baseURL)
    }

    private static func splitImageSourceAndOptions(_ source: String) -> (url: String, options: [String: String]) {
        var index = source.startIndex
        while let comma = source[index...].firstIndex(of: ",") {
            let rest = String(source[source.index(after: comma)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if rest.hasPrefix("{") {
                let url = String(source[..<comma]).trimmingCharacters(in: .whitespacesAndNewlines)
                if let data = rest.data(using: .utf8),
                   let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    var options: [String: String] = [:]
                    for (key, value) in object { options[key] = String(describing: value) }
                    return (url, options)
                }
                return (url, [:])
            }
            index = source.index(after: comma)
            if index >= source.endIndex { break }
        }
        return (source.trimmingCharacters(in: .whitespacesAndNewlines), [:])
    }

    private static func absoluteURL(_ value: String, baseURL: String) -> String? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if value.lowercased().hasPrefix("http://") ||
            value.lowercased().hasPrefix("https://") ||
            value.lowercased().hasPrefix("data:") { return value }
        if value.hasPrefix("//") {
            return "\(URL(string: baseURL)?.scheme ?? "https"):\(value)"
        }
        guard let base = URL(string: baseURL),
              let url = URL(string: value, relativeTo: base)?.absoluteURL else { return value }
        return url.absoluteString
    }

    private static func paragraphBreakCount(in text: String) -> Int {
        let normalized = text.replacingOccurrences(
            of: "(?is)</(?:p|div|li|article|dd|dl|h[1-6])\\s*>|<br\\s*/?\\s*>",
            with: "\n",
            options: .regularExpression
        )
        return normalized.reduce(into: 0) { count, character in
            if character == "\n" { count += 1 }
        }
    }

    private static func stripRemainingHTML(_ input: String) -> String {
        var text = input
        text = text.replacingOccurrences(
            of: "(?is)<br\\s*/?\\s*>", with: "\n", options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: "(?is)</(?:p|div|li|article|dd|dl|h[1-6])\\s*>",
            with: "\n", options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: "(?is)<!--.*?-->", with: "", options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: "(?is)<[^>]+>", with: "", options: .regularExpression
        )
        text = decodeEntities(text)
        text = text.replacingOccurrences(of: "\\r\\n?", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decodeEntities(_ input: String) -> String {
        var text = input
        let entities: [String: String] = [
            "&nbsp;": " ", "&#160;": " ", "&amp;": "&", "&lt;": "<",
            "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&apos;": "'"
        ]
        for (entity, value) in entities { text = text.replacingOccurrences(of: entity, with: value) }
        return text
    }
}
