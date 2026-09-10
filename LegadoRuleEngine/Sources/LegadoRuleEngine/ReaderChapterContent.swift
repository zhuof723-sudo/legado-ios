import Foundation

/// 正文中的 Legado 段评入口。
public struct InlineReviewMarker: Codable, Equatable, Sendable, Identifiable {
    public let id: Int
    public let source: String
    public let action: String?
    public let paragraphIndex: Int
    public let count: String
    public let title: String

    public init(
        id: Int,
        source: String,
        action: String? = nil,
        paragraphIndex: Int = 0,
        count: String = "",
        title: String = "段评"
    ) {
        self.id = id
        self.source = source
        self.action = action
        self.paragraphIndex = paragraphIndex
        self.count = count
        self.title = title
    }

    private enum CodingKeys: String, CodingKey {
        case id, source, action, paragraphIndex, count, title
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        source = try container.decode(String.self, forKey: .source)
        action = try container.decodeIfPresent(String.self, forKey: .action)
        paragraphIndex = try container.decodeIfPresent(Int.self, forKey: .paragraphIndex) ?? 0
        count = try container.decodeIfPresent(String.self, forKey: .count) ?? ""
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "段评"
    }

    /// 私有区占位符。分页时占一个字符位置，渲染时替换成可点击气泡。
    public var token: String {
        guard id >= 0, id <= 0x1FFF,
              let scalar = UnicodeScalar(0xE000 + id) else { return "" }
        return String(scalar)
    }
}

/// 已格式化但尚未分页的章节正文。
public struct ReaderChapterContent: Codable, Equatable, Sendable {
    /// 当前正文缓存格式。版本 3 开始明确记录段评处理是否已经完成，
    /// 旧版纯文本和旧 JSON 缓存会被在线阅读器自动重新获取。
    public static let currentFormatVersion = 4
    public let formatVersion: Int
    public let text: String
    public let inlineReviewMarkers: [InlineReviewMarker]
    public let inlineReviewProcessed: Bool
    public let inlineReviewEnabled: Bool

    public init(
        text: String,
        inlineReviewMarkers: [InlineReviewMarker] = [],
        formatVersion: Int = ReaderChapterContent.currentFormatVersion,
        inlineReviewProcessed: Bool = true,
        inlineReviewEnabled: Bool = true
    ) {
        self.formatVersion = formatVersion
        self.text = text
        self.inlineReviewMarkers = inlineReviewMarkers
        self.inlineReviewProcessed = inlineReviewProcessed
        self.inlineReviewEnabled = inlineReviewEnabled
    }

    private enum CodingKeys: String, CodingKey {
        case formatVersion, text, inlineReviewMarkers
        case inlineReviewProcessed, inlineReviewEnabled
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try container.decodeIfPresent(Int.self, forKey: .formatVersion) ?? 1
        text = try container.decode(String.self, forKey: .text)
        inlineReviewMarkers = try container.decodeIfPresent(
            [InlineReviewMarker].self,
            forKey: .inlineReviewMarkers
        ) ?? []
        // 旧缓存没有这两个字段，必须视为尚未经过段评处理。
        inlineReviewProcessed = try container.decodeIfPresent(
            Bool.self,
            forKey: .inlineReviewProcessed
        ) ?? false
        inlineReviewEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .inlineReviewEnabled
        ) ?? false
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

        // getComments 在部分书山接口响应中会返回 &lt;comment ...&gt;，
        // 必须先解码，否则后面的 HTML 标签解析永远不会命中。
        let normalizedHTML = decodeEntities(html)
        guard let tagRegex = try? NSRegularExpression(
            pattern: "(?is)<(?:img|comment)(?:[^>])*?>", options: []
        ) else { return ReaderChapterContent(text: html) }
        let source = normalizedHTML as NSString
        let fullRange = NSRange(location: 0, length: source.length)
        let matches = tagRegex.matches(in: normalizedHTML, range: fullRange)

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
               markerID <= 0x1FFF {
                let target = browserTarget(in: action, baseURL: baseURL)
                let marker = InlineReviewMarker(
                    id: markerID,
                    source: target?.url ?? action,
                    action: action,
                    paragraphIndex: paragraphIndex,
                    count: attributeValue("count", in: tag) ?? "",
                    title: target?.title.isEmpty == false ? target?.title ?? "段评" : "段评"
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
                    let action = parts.options["click"] ?? parts.options["action"] ?? parts.options["js"]
                    let marker = InlineReviewMarker(
                        id: markerID,
                        source: url,
                        action: action,
                        paragraphIndex: paragraphIndex,
                        count: bubbleCount(fromImageSource: parts.url),
                        title: action.flatMap { browserTarget(in: $0, baseURL: baseURL)?.title } ?? "段评"
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

    private static func browserTarget(in action: String, baseURL: String) -> (url: String, title: String)? {
        let pattern = #"(?:showReadingBrowser|showCmt|startBrowser(?:Dp)?)\(\s*'([^']*)'(?:\s*,\s*'([^']*)')?\s*\)"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
            let ns = action as NSString
            if let match = regex.firstMatch(
                in: action,
                range: NSRange(location: 0, length: ns.length)
            ), match.numberOfRanges >= 2 {
                let rawURL = ns.substring(with: match.range(at: 1))
                let title = match.numberOfRanges >= 3 && match.range(at: 2).location != NSNotFound
                    ? ns.substring(with: match.range(at: 2))
                    : ""
                if let url = absoluteURL(rawURL, baseURL: baseURL), !url.isEmpty {
                    return (url, title)
                }
            }
        }

        let candidates = ["https://", "http://"]
        var start: String.Index?
        for candidate in candidates {
            if let found = action.range(of: candidate, options: .caseInsensitive)?.lowerBound,
               start == nil || found < start! {
                start = found
            }
        }
        guard let start else { return nil }
        var end = start
        while end < action.endIndex {
            let character = action[end]
            if character == "'" || character == "\"" || character == ")" || character.isWhitespace { break }
            end = action.index(after: end)
        }
        guard let url = absoluteURL(String(action[start..<end]), baseURL: baseURL) else { return nil }
        return (url, "")
    }

    private static func bubbleCount(fromImageSource source: String) -> String {
        let prefix = "data:image/svg+xml"
        guard source.lowercased().hasPrefix(prefix),
              let comma = source.firstIndex(of: ",") else { return "" }
        let metadata = source[..<comma].lowercased()
        let payload = String(source[source.index(after: comma)...])
        let svg: String?
        if metadata.contains(";base64") {
            svg = Data(base64Encoded: payload, options: [.ignoreUnknownCharacters])
                .flatMap { String(data: $0, encoding: .utf8) }
        } else {
            svg = payload.removingPercentEncoding ?? payload
        }
        guard let svg,
              let regex = try? NSRegularExpression(
                pattern: #"<text\b[^>]*>(.*?)</text>"#,
                options: [.caseInsensitive, .dotMatchesLineSeparators]
              ) else { return "" }
        let ns = svg as NSString
        guard let match = regex.firstMatch(
            in: svg,
            range: NSRange(location: 0, length: ns.length)
        ), match.numberOfRanges > 1 else { return "" }
        let value = ns.substring(with: match.range(at: 1))
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.range(of: #"^[0-9]+[+]?$"#, options: .regularExpression) != nil ? value : ""
    }

    private static func imageSource(in tag: String) -> String? {
        for name in ["src", "data-src", "data-original", "data-srcset"] {
            if let value = attributeValue(name, in: tag) { return value }
        }
        return nil
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
