import Foundation

/// 本地 TXT 章节
struct LocalChapter: Codable {
    let title: String
    let content: String
}

/// TXT 章节切分：优先按"第X章/卷/节…"行切，切不出来就按空行分块，再不行整本一章
enum TxtParser {
    static func chapters(from text: String) -> [LocalChapter] {
        let cleaned = text.replacingOccurrences(of: "\r\n", with: "\n")
                             .replacingOccurrences(of: "\r", with: "\n")
        let lines = cleaned.components(separatedBy: "\n")

        let titleRegex = try! NSRegularExpression(
            pattern: "^[\\s　]{0,8}(第[0-9一二三四五六七八九十百千万零〇两]+[章节卷回部集篇][^\\n]{0,40})$"
        )

        var chapters: [LocalChapter] = []
        var currentTitle = "开始"
        var buffer: [String] = []

        func flush() {
            let content = buffer
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !content.isEmpty {
                chapters.append(LocalChapter(title: currentTitle, content: content))
            }
            buffer.removeAll()
        }

        for line in lines {
            let ns = line as NSString
            if titleRegex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) != nil {
                flush()
                currentTitle = line.trimmingCharacters(in: .whitespaces)
            } else {
                buffer.append(line)
            }
        }
        flush()

        if chapters.isEmpty {
            return [LocalChapter(title: "全文", content: cleaned.trimmingCharacters(in: .whitespacesAndNewlines))]
        }
        return chapters
    }

    static func encode(_ chapters: [LocalChapter]) -> String {
        guard let data = try? JSONEncoder().encode(chapters),
              let s = String(data: data, encoding: .utf8) else { return "[]" }
        return s
    }

    static func decode(_ data: String) -> [LocalChapter] {
        guard let d = data.data(using: .utf8),
              let list = try? JSONDecoder().decode([LocalChapter].self, from: d) else { return [] }
        return list
    }
}
