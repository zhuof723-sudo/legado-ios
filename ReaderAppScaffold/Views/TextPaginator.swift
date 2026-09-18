import UIKit
import LegadoRuleEngine

/// 排版完成的一页。分页与显示共用同一份 NSAttributedString——
/// 量页和渲染走同一条 TextKit1 管线，段评气泡的宽度在分页时就已参与测量，
/// 显示端原样上屏不再二次拼装，从根上消除“分页量宽”与“渲染量宽”
/// 不一致导致的字体错位。
struct ReaderPage: Equatable {
    /// 本页显示内容（含段评气泡 attachment、链接与颜色）。
    let attributed: NSAttributedString
    /// TTS / 纯文本场景使用（剥掉气泡与 💬 角标）。
    let plainText: String
    /// 分页批次标识（即 paginationKey），用于低成本相等比较。
    let buildKey: String
    /// 页首第一个有效字符在整章中的 UTF-16 偏移。
    let startOffset: Int

    init(attributed: NSAttributedString, plainText: String, buildKey: String, startOffset: Int) {
        self.attributed = attributed
        self.plainText = plainText
        self.buildKey = buildKey
        self.startOffset = startOffset
    }

    static func == (lhs: ReaderPage, rhs: ReaderPage) -> Bool {
        lhs.buildKey == rhs.buildKey && lhs.startOffset == rhs.startOffset && lhs.plainText == rhs.plainText
    }
}

/// 章节分页器：构建整章显示用的富文本（含段评入口），再用 TextKit1 切页。
enum ReaderPageComposer {
    static func compose(
        content: String,
        markers: [InlineReviewMarker],
        legacyReviewLinks: Bool,
        reviewCounts: [Int: Int],
        font: UIFont,
        badgeColor: UIColor,
        lineSpacing: CGFloat,
        paragraphSpacing: CGFloat,
        firstLineIndent: CGFloat,
        alignment: NSTextAlignment,
        pageSize: CGSize,
        buildKey: String
    ) -> [ReaderPage]? {
        guard !content.isEmpty, pageSize.width > 1, pageSize.height > 1 else { return [] }

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = lineSpacing
        paragraphStyle.paragraphSpacing = paragraphSpacing
        paragraphStyle.lineBreakMode = .byWordWrapping
        paragraphStyle.alignment = alignment
        paragraphStyle.firstLineHeadIndent = firstLineIndent

        // 关键：正文 run 不携带 foregroundColor——颜色不参与排版度量，
        // 由显示端 textView.textColor 供给。这样主题/夜间切换只需改
        // textColor（纯重绘，不重新布局），分页产物完全复用。
        // 段评链接文本的颜色（systemGray）保留在 run 上，因为它语义上
        // 就是链接的装饰色。
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraphStyle
        ]

        // 段评入口在分页前就构建好：气泡宽度、💬 角标都会真实参与排版测量。
        let full: NSAttributedString
        if !markers.isEmpty {
            full = ReviewLinkHelper.buildInlineReviewContent(
                text: content,
                markers: markers,
                attributes: attributes,
                reviewCounts: reviewCounts,
                badgeColor: badgeColor
            )
        } else if legacyReviewLinks {
            full = ReviewLinkHelper.buildLegacyReviewContent(
                text: content,
                attributes: attributes,
                reviewCounts: reviewCounts
            )
        } else {
            full = NSAttributedString(string: content, attributes: attributes)
        }

        return paginate(full: full, pageSize: pageSize, buildKey: buildKey)
    }

    /// TextKit1 分页。PageContentView / FreeScrollReader 里的 UITextView 都被
    /// 强制成 TextKit1（访问 layoutManager），这里用同一个 NSLayoutManager 量页，
    /// 字体、行距、段距、气泡宽度全部与最终渲染一致。
    private static func paginate(full: NSAttributedString, pageSize: CGSize, buildKey: String) -> [ReaderPage]? {
        let storage = NSTextStorage(attributedString: full)
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)

        func makeContainer() -> NSTextContainer {
            let container = NSTextContainer(size: pageSize)
            container.lineFragmentPadding = 0
            container.lineBreakMode = .byWordWrapping
            return container
        }

        layoutManager.addTextContainer(makeContainer())
        let pageRect = CGRect(origin: .zero, size: pageSize)
        let nsText = full.string as NSString
        var location = 0
        var pages: [ReaderPage] = []

        while location < storage.length {
            if Task.isCancelled { return nil }

            let container = layoutManager.textContainers.last!
            var glyphRange = layoutManager.glyphRange(forBoundingRect: pageRect, in: container)

            // glyphRange(forBoundingRect:) 按“相交”取值：页面底部只露出半行的
            // 也要裁掉，否则这半行会同时出现在两页，显示端再排一次时被顶出页面。
            while glyphRange.length > 0 {
                var lineGlyphs = NSRange()
                let lineRect = layoutManager.lineFragmentRect(
                    forGlyphAt: NSMaxRange(glyphRange) - 1,
                    effectiveRange: &lineGlyphs,
                    withoutAdditionalLayout: true
                )
                if lineRect.maxY <= pageSize.height + 0.5 { break }
                let overflow = NSMaxRange(glyphRange) - lineGlyphs.location
                if overflow <= 0 || overflow > glyphRange.length { break }
                glyphRange.length -= overflow
            }

            var charRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
            if charRange.length <= 0 || NSMaxRange(charRange) <= location {
                // 极端情况（页面小到一行都放不下）：至少推进 1 个字符防死循环。
                charRange = NSRange(location: location, length: 1)
            }

            let end = NSMaxRange(charRange)
            var start = charRange.location
            // 页首不留空行（与旧 CoreText 分页行为一致）
            while start < end,
                  nsText.character(at: start) == 0x0A || nsText.character(at: start) == 0x0D {
                start += 1
            }

            if start < end {
                let pageContent = full.attributedSubstring(from: NSRange(location: start, length: end - start))
                pages.append(ReaderPage(
                    attributed: pageContent,
                    plainText: ReviewLinkHelper.extractPlainText(from: pageContent),
                    buildKey: buildKey,
                    startOffset: start
                ))
            }

            location = end
            if location < storage.length {
                layoutManager.addTextContainer(makeContainer())
            }
        }
        return pages
    }
}
