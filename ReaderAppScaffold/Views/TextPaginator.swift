import UIKit
import CoreText

/// 用 CoreText 的标准分页手法：反复用 `CTFramesetterCreateFrame` 在给定尺寸的矩形里
/// 排版，每次问它"这次实际排进去多少字"(`CTFrameGetVisibleStringRange`)，
/// 剩下的文字接着排下一页，直到排完。这是最贴近"真实渲染结果"的分页方式——
/// 不是按字数估算，是真的量出来的，字体、行距、页面尺寸变了重新跑一遍就行。
public enum TextPaginator {
    public static func paginate(
        text: String,
        font: UIFont,
        lineSpacing: CGFloat,
        paragraphSpacing: CGFloat = 0,
        firstLineIndent: CGFloat = 0,
        alignment: NSTextAlignment = .justified,
        pageSize: CGSize
    ) -> [String] {
        guard !text.isEmpty, pageSize.width > 1, pageSize.height > 1 else {
            return text.isEmpty ? [] : [text]
        }

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = lineSpacing
        paragraphStyle.paragraphSpacing = paragraphSpacing
        paragraphStyle.lineBreakMode = .byWordWrapping
        paragraphStyle.alignment = alignment
        paragraphStyle.firstLineHeadIndent = firstLineIndent

        let attributed = NSAttributedString(string: text, attributes: [
            .font: font,
            .paragraphStyle: paragraphStyle
        ])

        let framesetter = CTFramesetterCreateWithAttributedString(attributed as CFAttributedString)
        let path = CGPath(rect: CGRect(origin: .zero, size: pageSize), transform: nil)
        let fullLength = attributed.length

        var pages: [String] = []
        var location = 0
        let ns = text as NSString

        while location < fullLength {
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: location, length: 0), path, nil)
            let visibleRange = CTFrameGetVisibleStringRange(frame)

            // 极端情况（页面小到连一行都放不下）防止死循环：至少往前推进1个字符
            let length = max(visibleRange.length, 1)
            let safeLength = min(length, fullLength - location)
            let range = NSRange(location: location, length: safeLength)
            // 去除分页结果开头的换行符（避免下一页以空行开头）
            var pageText = ns.substring(with: range)
            if pageText.hasPrefix("\n") {
                pageText = String(pageText.dropFirst())
            }
            pages.append(pageText)
            location += safeLength
        }
        return pages
    }
}
