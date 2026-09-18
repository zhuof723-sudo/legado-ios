import UIKit
import LegadoRuleEngine

// MARK: - 段评链接

enum ReaderPageLink: Equatable {
    case paragraph(Int)
    case marker(Int)

    var url: URL {
        switch self {
        case .paragraph(let index): return URL(string: "reader-review://paragraph/\(index)")!
        case .marker(let id): return URL(string: "reader-review://marker/\(id)")!
        }
    }

    static func resolve(_ url: URL) -> ReaderPageLink? {
        guard url.scheme == "reader-review", let host = url.host,
              url.pathComponents.count > 1,
              let value = Int(url.pathComponents[1]) else { return nil }
        switch host {
        case "paragraph": return .paragraph(value)
        case "marker": return .marker(value)
        default: return nil
        }
    }
}

// MARK: - 文档模型

struct ReaderPageParagraph {
    let attributed: NSAttributedString
    let sourceRange: NSRange
    var isBlank: Bool { attributed.length == 0 }
}

struct ReaderPageDocument {
    let title: String
    let sourceText: String
    let paragraphs: [ReaderPageParagraph]
    let fingerprint: String
}

enum ReaderPageDocumentBuilder {
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
    ) -> ReaderPageDocument {
        let nsText = text as NSString
        var ranges: [NSRange] = []
        var start = 0
        while start <= nsText.length {
            var end = nsText.length
            var next = nsText.length
            var cursor = start
            while cursor < nsText.length {
                if nsText.character(at: cursor) == 0x0A {
                    end = cursor
                    next = cursor + 1
                    break
                }
                cursor += 1
            }
            ranges.append(NSRange(location: start, length: end - start))
            if next >= nsText.length { break }
            start = next
        }
        if ranges.count > 1, ranges.last?.length == 0 { ranges.removeLast() }

        var markerMap: [Int: InlineReviewMarker] = [:]
        for marker in markers where markerMap[marker.id] == nil {
            markerMap[marker.id] = marker
        }

        let bodyAttributes: [NSAttributedString.Key: Any] = [.font: font]
        let markerFont = UIFont.systemFont(ofSize: max(font.pointSize - 2, 10))
        var paragraphs: [ReaderPageParagraph] = []
        paragraphs.reserveCapacity(ranges.count)

        for (paragraphIndex, range) in ranges.enumerated() {
            let raw = nsText.substring(with: range)
            let result = NSMutableAttributedString()
            let rawNS = raw as NSString
            var cursor = 0
            var position = 0

            while position < rawNS.length {
                let scalar = rawNS.character(at: position)
                guard (0xE000...0xF8FF).contains(scalar) else {
                    position += 1
                    continue
                }
                if position > cursor {
                    result.append(NSAttributedString(
                        string: rawNS.substring(with: NSRange(location: cursor, length: position - cursor)),
                        attributes: bodyAttributes
                    ))
                }
                let markerID = Int(scalar) - 0xE000
                if let marker = markerMap[markerID] {
                    let count = marker.count.trimmingCharacters(in: .whitespacesAndNewlines)
                    let label = count.isEmpty ? "💬" : "💬\(count)"
                    result.append(NSAttributedString(string: label, attributes: [
                        .font: markerFont,
                        .foregroundColor: markerColor,
                        .link: ReaderPageLink.marker(marker.id).url
                    ]))
                }
                position += 1
                cursor = position
            }
            if cursor < rawNS.length {
                result.append(NSAttributedString(string: rawNS.substring(from: cursor), attributes: bodyAttributes))
            }

            if reviewsEnabled, !raw.isEmpty, paragraphIndex < ranges.count - 1 {
                result.append(NSAttributedString(string: "  💬", attributes: [
                    .font: markerFont,
                    .foregroundColor: markerColor,
                    .link: ReaderPageLink.paragraph(paragraphIndex).url
                ]))
            }

            paragraphs.append(ReaderPageParagraph(attributed: result, sourceRange: range))
        }

        return ReaderPageDocument(
            title: title,
            sourceText: text,
            paragraphs: paragraphs,
            fingerprint: fingerprint(text)
        )
    }
}
