import UIKit

// MARK: - 评论链接工具（用 NSLink 代替 NSTextAttachment，更可靠）

/// 段评相关的常量和工具方法。
/// 用 NSLink（URL 方案 "review://paragraph/{index}"）在段落末尾插入评论按钮，
/// UITextView 原生支持链接点击，比 NSTextAttachment 更可靠。
public enum ReviewLinkHelper {
    /// 评论链接的 URL scheme
    public static let scheme = "review"
    /// 评论链接的 host
    public static let host = "paragraph"

    /// 生成某段落的评论链接 URL
    public static func reviewURL(for paragraphIndex: Int) -> URL {
        URL(string: "\(scheme)://\(host)/\(paragraphIndex)")!
    }

    /// 判断是否是评论链接
    public static func isReviewURL(_ url: URL) -> Bool {
        url.scheme == scheme && url.host == host
    }

    /// 从评论链接中解析段落索引
    public static func paragraphIndex(from url: URL) -> Int? {
        guard isReviewURL(url) else { return nil }
        let components = url.pathComponents
        guard components.count >= 2, let index = Int(components[1]) else { return nil }
        return index
    }

    /// 评论按钮显示的文字（用表情符号，简单可靠）
    public static let reviewButtonText = " 💬"

    /// 将纯文本转换为带评论链接的 NSAttributedString。
    /// 在每段末尾（换行符前）插入评论链接，点击时触发 onReviewTap。
    /// - Parameters:
    ///   - text: 原始纯文本
    ///   - attributes: 文本的基础属性（字体、颜色、段落样式等）
    ///   - reviewCounts: 各段落的评论数（用于显示在评论按钮上）
    /// - Returns: 带评论链接的 NSAttributedString
    public static func attachReviewLinks(
        to text: String,
        attributes: [NSAttributedString.Key: Any],
        reviewCounts: [Int: Int] = [:]
    ) -> NSAttributedString {
        let paragraphs = text.components(separatedBy: "\n")
        let result = NSMutableAttributedString()

        for (index, paragraph) in paragraphs.enumerated() {
            // 添加段落文本
            result.append(NSAttributedString(string: paragraph, attributes: attributes))

            // 在段落末尾添加评论链接（最后一段不加）
            if index < paragraphs.count - 1 {
                let count = reviewCounts[index] ?? 0
                let buttonText = count > 0 ? " 💬\(count > 999 ? "999" : "\(count)")" : reviewButtonText

                var linkAttributes = attributes
                linkAttributes[.link] = reviewURL(for: index)
                linkAttributes[.foregroundColor] = UIColor.systemGray
                linkAttributes[.font] = UIFont.systemFont(ofSize: (attributes[.font] as? UIFont)?.pointSize ?? 14)

                result.append(NSAttributedString(string: buttonText, attributes: linkAttributes))
            }

            // 添加换行符（最后一段不加）
            if index < paragraphs.count - 1 {
                result.append(NSAttributedString(string: "\n", attributes: attributes))
            }
        }

        return result
    }

    /// 从带评论链接的 NSAttributedString 中提取纯文本（用于缓存等）
    public static func extractPlainText(from attributedText: NSAttributedString) -> String {
        let plain = NSMutableAttributedString(attributedString: attributedText)
        // 移除所有链接属性
        plain.removeAttribute(.link, range: NSRange(location: 0, length: plain.length))
        // 移除评论按钮文字（💬 及后面的数字）
        let result = plain.string.replacingOccurrences(of: " 💬[0-9]*", with: "", options: .regularExpression)
        return result
    }
}
