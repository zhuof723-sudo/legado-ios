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

struct BookReaderParagraph {
    let attributed: NSAttributedString
    let sourceRange: NSRange
    var isBlank: Bool { attributed.length == 0 }
}

struct BookReaderDocument {
    let title: String
    let sourceText: String
    let paragraphs: [BookReaderParagraph]
    let fingerprint: String

    /// 连续滚动专用文本：使用 TextKit 一次排整章，不使用分页器的行和页。
    func continuousText(font: UIFont, lineSpacing: Double, paragraphSpacing: Double, indent: CGFloat) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let style = NSMutableParagraphStyle()
        style.alignment = .justified
        style.lineBreakMode = .byCharWrapping
        style.lineSpacing = CGFloat(max(lineSpacing, 0))
        style.paragraphSpacing = CGFloat(max(paragraphSpacing, 0))
        style.firstLineHeadIndent = indent
        style.headIndent = 0

        for (index, paragraph) in paragraphs.enumerated() {
            if paragraph.attributed.length > 0 {
                let start = result.length
                result.append(paragraph.attributed)
                result.addAttribute(.paragraphStyle, value: style, range: NSRange(location: start, length: paragraph.attributed.length))
            }
            if index < paragraphs.count - 1 {
                let start = result.length
                result.append(NSAttributedString(string: "\n", attributes: [
                    .font: font,
                    .paragraphStyle: style
                ]))
                result.addAttribute(.paragraphStyle, value: style, range: NSRange(location: start, length: 1))
            }
        }
        return result
    }
}

enum BookReaderDocumentBuilder {
    static func fingerprint(_ text: String) -> String {
        "\(text.count)-\(text.prefix(32))-\(text.suffix(32))"
    }

    static func make(
        title: String,
        text: String,
        markers: [InlineReviewMarker],
        reviewsEnabled: Bool,
        font: UIFont,
        markerColor: UIColor
    ) -> BookReaderDocument {
        let source = text as NSString
        var ranges: [NSRange] = []
        var start = 0
        while start <= source.length {
            var end = source.length
            var next = source.length
            var cursor = start
            while cursor < source.length {
                if source.character(at: cursor) == 0x0A {
                    end = cursor
                    next = cursor + 1
                    break
                }
                cursor += 1
            }
            ranges.append(NSRange(location: start, length: end - start))
            if next >= source.length { break }
            start = next
        }
        if ranges.count > 1, ranges.last?.length == 0 { ranges.removeLast() }

        var markerMap: [Int: InlineReviewMarker] = [:]
        for marker in markers where markerMap[marker.id] == nil { markerMap[marker.id] = marker }

        let body: [NSAttributedString.Key: Any] = [.font: font]
        let markerFont = UIFont.systemFont(ofSize: max(font.pointSize - 2, 10))
        var paragraphs: [BookReaderParagraph] = []
        paragraphs.reserveCapacity(ranges.count)

        for (paragraphIndex, range) in ranges.enumerated() {
            let raw = source.substring(with: range)
            let rawNS = raw as NSString
            let output = NSMutableAttributedString()
            var cursor = 0
            var position = 0

            while position < rawNS.length {
                let scalar = rawNS.character(at: position)
                guard (0xE000...0xF8FF).contains(scalar) else {
                    position += 1
                    continue
                }
                if position > cursor {
                    output.append(NSAttributedString(
                        string: rawNS.substring(with: NSRange(location: cursor, length: position - cursor)),
                        attributes: body
                    ))
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
                output.append(NSAttributedString(string: rawNS.substring(from: cursor), attributes: body))
            }

            if reviewsEnabled, !raw.isEmpty, paragraphIndex < ranges.count - 1 {
                output.append(NSAttributedString(string: "  💬", attributes: [
                    .font: markerFont,
                    .foregroundColor: markerColor,
                    .link: BookReaderLink.paragraph(paragraphIndex).url
                ]))
            }
            paragraphs.append(BookReaderParagraph(attributed: output, sourceRange: range))
        }

        return BookReaderDocument(
            title: title,
            sourceText: text,
            paragraphs: paragraphs,
            fingerprint: fingerprint(text)
        )
    }
}
