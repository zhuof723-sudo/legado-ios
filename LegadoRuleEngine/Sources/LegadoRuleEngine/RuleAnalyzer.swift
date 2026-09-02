import Foundation

/// 对应 legado: model/analyzeRule/RuleAnalyzer.kt
/// 通用的规则切分处理。逐字符扫描书源规则字符串（如 css/xpath/jsonPath 规则），
/// 按 "&&" "||" "%%" 等组合符切分，同时正确跳过 [...] 和 (...) 筛选器内部的组合符，
/// 并支持 {...} 内嵌规则替换（如 jsonPath 里的 {$.xxx}）。
///
/// 说明：Kotlin 原版用 String 做随机访问（O(1)），Swift String 不是随机访问容器，
/// 这里内部转成 [Character] 数组以保持同样的访问方式与性能特征。
public final class RuleAnalyzer {

    /// 规则解析错误（对应 Kotlin 里的 throw Error(...)）
    public struct RuleAnalyzerError: Error, CustomStringConvertible {
        public let message: String
        public var description: String { message }
    }

    private let queue: [Character]      // 被处理字符串
    private var pos = 0                 // 当前处理到的位置
    private var start = 0                // 当前处理字段的开始
    private var startX = 0               // 当前规则的开始

    private var rule: [String] = []      // 分割出的规则列表
    private var step: Int = 0            // 分割字符的长度
    public private(set) var elementsType = ""   // 当前分割字串

    private let isCode: Bool             // json/js 场景用代码平衡组，否则用规则平衡组

    private static let ESC: Character = "\\"

    public init(_ data: String, code: Bool = false) {
        self.queue = Array(data)
        self.isCode = code
    }

    // MARK: - 基础工具

    private func sub(_ from: Int, _ to: Int) -> String {
        guard from <= to, from >= 0, to <= queue.count else { return "" }
        return String(queue[from..<to])
    }

    private func sub(_ from: Int) -> String {
        guard from >= 0, from <= queue.count else { return "" }
        return String(queue[from...])
    }

    private func isTrimmable(_ c: Character) -> Bool {
        if c == "@" { return true }
        guard c.unicodeScalars.count == 1, let scalar = c.unicodeScalars.first else { return false }
        return scalar.value < 33
    }

    /// 修剪当前规则之前的"@"或者空白符
    public func trim() {
        guard pos < queue.count else { return }
        if isTrimmable(queue[pos]) {
            pos += 1
            while pos < queue.count, isTrimmable(queue[pos]) { pos += 1 }
            start = pos
            startX = pos
        }
    }

    /// 将pos重置为0，方便复用
    public func reSetPos() {
        pos = 0
        startX = 0
    }

    /// 从剩余字串中拉出一个字符串，直到但不包括匹配序列 seq（区分大小写）
    @discardableResult
    private func consumeTo(_ seq: String) -> Bool {
        start = pos
        if let offset = indexOf(seq, from: pos) {
            pos = offset
            return true
        }
        return false
    }

    private func indexOf(_ seq: String, from: Int) -> Int? {
        let seqArr = Array(seq)
        if seqArr.isEmpty { return from }
        if from > queue.count - seqArr.count { return nil }
        var i = from
        while i <= queue.count - seqArr.count {
            var matched = true
            for j in 0..<seqArr.count where queue[i + j] != seqArr[j] {
                matched = false
                break
            }
            if matched { return i }
            i += 1
        }
        return nil
    }

    /// 从剩余字串中拉出一个字符串，直到但不包括匹配序列（匹配参数列表中一项即为匹配），或剩余字串用完
    private func consumeToAny(_ seqs: [String]) -> Bool {
        let seqArrs = seqs.map { Array($0) }
        var p = pos
        while p != queue.count {
            for s in seqArrs where regionMatches(p, s) {
                step = s.count
                pos = p
                return true
            }
            p += 1
        }
        return false
    }

    private func regionMatches(_ p: Int, _ s: [Character]) -> Bool {
        if p + s.count > queue.count { return false }
        for j in 0..<s.count where queue[p + j] != s[j] { return false }
        return true
    }

    /// 从剩余字串中找到匹配字符集合中任意一个字符的位置
    private func findToAny(_ chars: [Character]) -> Int {
        var p = pos
        while p != queue.count {
            for s in chars where queue[p] == s { return p }
            p += 1
        }
        return -1
    }

    /// 拉出一个非内嵌代码平衡组，存在转义文本（用于 {} 内嵌 js/jsonPath 规则）
    private func chompCodeBalanced(_ open: Character, _ close: Character) -> Bool {
        var p = pos
        var depth = 0
        var otherDepth = 0
        var inSingleQuote = false
        var inDoubleQuote = false

        repeat {
            if p == queue.count { break }
            let c = queue[p]
            p += 1
            if c != RuleAnalyzer.ESC {
                if c == "'" && !inDoubleQuote { inSingleQuote.toggle() }
                else if c == "\"" && !inSingleQuote { inDoubleQuote.toggle() }

                if inSingleQuote || inDoubleQuote { continue }

                if c == "[" { depth += 1 }
                else if c == "]" { depth -= 1 }
                else if depth == 0 {
                    if c == open { otherDepth += 1 }
                    else if c == close { otherDepth -= 1 }
                }
            } else {
                p += 1
            }
        } while depth > 0 || otherDepth > 0

        if depth > 0 || otherDepth > 0 { return false }
        pos = p
        return true
    }

    /// 拉出一个规则平衡组（css/xpath 筛选器 [...] 或 (...)），引号内转义字符无效
    private func chompRuleBalanced(_ open: Character, _ close: Character) -> Bool {
        var p = pos
        var depth = 0
        var inSingleQuote = false
        var inDoubleQuote = false

        repeat {
            if p == queue.count { break }
            let c = queue[p]
            p += 1
            if c == "'" && !inDoubleQuote { inSingleQuote.toggle() }
            else if c == "\"" && !inSingleQuote { inDoubleQuote.toggle() }

            if inSingleQuote || inDoubleQuote { continue }
            else if c == "\\" {
                p += 1
                continue
            }

            if c == open { depth += 1 }
            else if c == close { depth -= 1 }
        } while depth > 0

        if depth > 0 { return false }
        pos = p
        return true
    }

    private func chompBalanced(_ open: Character, _ close: Character) -> Bool {
        isCode ? chompCodeBalanced(open, close) : chompRuleBalanced(open, close)
    }

    // MARK: - splitRule 核心切分算法

    /// 不用正则，不到最后不切片也不用中间变量存储，只在序列中标记当前查找字段的开头结尾，
    /// 到返回时才切片，高效准确切割规则。
    /// 解决 jsonPath 自带的 "&&" "||" 与阅读的规则冲突，以及规则正则或字符串中
    /// 包含 "&&"、"||"、"%%"、"@" 导致的冲突。
    @discardableResult
    public func splitRule(_ split: String...) throws -> [String] {
        try splitRuleEntry(split)
    }

    @discardableResult
    public func splitRule(_ split: [String]) throws -> [String] {
        try splitRuleEntry(split)
    }

    private func splitRuleEntry(_ split: [String]) throws -> [String] {
        if split.count == 1 {
            elementsType = split[0]
            if !consumeTo(elementsType) {
                rule.append(sub(startX))
                return rule
            } else {
                step = elementsType.count
                return try splitRuleContinue()
            }
        } else if !consumeToAny(split) {
            rule.append(sub(startX))
            return rule
        }

        let end = pos
        pos = start

        while true {
            let st = findToAny(["[", "("])

            if st == -1 {
                rule = [sub(startX, end)]
                elementsType = sub(end, end + step)
                pos = end + step
                while consumeTo(elementsType) {
                    rule.append(sub(start, pos))
                    pos += step
                }
                rule.append(sub(pos))
                return rule
            }

            if st > end {
                rule = [sub(startX, end)]
                elementsType = sub(end, end + step)
                pos = end + step
                while consumeTo(elementsType) && pos < st {
                    rule.append(sub(start, pos))
                    pos += step
                }
                if pos > st {
                    startX = start
                    return try splitRuleContinue()
                } else {
                    rule.append(sub(pos))
                    return rule
                }
            }

            pos = st
            let nextChar: Character = (queue[pos] == "[") ? "]" : ")"
            if !chompBalanced(queue[pos], nextChar) {
                throw RuleAnalyzerError(message: sub(0, start) + "后未平衡")
            }

            if !(end > pos) { break }
        }

        start = pos
        return try splitRuleEntry(split)
    }

    /// 二段匹配：elementsType 已在首段确定，直接按 elementsType 查找
    private func splitRuleContinue() throws -> [String] {
        let end = pos
        pos = start

        while true {
            let st = findToAny(["[", "("])

            if st == -1 {
                rule.append(sub(startX, end))
                pos = end + step
                while consumeTo(elementsType) {
                    rule.append(sub(start, pos))
                    pos += step
                }
                rule.append(sub(pos))
                return rule
            }

            if st > end {
                rule.append(sub(startX, end))
                pos = end + step
                while consumeTo(elementsType) && pos < st {
                    rule.append(sub(start, pos))
                    pos += step
                }
                if pos > st {
                    startX = start
                    return try splitRuleContinue()
                } else {
                    rule.append(sub(pos))
                    return rule
                }
            }

            pos = st
            let nextChar: Character = (queue[pos] == "[") ? "]" : ")"
            if !chompBalanced(queue[pos], nextChar) {
                throw RuleAnalyzerError(message: sub(0, start) + "后未平衡")
            }

            if !(end > pos) { break }
        }

        start = pos
        if !consumeTo(elementsType) {
            rule.append(sub(startX))
            return rule
        }
        return try splitRuleContinue()
    }

    // MARK: - 内嵌规则替换

    /// 替换内嵌规则，如 {$.rule...} 形式（jsonPath / js 用）
    /// - Parameters:
    ///   - inner: 起始标志，如 "{$."
    ///   - startStep: 不属于规则部分的前置字符长度
    ///   - endStep: 不属于规则部分的后置字符长度
    ///   - fr: 查找到内嵌规则时，用于解析的函数
    @discardableResult
    public func innerRule(
        _ inner: String,
        startStep: Int = 1,
        endStep: Int = 1,
        _ fr: (String) throws -> String?
    ) rethrows -> String {
        var st = ""
        while consumeTo(inner) {
            let posPre = pos
            if chompCodeBalanced("{", "}") {
                let frv = try fr(sub(posPre + startStep, pos - endStep))
                if let frv = frv, !frv.isEmpty {
                    st += sub(startX, posPre) + frv
                    startX = pos
                    continue
                }
            }
            pos += inner.count
        }
        return startX == 0 ? "" : st + sub(startX)
    }

    /// 替换内嵌规则（起止字符串形式）
    @discardableResult
    public func innerRule(
        startStr: String,
        endStr: String,
        _ fr: (String) throws -> String?
    ) rethrows -> String {
        var st = ""
        while consumeTo(startStr) {
            pos += startStr.count
            let posPre = pos
            if consumeTo(endStr) {
                let frv = try fr(sub(posPre, pos)) ?? ""
                st += sub(startX, posPre - startStr.count) + frv
                pos += endStr.count
                startX = pos
            }
        }
        return startX == 0 ? String(queue) : st + sub(startX)
    }
}
