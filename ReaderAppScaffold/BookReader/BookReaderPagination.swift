import UIKit
import CoreText

struct BookReaderLayout {
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

struct BookReaderLine {
    let line: CTLine
    let attributed: NSAttributedString
    let paragraphIndex: Int
    let x: CGFloat
    let top: CGFloat
    let baseline: CGFloat
    let height: CGFloat
}

struct BookReaderPage: Equatable {
    let lines: [BookReaderLine]
    let sourceRange: NSRange
    let spokenText: String
    let key: String

    static func == (lhs: BookReaderPage, rhs: BookReaderPage) -> Bool {
        lhs.key == rhs.key && lhs.sourceRange.location == rhs.sourceRange.location && lhs.lines.count == rhs.lines.count
    }
}

final class BookReaderPageCache {
    static let shared = BookReaderPageCache()
    private let lock = NSLock()
    private let capacity = 8
    private var storage: [String: [BookReaderPage]] = [:]
    private var order: [String] = []

    func get(_ key: String) -> [BookReaderPage]? {
        lock.lock(); defer { lock.unlock() }
        guard let value = storage[key] else { return nil }
        order.removeAll { $0 == key }
        order.append(key)
        return value
    }

    func put(_ value: [BookReaderPage], key: String) {
        lock.lock(); defer { lock.unlock() }
        storage[key] = value
        order.removeAll { $0 == key }
        order.append(key)
        while order.count > capacity { storage.removeValue(forKey: order.removeFirst()) }
    }
}

enum BookReaderPagination {
    static func makePages(document: BookReaderDocument, layout: BookReaderLayout, key: String) -> [BookReaderPage] {
        guard layout.pageSize.width > 8, layout.pageSize.height > 8,
              document.paragraphs.contains(where: { !$0.isBlank }) else { return [] }

        let sourceLength = (document.sourceText as NSString).length
        var pages: [BookReaderPage] = []
        var current: [BookReaderLine] = []
        var y: CGFloat = 0

        func flush() {
            guard !current.isEmpty else { return }
            let start = document.paragraphs[current[0].paragraphIndex].sourceRange.location
            let end = min(NSMaxRange(document.paragraphs[current[current.count - 1].paragraphIndex].sourceRange), sourceLength)
            let range = NSRange(location: min(start, end), length: max(end - start, 0))
            let raw = (document.sourceText as NSString).substring(with: range)
            let spoken = String(raw.filter { !$0.unicodeScalars.contains { (0xE000...0xF8FF).contains($0.value) } })
            pages.append(BookReaderPage(lines: current, sourceRange: range, spokenText: spoken, key: key))
            current.removeAll(keepingCapacity: true)
            y = 0
        }

        for (paragraphIndex, paragraph) in document.paragraphs.enumerated() {
            if Task.isCancelled { return [] }
            if paragraphIndex > 0, !current.isEmpty { y += layout.paragraphSpacing }
            if paragraph.isBlank {
                if !current.isEmpty { y += layout.lineHeight }
                continue
            }

            let typesetter = CTTypesetterCreateWithAttributedString(paragraph.attributed)
            var position = 0
            var firstLine = true
            while position < paragraph.attributed.length {
                let available = max(layout.pageSize.width - (firstLine ? layout.firstLineIndent : 0), 10)
                var count = CTTypesetterSuggestLineBreak(typesetter, position, Double(available))
                if count <= 0 { count = 1 }
                var line = CTTypesetterCreateLine(typesetter, CFRange(location: position, length: count))
                let lastLine = position + count >= paragraph.attributed.length
                if !lastLine, let justified = CTLineCreateJustifiedLine(line, 0, Double(available)) { line = justified }

                if !current.isEmpty, y + layout.lineHeight > layout.pageSize.height + 0.5 { flush() }
                let baseline = y + (layout.lineHeight - layout.font.lineHeight) / 2 + layout.font.ascender
                current.append(BookReaderLine(
                    line: line,
                    attributed: paragraph.attributed,
                    paragraphIndex: paragraphIndex,
                    x: firstLine ? layout.firstLineIndent : 0,
                    top: y,
                    baseline: baseline,
                    height: layout.lineHeight
                ))
                y += layout.lineHeight
                position += count
                firstLine = false
            }
        }
        flush()
        return pages
    }
}
