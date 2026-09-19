import Foundation

/// 阅读内核统一正文规范化入口。
/// 只修复传输层与 HTML 层产生的空白问题，不猜测、不自动补配中文引号。
enum ReadingTextNormalizer {
    struct Paragraph: Equatable {
        let text: String
        let sourceRange: NSRange
        let isBlank: Bool
    }

    static func normalizePlainText(_ input: String) -> String {
        var text = normalizeLineEndings(input)
        text = text.replacingOccurrences(
            of: "[\\t\\u{00A0}\\u{3000} ]+",
            with: " ",
            options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: "[\\t\\u{00A0}\\u{3000} ]*\\n[\\t\\u{00A0}\\u{3000} ]*",
            with: "\n",
            options: .regularExpression
        )
        text = repairDetachedClosingQuotes(text)
        return trimOuterBlankLines(text)
    }

    static func normalizeHTML(_ input: String) -> String {
        var text = normalizeLineEndings(input)
        text = replacing(text, pattern: "(?i)<\\s*br\\s*/?\\s*>", with: "\n")
        text = replacing(
            text,
            pattern: "(?i)</?\\s*(?:p|div|li|section|article|blockquote|h[1-6])\\b[^>]*>",
            with: "\n"
        )
        text = replacing(text, pattern: "(?s)<script\\b[^>]*>.*?</script>", with: "")
        text = replacing(text, pattern: "(?s)<style\\b[^>]*>.*?</style>", with: "")
        text = replacing(text, pattern: "(?s)<[^>]+>", with: "")
        text = decodeHTMLEntities(text)
        return normalizePlainText(text)
    }

    static func paragraphs(in normalizedText: String) -> [Paragraph] {
        let source = normalizedText as NSString
        guard source.length > 0 else { return [] }

        var result: [Paragraph] = []
        var lineStart = 0
        for index in 0...source.length {
            let isEnd = index == source.length
            let isNewline = !isEnd && source.character(at: index) == 10
            guard isEnd || isNewline else { continue }

            let range = NSRange(location: lineStart, length: index - lineStart)
            let value = source.substring(with: range)
            result.append(Paragraph(
                text: value,
                sourceRange: range,
                isBlank: value.isEmpty
            ))
            lineStart = index + 1
        }
        return result
    }

    private static func normalizeLineEndings(_ input: String) -> String {
        input
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{2028}", with: "\n")
            .replacingOccurrences(of: "\u{2029}", with: "\n")
    }

    private static func repairDetachedClosingQuotes(_ input: String) -> String {
        replacing(
            input,
            pattern: "([。！？!?…])[^\\S\\n]*\\n[^\\S\\n]*([”’」』])",
            with: "$1$2"
        )
    }

    private static func trimOuterBlankLines(_ input: String) -> String {
        input.replacingOccurrences(
            of: "^(?:\\n)+|(?:\\n)+$",
            with: "",
            options: .regularExpression
        )
    }

    private static func decodeHTMLEntities(_ input: String) -> String {
        var text = input
        let named: [(String, String)] = [
            ("&nbsp;", " "), ("&#160;", " "), ("&amp;", "&"),
            ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""),
            ("&apos;", "'"), ("&#39;", "'")
        ]
        for (entity, value) in named {
            text = text.replacingOccurrences(of: entity, with: value)
        }
        return text
    }

    private static func replacing(_ input: String, pattern: String, with replacement: String) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return input }
        let range = NSRange(location: 0, length: (input as NSString).length)
        return expression.stringByReplacingMatches(
            in: input,
            range: range,
            withTemplate: replacement
        )
    }
}
