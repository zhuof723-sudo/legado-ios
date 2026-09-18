import UIKit
import CoreText

// MARK: - 排版参数

/// 排版参数快照：决定一次分页结果的全部输入。
/// 任何一项变化都必须产生不同的分页缓存键（由 `signature` 保证）。
struct ReaderTypography {
    let font: UIFont
    /// 单行槽高 = 字体行高 + 行距。行距按“槽内均匀上下分布”落位，见 baseline。
    let lineSlotHeight: CGFloat
    /// 段间距（仅在页面中部生效；页顶不落段距，避免页首悬挂空隙）。
    let paragraphGap: CGFloat
    /// 首行缩进（pt）。中文书籍惯例 = 2 个字符宽，由 ReaderConfig 换算。
    let firstLineIndent: CGFloat
    /// 文字区尺寸（屏幕尺寸减去阅读边距）。
    let pageSize: CGSize

    init(font: UIFont, lineSpacing: CGFloat, paragraphGap: CGFloat, firstLineIndent: CGFloat, pageSize: CGSize) {
        self.font = font
        self.lineSlotHeight = font.lineHeight + max(lineSpacing, 0)
        self.paragraphGap = max(paragraphGap, 0)
        self.firstLineIndent = max(firstLineIndent, 0)
        self.pageSize = pageSize
    }

    /// ReaderConfig 以 Double 存偏好设置，这里做一次收敛转换。
    init(font: UIFont, lineSpacing: Double, paragraphGap: Double, firstLineIndent: CGFloat, pageSize: CGSize) {
        self.init(
            font: font,
            lineSpacing: CGFloat(lineSpacing),
            paragraphGap: CGFloat(paragraphGap),
            firstLineIndent: firstLineIndent,
            pageSize: pageSize
        )
    }

    var signature: String {
        [
            font.fontName,
            "\(Int(font.pointSize))",
            "ls\(Int(lineSlotHeight))",
            "ps\(Int(paragraphGap))",
            "in\(Int(firstLineIndent))",
            "pg\(Int(pageSize.width))x\(Int(pageSize.height))"
        ].joined(separator: "|")
    }
}

// MARK: - 排好版的一行

/// 一行已经定好位的文字。`line` 由 CTTypesetter 产出（非段末行已两端对齐），
/// 行内 run 的字符区间相对于所在段落的合成文本。
struct PlacedLine {
    let line: CTLine
    /// 所属段落的合成文本（行内 run 查询颜色/链接用）。
    let paragraphAttributed: NSAttributedString
    /// 所属段落在文档 paragraphs 里的序号（页内章节范围计算用）。
    let paragraphIndex: Int
    /// 行起点 x（段首行 = firstLineIndent，其余 = 0）。
    let x: CGFloat
    /// 行槽顶 y（相对文字区左上）。
    let slotTop: CGFloat
    /// 基线 y（相对文字区左上）。
    let baselineY: CGFloat
    let slotHeight: CGFloat
}

// MARK: - 一页

/// 排版完成的一页。页码、页内文字范围都来自分页结果本身；
/// 渲染端只做纯绘制，不参与任何测量——量页与上屏天然同源。
struct ReaderPage: Equatable {
    let lines: [PlacedLine]
    /// 本页覆盖的整章纯文本 UTF-16 范围（进度恢复用）。
    let chapterRange: NSRange
    /// 本页纯文本（TTS 用，已剔除段评占位符与角标）。
    let plainText: String
    /// 分页批次标识（分页缓存键），用于低成本相等比较。
    let buildKey: String

    static func == (lhs: ReaderPage, rhs: ReaderPage) -> Bool {
        lhs.buildKey == rhs.buildKey
            && lhs.chapterRange.location == rhs.chapterRange.location
            && lhs.lines.count == rhs.lines.count
    }
}

// MARK: - 分页引擎

/// CoreText 分页引擎。
///
/// 中文断行：CTTypesetter 的行切分基于 Unicode UAX #14，对中文天然按字
/// 可断行，同时遵守禁则（行首不出现 、。，！？：；」』）等闭标点，行尾
/// 不出现 「『（ 等开标点）。
/// 两端对齐：非段末行经 CTLineCreateJustifiedLine 拉满整行宽度；
/// 段末行保持自然长度左对齐（书籍惯例）。
/// 首行缩进：每段第一行 x 起点 = firstLineIndent，对齐宽度同步收进。
enum ReaderPaginator {

    /// 把章节文档切成一页一页。纯函数，可在后台线程执行。
    static func paginate(
        document: ReaderChapterDocument,
        typography: ReaderTypography,
        buildKey: String
    ) -> [ReaderPage] {
        let width = typography.pageSize.width
        let pageHeight = typography.pageSize.height
        guard width > 8, pageHeight > 8,
              document.paragraphs.contains(where: { !$0.isBlank }) else { return [] }

        let chapterLength = (document.plainText as NSString).length
        var pages: [ReaderPage] = []
        var lines: [PlacedLine] = []
        var y: CGFloat = 0

        func flushPage() {
            guard !lines.isEmpty else { return }
            let location = document.paragraphs[lines[0].paragraphIndex].chapterRange.location
            let end = NSMaxRange(document.paragraphs[lines[lines.count - 1].paragraphIndex].chapterRange)
            let clampedEnd = min(end, chapterLength)
            let pageText: String
            if location <= clampedEnd {
                pageText = sanitized(
                    (document.plainText as NSString).substring(
                        with: NSRange(location: location, length: clampedEnd - location)
                    )
                )
            } else {
                pageText = ""
            }
            pages.append(ReaderPage(
                lines: lines,
                chapterRange: NSRange(location: min(location, clampedEnd), length: max(clampedEnd - location, 0)),
                plainText: pageText,
                buildKey: buildKey
            ))
            lines = []
            y = 0
        }

        for (paragraphIndex, paragraph) in document.paragraphs.enumerated() {
            if Task.isCancelled { return [] }

            // 段距：只落在页面中部；页顶不落（新页从段落首行直接开始）。
            if paragraphIndex > 0, !lines.isEmpty {
                y += typography.paragraphGap
            }

            if paragraph.isBlank {
                // 空段落 = 一个空行槽。页顶不留空行。
                if !lines.isEmpty {
                    y += typography.lineSlotHeight
                }
                continue
            }

            let attributed = paragraph.attributed
            let total = attributed.length
            let typesetter = CTTypesetterCreateWithAttributedString(attributed)

            var start = 0
            var isFirstLine = true
            while start < total {
                if Task.isCancelled { return [] }
                let availableWidth = max(width - (isFirstLine ? typography.firstLineIndent : 0), 10)
                var count = CTTypesetterSuggestLineBreak(typesetter, start, Double(availableWidth))
                if count <= 0 {
                    // 极端情况（比如宽度极小）：至少推进一个字符，杜绝死循环。
                    count = 1
                }

                var line = CTTypesetterCreateLine(typesetter, CFRange(location: start, length: count))
                let isParagraphLastLine = start + count >= total
                if !isParagraphLastLine,
                   let justified = CTLineCreateJustifiedLine(line, 0, Double(availableWidth)) {
                    line = justified
                }

                // 页满换页：整行不放进当前页，新开一页。
                if !lines.isEmpty, y + typography.lineSlotHeight > pageHeight + 0.5 {
                    flushPage()
                }

                // 槽内基线：字体行高在槽内垂直居中，行距上下均分。
                let baseline = y
                    + (typography.lineSlotHeight - typography.font.lineHeight) / 2
                    + typography.font.ascender

                lines.append(PlacedLine(
                    line: line,
                    paragraphAttributed: attributed,
                    paragraphIndex: paragraphIndex,
                    x: isFirstLine ? typography.firstLineIndent : 0,
                    slotTop: y,
                    baselineY: baseline,
                    slotHeight: typography.lineSlotHeight
                ))
                y += typography.lineSlotHeight
                start += count
                isFirstLine = false
            }
        }
        flushPage()
        return pages
    }

    /// TTS 文本净化：剔除段评占位符（PUA 区），避免朗读引擎碰到私有区字符。
    private static func sanitized(_ text: String) -> String {
        guard text.contains(where: { $0.unicodeScalars.contains { (0xE000...0xF8FF).contains($0.value) } }) else {
            return text
        }
        return String(text.filter {
            !$0.unicodeScalars.contains(where: { (0xE000...0xF8FF).contains($0.value) })
        })
    }
}

// MARK: - 分页缓存

/// 分页产物缓存：同一份内容 + 排版参数命中即返回，Aa 面板拖动滑杆
/// 反复横跳时零重排。LRU 上限 8 章，足够覆盖前后章缓存。
final class ReaderPageCache {
    static let shared = ReaderPageCache()

    private let capacity = 8
    private var storage: [String: [ReaderPage]] = [:]
    private var order: [String] = []
    private let lock = NSLock()

    private init() {}

    func pages(for key: String) -> [ReaderPage]? {
        lock.lock()
        defer { lock.unlock() }
        guard let pages = storage[key] else { return nil }
        // 访问即置顶
        if let position = order.firstIndex(of: key) {
            order.remove(at: position)
            order.append(key)
        }
        return pages
    }

    func store(_ pages: [ReaderPage], for key: String) {
        lock.lock()
        defer { lock.unlock() }
        storage[key] = pages
        if let position = order.firstIndex(of: key) {
            order.remove(at: position)
        }
        order.append(key)
        while order.count > capacity {
            let evicted = order.removeFirst()
            storage.removeValue(forKey: evicted)
        }
    }

    func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        storage.removeAll()
        order.removeAll()
    }
}
