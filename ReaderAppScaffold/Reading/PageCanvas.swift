import UIKit
import CoreText

// MARK: - 单页渲染（CoreText 直绘）

/// 一张书页。行数据全部来自分页引擎的 LayoutLine（测量与绘制同源，
/// 从根上消除“量页”和“上屏”排版不一致），本视图只做三件事：
/// 1. draw(_:) 里逐 run 绘制（正文 run 无颜色属性 → 用当前主题色；
///    段评角标 run 烘焙了中性灰 → 直接生效，主题切换无需重排）
/// 2. 点击分发：先链接命中检测（段评入口），再走点击分区
/// 3. 主题切换热刷新：setNeedsDisplay 只重绘不重排
final class PageCanvasView: UIView, UIGestureRecognizerDelegate {
    private let page: BookPage
    private let prefs: ReadingPreferences
    /// 文字区相对视图的偏移（阅读边距）。
    private let contentOffset: CGPoint
    private let contentSize: CGSize

    var onZoneTap: ((TapZoneAction) -> Void)?
    var onLinkTap: ((InlineLink) -> Void)?

    init(page: BookPage, prefs: ReadingPreferences, contentOffset: CGPoint, contentSize: CGSize) {
        self.page = page
        self.prefs = prefs
        self.contentOffset = contentOffset
        self.contentSize = contentSize
        super.init(frame: .zero)

        backgroundColor = UIColor(prefs.currentTheme.background)
        isOpaque = true
        contentMode = .redraw

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tap.cancelsTouchesInView = false
        addGestureRecognizer(tap)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - 绘制

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.textMatrix = .identity

        let bodyColor = UIColor(prefs.currentTheme.textColor).cgColor
        let badgeColor = UIColor.systemGray.cgColor

        for placed in page.lines {
            guard let runs = CTLineGetGlyphRuns(placed.line) as? [CTRun] else { continue }
            for run in runs {
                let runRange = CTRunGetStringRange(run)
                guard runRange.length > 0 else { continue }

                // 段评角标 run 带烘焙前景色（主题无关的中性灰）；正文 run 用主题色。
                let isBadge = placed.paragraphAttributed
                    .attribute(.foregroundColor, at: runRange.location, effectiveRange: nil) != nil
                context.setFillColor(isBadge ? badgeColor : bodyColor)

                // run 在行内的起点：CTLineGetOffsetForStringIndex 给出排版位移，
                // 首行缩进与两端对齐都已反映在位移里。
                let runX = CGFloat(CTLineGetOffsetForStringIndex(placed.line, runRange.location, nil))
                context.textPosition = CGPoint(
                    x: contentOffset.x + placed.x + runX,
                    y: contentOffset.y + placed.baselineY
                )
                CTRunDraw(run, context, CFRange(location: 0, length: 0))
            }
        }
    }

    // MARK: - 主题热刷新

    /// 主题/夜间切换：背景 + 文字颜色重绘，不触碰分页产物。
    func refreshAppearance() {
        backgroundColor = UIColor(prefs.currentTheme.background)
        setNeedsDisplay()
    }

    // MARK: - 点击分发

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else { return }
        let point = gesture.location(in: self)
        if let target = linkTarget(at: point) {
            onLinkTap?(target)
            return
        }
        onZoneTap?(TapZones.classify(x: point.x, width: bounds.width))
    }

    /// 命中检测：先按行槽找行，再用 CTLineGetStringIndexForPosition 反查字符，
    /// 最后查合成文本的 .link 属性。
    private func linkTarget(at point: CGPoint) -> InlineLink? {
        let local = CGPoint(x: point.x - contentOffset.x, y: point.y - contentOffset.y)
        guard local.x >= 0, local.x <= contentSize.width,
              local.y >= 0, local.y <= contentSize.height else { return nil }

        for placed in page.lines {
            guard local.y >= placed.slotTop, local.y < placed.slotTop + placed.slotHeight else { continue }
            let index = CTLineGetStringIndexForPosition(
                placed.line,
                CGPoint(x: local.x - placed.x, y: 0)
            )
            guard index >= 0, index < placed.paragraphAttributed.length,
                  let url = placed.paragraphAttributed.attribute(
                    .link,
                    at: index,
                    effectiveRange: nil
                  ) as? URL else { return nil }
            return InlineLink.from(url: url)
        }
        return nil
    }
}
