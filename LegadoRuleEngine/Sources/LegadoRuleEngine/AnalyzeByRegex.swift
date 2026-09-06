import Foundation

/// 对应 legado: model/analyzeRule/AnalyzeByRegex.kt
/// 正则表达式规则解析（书源里 ":" 开头的 AllInOne 正则规则用这个）。
/// regs 是多级正则（用 "&&" 分隔的每一级），逐级用上一级所有匹配拼接的文本喂给下一级正则。
public enum AnalyzeByRegex {

    /// 取一个结果：返回最后一级正则里"第一个匹配"的所有分组（0=整体匹配,1..n=各分组）
    public static func getElement(_ res: String, _ regs: [String], index: Int = 0) -> [String]? {
        guard index < regs.count,
              let regex = try? NSRegularExpression(pattern: regs[index]) else { return nil }
        let ns = res as NSString
        let full = NSRange(location: 0, length: ns.length)
        let allMatches = regex.matches(in: res, range: full)
        guard let first = allMatches.first else { return nil }

        if index + 1 == regs.count {
            var info: [String] = []
            for g in 0..<first.numberOfRanges {
                let r = first.range(at: g)
                info.append(r.location == NSNotFound ? "" : ns.substring(with: r))
            }
            return info
        } else {
            var result = ""
            for m in allMatches {
                result += ns.substring(with: m.range)
            }
            return getElement(result, regs, index: index + 1)
        }
    }

    /// 取列表：最后一级正则里"每一个匹配"各自的分组列表
    public static func getElements(_ res: String, _ regs: [String], index: Int = 0) -> [[String]] {
        guard index < regs.count,
              let regex = try? NSRegularExpression(pattern: regs[index]) else { return [] }
        let ns = res as NSString
        let full = NSRange(location: 0, length: ns.length)
        let allMatches = regex.matches(in: res, range: full)
        if allMatches.isEmpty { return [] }

        if index + 1 == regs.count {
            var books: [[String]] = []
            for m in allMatches {
                var info: [String] = []
                for g in 0..<m.numberOfRanges {
                    let r = m.range(at: g)
                    info.append(r.location == NSNotFound ? "" : ns.substring(with: r))
                }
                books.append(info)
            }
            return books
        } else {
            var result = ""
            for m in allMatches {
                result += ns.substring(with: m.range)
            }
            return getElements(result, regs, index: index + 1)
        }
    }
}
