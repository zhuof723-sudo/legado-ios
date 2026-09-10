import UIKit

/// 绘制阅读器里的段评数量徽标。
/// 目标样式是参考 App 的“猫头/云头”轮廓：上半部有两只小耳朵，
/// 主体是圆角胶囊，整体只描边不填充，数字居中。
/// 气泡作为 NSTextAttachment 参与排版，形状、数量和点击区域属于同一个对象。
enum ReviewBadgeRenderer {
    private static let cache = NSCache<NSString, UIImage>()

    static func bubble(count: String, pointSize: CGFloat, color: UIColor) -> UIImage {
        let finiteSize = pointSize.isFinite ? min(max(pointSize, 8), 64) : 17
        let rawDisplay = count.trimmingCharacters(in: .whitespacesAndNewlines)
        let display = rawDisplay.isEmpty ? "··" : String(rawDisplay.prefix(6))
        let key = "\(display)|\(Int(finiteSize.rounded()))|\(color)" as NSString
        if let image = cache.object(forKey: key) { return image }

        let fontSize = max(7, finiteSize * 0.54)
        let font = UIFont.systemFont(ofSize: fontSize, weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]
        let textSize = (display as NSString).size(withAttributes: attributes)
        let bodyHeight = ceil(max(14, finiteSize * 0.80))
        let horizontalPadding = max(7, finiteSize * 0.36)
        let bodyWidth = max(
            bodyHeight * 1.38,
            ceil(textSize.width) + horizontalPadding * 2
        )
        let earHeight = ceil(bodyHeight * 0.25)
        let canvas = CGSize(width: bodyWidth + 2, height: bodyHeight + earHeight + 2)

        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = 3
        let image = UIGraphicsImageRenderer(size: canvas, format: format).image { _ in
            let scale = max(UIScreen.main.scale, 1)
            let lineWidth = 1 / scale
            let bodyRect = CGRect(
                x: 1,
                y: earHeight + 1,
                width: bodyWidth,
                height: bodyHeight
            )
            let path = catHeadPath(bodyRect: bodyRect, lineWidth: lineWidth)
            path.lineWidth = lineWidth
            path.lineJoinStyle = .round
            path.lineCapStyle = .round
            color.setStroke()
            UIColor.clear.setFill()
            path.fill()
            path.stroke()

            let origin = CGPoint(
                x: bodyRect.midX - textSize.width / 2,
                y: bodyRect.midY - textSize.height / 2
            )
            (display as NSString).draw(at: origin, withAttributes: attributes)
        }
        cache.setObject(image, forKey: key)
        return image
    }

    /// 用一条闭合路径画出猫头轮廓，避免耳朵和主体之间出现内部描边。
    private static func catHeadPath(bodyRect: CGRect, lineWidth: CGFloat) -> UIBezierPath {
        let body = bodyRect.insetBy(dx: lineWidth / 2, dy: lineWidth / 2)
        let left = body.minX
        let right = body.maxX
        let top = body.minY
        let bottom = body.maxY
        let width = body.width
        let radius = min(body.height * 0.48, width * 0.5)
        let earHeight = min(body.height * 0.46, width * 0.20)

        let leftEarOuterX = left + width * 0.07
        let leftEarPeakX = left + width * 0.23
        let leftEarInnerX = left + width * 0.39
        let rightEarInnerX = right - width * 0.39
        let rightEarPeakX = right - width * 0.23
        let rightEarOuterX = right - width * 0.07

        let path = UIBezierPath()
        path.move(to: CGPoint(x: leftEarOuterX, y: top))
        path.addLine(to: CGPoint(x: leftEarPeakX, y: top - earHeight))
        path.addLine(to: CGPoint(x: leftEarInnerX, y: top))
        path.addLine(to: CGPoint(x: rightEarInnerX, y: top))
        path.addLine(to: CGPoint(x: rightEarPeakX, y: top - earHeight))
        path.addLine(to: CGPoint(x: rightEarOuterX, y: top))

        // 右上到右下：把正文主体的圆角连进同一条轮廓。
        path.addQuadCurve(
            to: CGPoint(x: right, y: top + radius),
            controlPoint: CGPoint(x: right, y: top)
        )
        path.addLine(to: CGPoint(x: right, y: bottom - radius))
        path.addQuadCurve(
            to: CGPoint(x: right - radius, y: bottom),
            controlPoint: CGPoint(x: right, y: bottom)
        )
        path.addLine(to: CGPoint(x: left + radius, y: bottom))
        path.addQuadCurve(
            to: CGPoint(x: left, y: bottom - radius),
            controlPoint: CGPoint(x: left, y: bottom)
        )
        path.addLine(to: CGPoint(x: left, y: top + radius))
        path.addQuadCurve(
            to: CGPoint(x: leftEarOuterX, y: top),
            controlPoint: CGPoint(x: left, y: top)
        )
        path.close()
        return path
    }
}
