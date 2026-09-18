import UIKit
import CoreText

struct ReaderPageLayout {
    let font: UIFont
    let lineHeight: CGFloat
    let paragraphSpacing: CGFloat
    let firstLineIndent: CGFloat
    let pageSize: CGSize

    init(font: UIFont, lineSpacing: Double, paragraphSpacing: Double, firstLineIndent: CGFloat, pageSize: CGSize) {
        self.font = font
        self.lineHeight = font.lineHeight + CGFloat(max(lineSpacing, 0))
        self.paragraphSpacing = CGFloat(max(paragraphSpacing, 0))
        self.firstLineIndent = max(firstLineIndent, 0)
        self.pageSize = pageSize
    }

    var signature: String {
        "\(font.fontName)|\(font.pointSize)|\(lineHeight)|\(paragraphSpacing)|\(firstLineIndent)|\(pageSize.width)x\(pageSize.height)"
    }
}

struct ReaderPageLine {
    let line: CTLine
    let attributed: NSAttributedString
    let paragraphIndex: Int
    let x: CGFloat
    let top: CGFloat
    let baseline: CGFloat
    let height: CGFloat
}

struct ReaderBookPage: Equatable {
    let lines: [ReaderPageLine]
    let sourceRange: NSRange
    let speechText: String
    let key: String

    static func == (lhs: ReaderBookPage, rhs: ReaderBookPage) -> Bool {
        lhs.key == rhs.key && lhs.sourceRange.location == rhs.sourceRange.location && lhs.lines.count == rhs.lines.count
    }
}

final class ReaderPageCache {
    static let shared = ReaderPageCache()
    private let lock = NSLock()
    private let capacity = 8
    private var values: [String: [ReaderBookPage]] = [:]
    private var order: [String] = []

    func get(_ key: String) -> [ReaderBookPage]? {
        lock.lock(); defer { lock.unlock() }
        guard let result = values[key] else { return nil }
        order.removeAll { $0 == key }
        order.append(key)
        return result
    }

    func put(_ pages: [ReaderBookPage], key: String) {
        lock.lock(); defer { lock.unlock() }
        values[key] = pages
        order.removeAll { $0 == key }
        order.append(key)
        while order.count > capacity {
            values.removeValue(forKey: order.removeFirst())
        }
    }
}

enum ReaderPagePagination {
    static func paginate(document: ReaderPageDocument, layout: ReaderPageLayout, key: String) -> [ReaderBookPage] {
        guard layout.pageSize.width > 8, layout.pageSize.height > 8,
              document.paragraphs.contains(where: { !$0.isBlank }) else { return [] }

        let sourceLength = (document.sourceText as NSString).length
        var pages: [ReaderBookPage] = []
        var currentLines: [ReaderPageLine] = []
        var y: CGFloat = 0

        func flush() {
            guard !currentLines.isEmpty else { return }
            let firstParagraph = document.paragraphs[currentLines[0].paragraphIndex]
            let lastParagraph = document.paragraphs[currentLines[currentLines.count - 1].paragraphIndex]
            let start = firstParagraph.sourceRange.location
            let end = min(NSMaxRange(lastParagraph.sourceRange), sourceLength)
            let range = NSRange(location: min(start, end), length: max(end - start, 0))
            let text = (document.sourceText as NSString).substring(with: range)
            let cleanText = String(text.filter { !$0.unicodeScalars.contains { (0xE000...0xF8FF).contains($0.value) } })
            pages.append(ReaderBookPage(lines: currentLines, sourceRange: range, speechText: cleanText, key: key))
            currentLines.removeAll(keepingCapacity: true)
            y = 0
        }

        for (paragraphIndex, paragraph) in document.paragraphs.enumerated() {
            if Task.isCancelled { return [] }
            if paragraphIndex > 0, !currentLines.isEmpty { y += layout.paragraphSpacing }
            if paragraph.isBlank {
                if !currentLines.isEmpty { y += layout.lineHeight }
                continue
            }

            let typesetter = CTTypesetterCreateWithAttributedString(paragraph.attributed)
            var position = 0
            var first = true
            while position < paragraph.attributed.length {
                let available = max(layout.pageSize.width - (first ? layout.firstLineIndent : 0), 10)
                var count = CTTypesetterSuggestLineBreak(typesetter, position, Double(available))
                if count <= 0 { count = 1 }
                var line = CTTypesetterCreateLine(typesetter, CFRange(location: position, length: count))
                let last = position + count >= paragraph.attributed.length
                if !last, let justified = CTLineCreateJustifiedLine(line, 0, Double(available)) { line = justified }

                if !currentLines.isEmpty, y + layout.lineHeight > layout.pageSize.height + 0.5 { flush() }
                let baseline = y + (layout.lineHeight - layout.font.lineHeight) / 2 + layout.font.ascender
                currentLines.append(ReaderPageLine(
                    line: line,
                    attributed: paragraph.attributed,
                    paragraphIndex: paragraphIndex,
                    x: first ? layout.firstLineIndent : 0,
                    top: y,
                    baseline: baseline,
                    height: layout.lineHeight
                ))
                y += layout.lineHeight
                position += count
                first = false
            }
        }
        flush()
        return pages
    }
}
