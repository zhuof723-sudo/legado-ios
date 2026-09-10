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
        return Int(components[1].replacingOccurrences(of: "-", with: ""))
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
    /// 这里不能用 NSRegularExpression 扫 U+E000...U+F8FF：ICU 不接受
    /// `[\u{E000}-...]` 这种 Swift 风格十六进制范围，旧版会在这一行直接 SIGTRAP；
    /// 而使用 ICU 的 `[\uE000-\uFFFF]` 又会把中文正文一起匹配掉。
    public static func attachInlineReviewLinks(
        to text: String,
        markers: [InlineReviewMarker],
        attributes: [NSAttributedString.Key: Any],
        reviewCounts: [Int: Int] = [:]
    ) -> NSAttributedString {
        var map: [Int: InlineReviewMarker] = [:]
        map.reserveCapacity(markers.count)
        for marker in markers where (0...InlineReviewMarker.markerTokenLimit).contains(marker.id) {
            // 同一章架构建议由正文格式化器保证唯一；即使旧缓存出现重复 id，
            // 也不能用 Dictionary(uniqueKeysWithValues:) 让阅读器崩溃。
            if map[marker.id] == nil { map[marker.id] = marker }
        }

        let result = NSMutableAttributedString()
        let ns = text as NSString
        var cursor = 0
        var index = 0
        while index < ns.length {
            let scalarValue = ns.character(at: index)
            guard (0xE000...0xF8FF).contains(scalarValue) else {
                index += 1
                continue
            }
            if index > cursor {
                result.append(NSAttributedString(
                    string: ns.substring(with: NSRange(location: cursor, length: index - cursor)),
                    attributes: attributes
                ))
            }
            let id = Int(scalarValue) - 0xE000
            if let marker = map[id] {
                let fallbackCount = reviewCounts[marker.paragraphIndex] ?? 0
                let countText = marker.count.isEmpty
                    ? (fallbackCount > 0 ? "\(min(fallbackCount, 999))" : "")
                    : marker.count
                let image = ReviewBadgeRenderer.bubble(
                    count: countText,
                    pointSize: (attributes[.font] as? UIFont)?.pointSize ?? 17,
                    color: UIColor.secondaryLabel
                )
                let attachment = NSTextAttachment()
                attachment.image = image
                attachment.bounds = CGRect(
                    x: 0,
                    y: ((attributes[.font] as? UIFont)?.descender ?? -3) - max(2, image.size.height * 0.04),
                    width: image.size.width,
                    height: image.size.height
                )
                let markerString = NSMutableAttributedString(attachment: attachment)
                markerString.addAttribute(.link, value: markerURL(for: marker.id), range: NSRange(location: 0, length: markerString.length))
                markerString.addAttribute(.accessibilityTextCustom, value: marker.title, range: NSRange(location: 0, length: markerString.length))
                result.append(markerString)
            }
            index += 1
            cursor = index
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
