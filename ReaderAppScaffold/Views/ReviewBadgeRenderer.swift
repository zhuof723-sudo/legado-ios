import UIKit

/// 绘制与参考阅读器一致的行内段评数量气泡。
/// 气泡作为 NSTextAttachment 参与排版，背景、数量和点击区域属于同一个对象。
enum ReviewBadgeRenderer {
    private static let cache = NSCache<NSString, UIImage>()

    static func bubble(count: String, pointSize: CGFloat, color: UIColor) -> UIImage {
        let display = count.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "··" : count
        let key = "\(display)|\(Int(pointSize.rounded()))|\(color.description)" as NSString
        if let image = cache.object(forKey: key) { return image }

        let fontSize = max(8, pointSize * 0.60)
        let font = UIFont.systemFont(ofSize: fontSize, weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]
        let textSize = (display as NSString).size(withAttributes: attributes)
        let height = ceil(max(15, pointSize * 0.92))
        let horizontalPadding = max(4, pointSize * 0.28)
        let bubbleWidth = max(height, ceil(textSize.width) + horizontalPadding * 2)
        let leadingGap = ceil(pointSize * 0.22)
        let tailHeight = max(2, pointSize * 0.12)
        let canvas = CGSize(width: leadingGap + bubbleWidth, height: height + tailHeight)

        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = 3
        let image = UIGraphicsImageRenderer(size: canvas, format: format).image { _ in
            let scale = max(UIScreen.main.scale, 1)
            let lineWidth = 1 / scale
            let rect = CGRect(
                x: leadingGap + lineWidth / 2,
                y: lineWidth / 2,
                width: bubbleWidth - lineWidth,
                height: height - lineWidth
            )
            let path = UIBezierPath(roundedRect: rect, cornerRadius: rect.height * 0.4)
            let tailX = rect.minX + rect.width * 0.26
            let tail = UIBezierPath()
            tail.move(to: CGPoint(x: tailX, y: rect.maxY - 1))
            tail.addLine(to: CGPoint(x: tailX, y: rect.maxY + tailHeight))
            tail.addLine(to: CGPoint(x: tailX + tailHeight * 1.5, y: rect.maxY - 1))
            tail.close()
            path.append(tail)
            color.setStroke()
            path.lineWidth = lineWidth
            path.lineJoinStyle = .round
            path.stroke()

            let origin = CGPoint(
                x: rect.minX + (rect.width - textSize.width) / 2,
                y: rect.minY + (rect.height - textSize.height) / 2
            )
            (display as NSString).draw(at: origin, withAttributes: attributes)
        }
        cache.setObject(image, forKey: key)
        return image
    }
}
