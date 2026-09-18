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

    // MARK: - 富文本构建（分页前调用，附件宽度参与排版测量）

    /// 构建带内嵌段评气泡的整章富文本。
    /// PUA 占位符（U+E000...U+F8FF）在这里替换为 NSTextAttachment 气泡；
    /// 由于发生在分页之前，气泡的真实宽度会参与每一页的排版测量，
    /// 页面不会因“量页窄、渲染宽”而被 UITextView 顶出可见区。
    public static func buildInlineReviewContent(
        text: String,
        markers: [InlineReviewMarker],
        attributes: [NSAttributedString.Key: Any],
        reviewCounts: [Int: Int],
        badgeColor: UIColor
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
                result.append(makeBubbleString(
                    marker: marker,
                    fallbackCount: reviewCounts[marker.paragraphIndex] ?? 0,
                    attributes: attributes,
                    badgeColor: badgeColor
                ))
            }
            index += 1
            cursor = index
        }
        if cursor < ns.length {
            result.append(NSAttributedString(string: ns.substring(from: cursor), attributes: attributes))
        }
        return result
    }

    /// 兼容模式的整章富文本：普通段落 + 末尾 💬 角标（无内嵌段评图的书源）。
    public static func buildLegacyReviewContent(
        text: String,
        attributes: [NSAttributedString.Key: Any],
        reviewCounts: [Int: Int]
    ) -> NSAttributedString {
        let paragraphs = text.components(separatedBy: "\n")
        let result = NSMutableAttributedString()
        for (index, paragraph) in paragraphs.enumerated() {
            result.append(NSAttributedString(string: paragraph, attributes: attributes))
            if index < paragraphs.count - 1 {
                var linkAttributes = attributes
                linkAttributes[.link] = reviewURL(for: index)
                // 链接文本颜色不烘焙（textColor 之外的颜色会参与 run 存储），
                // 由显示端 linkTextAttributes 供给，主题切换随 textColor 热刷新。
                let count = reviewCounts[index] ?? 0
                let title = count > 0 ? "  💬\(min(count, 999))" : reviewButtonText
                result.append(NSAttributedString(string: title, attributes: linkAttributes))
                result.append(NSAttributedString(string: "\n", attributes: attributes))
            }
        }
        return result
    }

    private static func makeBubbleString(
        marker: InlineReviewMarker,
        fallbackCount: Int,
        attributes: [NSAttributedString.Key: Any],
        badgeColor: UIColor
    ) -> NSAttributedString {
        let countText = marker.count.isEmpty
            ? (fallbackCount > 0 ? "\(min(fallbackCount, 999))" : "")
            : marker.count
        let pointSize = (attributes[.font] as? UIFont)?.pointSize ?? 17
        let image = ReviewBadgeRenderer.bubble(
            count: countText,
            pointSize: pointSize,
            color: badgeColor
        )
        let attachment = NSTextAttachment()
        attachment.image = image
        attachment.bounds = CGRect(
            x: 0,
            y: ((attributes[.font] as? UIFont)?.descender ?? -3) - max(2, image.size.height * 0.04),
            width: image.size.width,
            height: image.size.height
        )
        let bubble = NSMutableAttributedString(attachment: attachment)
        bubble.addAttribute(
            .link,
            value: markerURL(for: marker.id),
            range: NSRange(location: 0, length: bubble.length)
        )
        bubble.addAttribute(
            .accessibilityTextCustom,
            value: marker.title,
            range: NSRange(location: 0, length: bubble.length)
        )
        return bubble
    }

    public static func extractPlainText(from attributedText: NSAttributedString) -> String {
        let plain = NSMutableAttributedString(attributedString: attributedText)
        plain.removeAttribute(.link, range: NSRange(location: 0, length: plain.length))
        return plain.string
            .replacingOccurrences(of: "\\s*💬[0-9]*", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\u{FFFC}", with: "")
    }
}
