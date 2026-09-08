import UIKit
import LegadoRuleEngine

/// Legado 段评图在 iOS 阅读器中的交互适配。
/// Android 原版会把正文末尾 `style:"TEXT"` 的 img 转成 `꧁`，并保留其 click/js 选项；
/// iOS 使用专用 URL 让 UITextView 可靠地处理点击。
public enum ReviewLinkHelper {
    public static let scheme = "review"
    public static let host = "paragraph"
    public static let markerHost = "marker"
    public static let reviewButtonText = "  💬"

    public static func reviewURL(for paragraphIndex: Int) -> URL {
        URL(string: "\(scheme)://\(host)/\(paragraphIndex)")!
    }

    public static func markerURL(for markerID: Int) -> URL {
        URL(string: "\(scheme)://\(markerHost)/\(markerID)")!
    }

    public static func isReviewURL(_ url: URL) -> Bool {
        url.scheme == scheme && (url.host == host || url.host == markerHost)
    }

    public static func paragraphIndex(from url: URL) -> Int? {
        guard isReviewURL(url), url.host == host else { return nil }
        let components = url.pathComponents
        guard components.count >= 2 else { return nil }
        return Int(components[1])
    }

    public static func markerID(from url: URL) -> Int? {
        guard isReviewURL(url), url.host == markerHost else { return nil }
        let components = url.pathComponents
        guard components.count >= 2 else { return nil }
        return Int(components[1])
    }

    /// 给普通纯文本段落添加兼容段评入口。
    public static func attachReviewLinks(
        to text: String,
        attributes: [NSAttributedString.Key: Any],
        reviewCounts: [Int: Int] = [:]
    ) -> NSAttributedString {
        let paragraphs = text.components(separatedBy: "\n")
        let result = NSMutableAttributedString()
        for (index, paragraph) in paragraphs.enumerated() {
            result.append(NSAttributedString(string: paragraph, attributes: attributes))
            if index < paragraphs.count - 1 {
                var linkAttributes = attributes
                linkAttributes[.link] = reviewURL(for: index)
                linkAttributes[.foregroundColor] = UIColor.systemGray
                let count = reviewCounts[index] ?? 0
                let title = count > 0 ? "  💬\(min(count, 999))" : reviewButtonText
                result.append(NSAttributedString(string: title, attributes: linkAttributes))
                result.append(NSAttributedString(string: "\n", attributes: attributes))
            }
        }
        return result
    }

    /// 将正文中私有区 marker 替换成可点击的段评图标，并保留普通文本。
    public static func attachInlineReviewLinks(
        to text: String,
        markers: [InlineReviewMarker],
        attributes: [NSAttributedString.Key: Any],
        reviewCounts: [Int: Int] = [:]
    ) -> NSAttributedString {
        let map = Dictionary(uniqueKeysWithValues: markers.map { ($0.id, $0) })
        let result = NSMutableAttributedString()
        let markerPattern = try! NSRegularExpression(pattern: "[\\u{E000}-\\u{F8FF}]")
        let ns = text as NSString
        var cursor = 0
        for match in markerPattern.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            if match.range.location > cursor {
                result.append(NSAttributedString(
                    string: ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor)),
                    attributes: attributes
                ))
            }
            let scalarValue = ns.substring(with: match.range).unicodeScalars.first?.value ?? 0
            let id = Int(scalarValue) - 0xE000
            if let marker = map[id] {
                var linkAttributes = attributes
                linkAttributes[.link] = markerURL(for: marker.id)
                linkAttributes[.foregroundColor] = UIColor.systemGray
                linkAttributes[.font] = (attributes[.font] as? UIFont)?.withSize(
                    max(11, ((attributes[.font] as? UIFont)?.pointSize ?? 14) * 0.9)
                )
                let count = reviewCounts[marker.paragraphIndex] ?? 0
                let title = count > 0 ? "💬\(min(count, 999))" : "💬"
                result.append(NSAttributedString(string: title, attributes: linkAttributes))
            } else {
                result.append(NSAttributedString(string: "", attributes: attributes))
            }
            cursor = match.range.location + match.range.length
        }
        if cursor < ns.length {
            result.append(NSAttributedString(string: ns.substring(from: cursor), attributes: attributes))
        }
        return result
    }

    public static func extractPlainText(from attributedText: NSAttributedString) -> String {
        let plain = NSMutableAttributedString(attributedString: attributedText)
        plain.removeAttribute(.link, range: NSRange(location: 0, length: plain.length))
        return plain.string
            .replacingOccurrences(of: "\\s*💬[0-9]*", with: "", options: .regularExpression)
    }
}
