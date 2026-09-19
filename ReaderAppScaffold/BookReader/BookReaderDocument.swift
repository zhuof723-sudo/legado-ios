import UIKit
import LegadoRuleEngine

// MARK: - 段评链接

enum BookReaderLink: Equatable {
    case paragraph(Int)
    case marker(Int)

    var url: URL {
        switch self {
        case .paragraph(let index): return URL(string: "book-reader-review://paragraph/\(index)")!
        case .marker(let id): return URL(string: "book-reader-review://marker/\(id)")!
        }
    }

    static func resolve(_ url: URL) -> BookReaderLink? {
        guard url.scheme == "book-reader-review", let host = url.host,
              url.pathComponents.count > 1,
              let value = Int(url.pathComponents[1]) else { return nil }
        switch host {
        case "paragraph": return .paragraph(value)
        case "marker": return .marker(value)
        default: return nil
        }
    }
}

// MARK: - 段落角色

/// 段落语义角色：章标题单独成行并与正文拉开距离，是目标排版的第一要素。
enum BookReaderParagraphKind {
    case chapterTitle
    case body
    case blank
}

struct BookReaderParagraph {
    let attributed: NSAttributedString
    let sourceRange: NSRange
    let kind: BookReaderParagraphKind
    var isBlank: Bool { attributed.length == 0 || kind == .blank }
}

struct BookReaderDocument {
    let title: String
    let sourceText: String
    let paragraphs: [BookReaderParagraph]
    let fingerprint: String

    /// 连续滚动专用文本：TextKit 一次排整章，不使用分页器的行与页。
    func continuousText(font: UIFont, lineSpacing: Double, paragraphSpacing: Double, indent: CGFloat, titleSpacing: Double) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let bodyStyle = NSMutableParagraphStyle()
        bodyStyle.alignment = .justified
        bodyStyle.lineBreakMode = .byCharWrapping
        bodyStyle.lineSpacing = CGFloat(max(lineSpacing, 0))
        bodyStyle.paragraphSpacing = CGFloat(max(paragraphSpacing, 0))
        bodyStyle.firstLineHeadIndent = indent
        bodyStyle.headIndent = 0

        let titleStyle = NSMutableParagraphStyle()
        titleStyle.alignment = .left
        titleStyle.lineBreakMode = .byWordWrapping
        titleStyle.paragraphSpacing = CGFloat(max(titleSpacing, 0))
        titleStyle.firstLineHeadIndent = 0
        titleStyle.headIndent = 0

        for (index, paragraph) in paragraphs.enumerated() {
            if paragraph.attributed.length > 0 {
                let start = result.length
                result.append(paragraph.attributed)
                let style = paragraph.kind == .chapterTitle ? titleStyle : bodyStyle
                result.addAttribute(.paragraphStyle, value: style, range: NSRange(location: start, length: paragraph.attributed.length))
            }
            if index < paragraphs.count - 1 {
                let start = result.length
                result.append(NSAttributedString(string: "\n", attributes: [.font: font, .paragraphStyle: bodyStyle]))
                result.addAttribute(.paragraphStyle, value: bodyStyle, range: NSRange(location: start, length: 1))
            }
        }
        return result
    }
}

enum BookReaderDocumentBuilder {
    static func fingerprint(_ text: String) -> String {
        "\(text.count)-\(text.prefix(32))-\(text.suffix(32))"
    }

    /// 章标题识别：整行且很短、形如「第X章 …」或在首行的书名式标题。
    static func isChapterTitleLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 40 else { return false }
        let patterns = [
            "^第[0-9零〇一二三四五六七八九十百千万两]{1,10}[章节卷回部集篇话幕][\\s\\S]{0,32}$",
            "^(序章|楔子|引子|尾声|终章|后记|番外)[\\s\\S]{0,24}$",
            "^(Chapter|CHAPTER)\\s+\\d+[\\s\\S]{0,32}$"
        ]
        for pattern in patterns {
            if trimmed.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil { return true }
        }
        return false
    }

    static func make(
        title: String,
        text: String,
        markers: [InlineReviewMarker],
        reviewsEnabled: Bool,
        font: UIFont,
        markerColor: UIColor
    ) -> BookReaderDocument {
        let normalizedText = ReadingTextNormalizer.normalizePlainText(text)
        let source = normalizedText as NSString
        var ranges: [NSRange] = []
        var start = 0
        while start <= source.length {
            var end = source.length
            var next = source.length
            var cursor = start
            while cursor < source.length {
                if source.character(at: cursor) == 0x0A { end = cursor; next = cursor + 1; break }
                cursor += 1
            }
            ranges.append(NSRange(location: start, length: end - start))
            if next >= source.length { break }
            start = next
        }
        if ranges.count > 1, ranges.last?.length == 0 { ranges.removeLast() }

        var markerMap: [Int: InlineReviewMarker] = [:]
        for marker in markers where markerMap[marker.id] == nil { markerMap[marker.id] = marker }

        let bodyAttributes: [NSAttributedString.Key: Any] = [.font: font]
        let titleFont = UIFont(descriptor: font.fontDescriptor, size: font.pointSize + 4)
        let titleAttributes: [NSAttributedString.Key: Any] = [.font: titleFont]
        let markerFont = UIFont.systemFont(ofSize: max(font.pointSize - 2, 10))

        var paragraphs: [BookReaderParagraph] = []
        paragraphs.reserveCapacity(ranges.count + 3)

        // ① 章节名独立成行：内容里没有标题行时，用章节名合成一行。
        var synthesizedTitle = false
        if let firstRange = ranges.first {
            let firstLine = source.substring(with: firstRange)
            synthesizedTitle = !isChapterTitleLine(firstLine)
        } else {
            synthesizedTitle = true
        }
        if synthesizedTitle {
            let heading = title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !heading.isEmpty {
                paragraphs.append(BookReaderParagraph(
                    attributed: NSAttributedString(string: heading, attributes: titleAttributes),
                    sourceRange: NSRange(location: 0, length: 0),
                    kind: .chapterTitle
                ))
                paragraphs.append(BookReaderParagraph(
                    attributed: NSAttributedString(string: "", attributes: bodyAttributes),
                    sourceRange: NSRange(location: 0, length: 0),
                    kind: .blank
                ))
            }
        }

        for (paragraphIndex, range) in ranges.enumerated() {
            let raw = source.substring(with: range)
            let rawNS = raw as NSString
            let output = NSMutableAttributedString()
            var cursor = 0
            var position = 0

            while position < rawNS.length {
                let scalar = rawNS.character(at: position)
                guard (0xE000...0xF8FF).contains(scalar) else { position += 1; continue }
                if position > cursor {
                    output.append(NSAttributedString(string: rawNS.substring(with: NSRange(location: cursor, length: position - cursor)), attributes: bodyAttributes))
                }
                let markerID = Int(scalar) - 0xE000
                if let marker = markerMap[markerID] {
                    let count = marker.count.trimmingCharacters(in: .whitespacesAndNewlines)
                    let label = count.isEmpty ? "💬" : "💬\(count)"
                    output.append(NSAttributedString(string: label, attributes: [
                        .font: markerFont,
                        .foregroundColor: markerColor,
                        .link: BookReaderLink.marker(marker.id).url
                    ]))
                }
                position += 1
                cursor = position
            }
            if cursor < rawNS.length {
                output.append(NSAttributedString(string: rawNS.substring(from: cursor), attributes: bodyAttributes))
            }

            // ② 内容首行本身就是章标题：升级为标题角色（改用标题字号）。
            let isTitle = paragraphIndex == 0 && !synthesizedTitle && isChapterTitleLine(raw)
            if isTitle, output.length > 0 {
                output.addAttribute(.font, value: titleFont, range: NSRange(location: 0, length: output.length))
            }

            if reviewsEnabled, !raw.isEmpty, paragraphIndex < ranges.count - 1 {
                output.append(NSAttributedString(string: "  💬", attributes: [
                    .font: markerFont,
                    .foregroundColor: markerColor,
                    .link: BookReaderLink.paragraph(paragraphIndex).url
                ]))
            }

            paragraphs.append(BookReaderParagraph(
                attributed: output,
                sourceRange: range,
                kind: isTitle ? .chapterTitle : (output.length == 0 ? .blank : .body)
            ))
        }

        return BookReaderDocument(
            title: title,
            sourceText: normalizedText,
            paragraphs: paragraphs,
            fingerprint: fingerprint(normalizedText)
        )
    }
}
