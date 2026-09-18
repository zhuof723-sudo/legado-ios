import UIKit
import LegadoRuleEngine

// MARK: - 链接目标

/// 正文里的可点对象。阅读引擎内唯一的“链接语义”层：
/// 段评气泡（正文内嵌 style:"TEXT" 段评图）与兼容模式的段落级入口。
enum ReaderLinkTarget: Equatable {
    case legacyParagraph(Int)
    case marker(Int)

    var url: URL {
        switch self {
        case .legacyParagraph(let i): return URL(string: "review://paragraph/\(i)")!
        case .marker(let id): return URL(string: "review://marker/\(id)")!
        }
    }

    static func from(url: URL) -> ReaderLinkTarget? {
        guard url.scheme == "review", let host = url.host else { return nil }
        let components = url.pathComponents
        guard components.count >= 2, let value = Int(components[1]) else { return nil }
        switch host {
        case "paragraph": return .legacyParagraph(value)
        case "marker": return .marker(value)
        default: return nil
        }
    }
}

// MARK: - 段落与章节文档

/// 一个排版段落。`attributed` 是“合成文本”：正文 run 只带字体（颜色由
/// 渲染端供给，主题切换零成本），段评角标 run 额外带颜色与链接。
/// `chapterRange` 指回整章纯文本的 UTF-16 范围（不含角标与换行符），
/// 供 TTS / 进度恢复使用。
struct ReaderParagraph {
    let attributed: NSAttributedString
    let chapterRange: NSRange
    /// 空段落：分页时按一个空行槽占位（保留原作的换行层次）。
    var isBlank: Bool { attributed.length == 0 }
}

/// 排版本的章节输入。一切“内容”都收敛到这个模型：
/// 本地 TXT/EPUB 是纯正文；在线书源正文可能带段评标记。
struct ReaderChapterDocument {
    let title: String
    /// 整章纯文本（含 PUA 段评占位符，不含合成角标）。
    let plainText: String
    let paragraphs: [ReaderParagraph]
    let fingerprint: String
}

enum ReaderDocumentBuilder {
    /// 正文指纹：O(1) 长度 + 首尾采样，作为分页缓存键的内容分量。
    static func fingerprint(of text: String) -> String {
        let head = text.prefix(32)
        let tail = text.suffix(32)
        return "\(text.count)-\(head)-\(tail)"
    }

    /// 把整章纯文本切成段落，并把段评标记替换为可点击的文本角标。
    ///
    /// 段落边界 = 换行符。换行符本身不进入任何段落（由段距呈现段落间隔），
    /// 空段落保留为空白行，忠实于原作的段落层次。
    static func build(
        title: String,
        content: String,
        markers: [InlineReviewMarker],
        legacyLinks: Bool,
        font: UIFont,
        badgeColor: UIColor
    ) -> ReaderChapterDocument {
        let ns = content as NSString
        var markerMap: [Int: InlineReviewMarker] = [:]
        markerMap.reserveCapacity(markers.count)
        for marker in markers where marker.id >= 0 && marker.id <= InlineReviewMarker.markerTokenLimit {
            // 正文格式化器保证 id 唯一；防御性保留第一个，重复 id 直接忽略。
            if markerMap[marker.id] == nil { markerMap[marker.id] = marker }
        }

        // 1. 按 \n 切段（保留空段）
        var ranges: [NSRange] = []
        var start = 0
        while start <= ns.length {
            var lineEnd = ns.length
            var next = ns.length
            var i = start
            while i < ns.length {
                if ns.character(at: i) == 0x0A { lineEnd = i; next = i + 1; break }
                i += 1
            }
            ranges.append(NSRange(location: start, length: lineEnd - start))
            if next >= ns.length { break }
            start = next
        }
        // 尾部空段不呈现（末尾换行不产生可见空行）
        if let last = ranges.last, last.length == 0, ranges.count > 1 {
            ranges.removeLast()
        }

        // 2. 逐段构建合成文本
        let baseAttributes: [NSAttributedString.Key: Any] = [.font: font]
        let badgeFont = UIFont.systemFont(ofSize: max(font.pointSize - 2, 10))
        var paragraphs: [ReaderParagraph] = []
        paragraphs.reserveCapacity(ranges.count)

        for (index, range) in ranges.enumerated() {
            let raw = ns.substring(with: range)
            let attributed = NSMutableAttributedString()

            if markerMap.isEmpty {
                attributed.append(NSAttributedString(string: raw, attributes: baseAttributes))
            } else {
                // 把正文里的 PUA 占位符（U+E000+id）替换为角标 run。
                let rawNS = raw as NSString
                var cursor = 0
                var position = 0
                while position < rawNS.length {
                    let scalar = rawNS.character(at: position)
                    guard (0xE000...0xF8FF).contains(scalar) else {
                        position += 1
                        continue
                    }
                    if position > cursor {
                        attributed.append(NSAttributedString(
                            string: rawNS.substring(with: NSRange(location: cursor, length: position - cursor)),
                            attributes: baseAttributes
                        ))
                    }
                    let markerID = Int(scalar) - 0xE000
                    if let marker = markerMap[markerID] {
                        attributed.append(markerBadge(marker: marker, font: badgeFont, color: badgeColor))
                    }
                    // 未知占位符：直接丢弃（不显示也不占排版位置）。
                    position += 1
                    cursor = position
                }
                if cursor < rawNS.length {
                    attributed.append(NSAttributedString(
                        string: rawNS.substring(from: cursor),
                        attributes: baseAttributes
                    ))
                }
            }

            // 兼容模式：每个有内容的段落末尾挂一个 💬 入口（最后一段除外，
            // 与旧 TextKit 管线一致，末段不挂）。
            if legacyLinks, !raw.isEmpty, index < ranges.count - 1 {
                var linkAttributes = baseAttributes
                linkAttributes[.font] = badgeFont
                linkAttributes[.foregroundColor] = badgeColor
                linkAttributes[.link] = ReaderLinkTarget.legacyParagraph(index).url
                attributed.append(NSAttributedString(string: "  💬", attributes: linkAttributes))
            }

            paragraphs.append(ReaderParagraph(
                attributed: attributed,
                chapterRange: range
            ))
        }

        return ReaderChapterDocument(
            title: title,
            plainText: content,
            paragraphs: paragraphs,
            fingerprint: fingerprint(of: content)
        )
    }

    private static func markerBadge(marker: InlineReviewMarker, font: UIFont, color: UIColor) -> NSAttributedString {
        let count = marker.count.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = count.isEmpty ? "💬" : "💬\(count)"
        return NSAttributedString(string: title, attributes: [
            .font: font,
            .foregroundColor: color,
            .link: ReaderLinkTarget.marker(marker.id).url
        ])
    }
}
