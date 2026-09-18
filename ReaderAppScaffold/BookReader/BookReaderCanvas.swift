import UIKit
import CoreText

final class BookReaderCanvas: UIView {
    private let page: BookReaderPage
    private let style: BookReaderStyle
    private let contentOffset: CGPoint
    private let contentSize: CGSize

    var onTurn: ((BookReaderTurnIntent) -> Void)?
    var onLink: ((BookReaderLink) -> Void)?

    init(page: BookReaderPage, style: BookReaderStyle, contentOffset: CGPoint, contentSize: CGSize) {
        self.page = page
        self.style = style
        self.contentOffset = contentOffset
        self.contentSize = contentSize
        super.init(frame: .zero)
        backgroundColor = UIColor(style.theme.background)
        isOpaque = true
        contentMode = .redraw
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
        tap.cancelsTouchesInView = false
        addGestureRecognizer(tap)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        // UIKit drawRect 是 y 向下；CoreText glyph drawing 需要 y 向上的文本空间。
        // 不做这一步，中文字会整体上下翻转，正是当前截图中的故障。
        context.saveGState()
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)

        let textColor = UIColor(style.theme.text).cgColor
        let markerColor = UIColor.systemGray.cgColor
        for line in page.lines {
            guard let runs = CTLineGetGlyphRuns(line.line) as? [CTRun] else { continue }
            for run in runs {
                let range = CTRunGetStringRange(run)
                guard range.length > 0 else { continue }
                let isMarker = line.attributed.attribute(.foregroundColor, at: range.location, effectiveRange: nil) != nil
                context.setFillColor(isMarker ? markerColor : textColor)
                let runX = CGFloat(CTLineGetOffsetForStringIndex(line.line, range.location, nil))
                let baselineFromBottom = bounds.height - contentOffset.y - line.baseline
                context.textPosition = CGPoint(
                    x: contentOffset.x + line.x + runX,
                    y: baselineFromBottom
                )
                CTRunDraw(run, context, CFRange(location: 0, length: 0))
            }
        }
        context.restoreGState()
    }

    func refreshTheme() {
        backgroundColor = UIColor(style.theme.background)
        setNeedsDisplay()
    }

    @objc private func tapped(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else { return }
        let point = gesture.location(in: self)
        let local = CGPoint(x: point.x - contentOffset.x, y: point.y - contentOffset.y)
        if local.x >= 0, local.x <= contentSize.width, local.y >= 0, local.y <= contentSize.height {
            for line in page.lines where local.y >= line.top && local.y < line.top + line.height {
                let index = CTLineGetStringIndexForPosition(line.line, CGPoint(x: local.x - line.x, y: 0))
                if index >= 0, index < line.attributed.length,
                   let url = line.attributed.attribute(.link, at: index, effectiveRange: nil) as? URL,
                   let link = BookReaderLink.resolve(url) {
                    onLink?(link)
                    return
                }
                break
            }
        }
        let edge = max(72, bounds.width * 0.24)
        if point.x <= edge { onTurn?(.previous) }
        else if point.x >= bounds.width - edge { onTurn?(.next) }
        else { onTurn?(.center) }
    }
}

enum BookReaderTurnIntent {
    case previous
    case next
    case center
}
