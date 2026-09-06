import Foundation

/// 对应 legado: AnalyzeRule.kt 里的 inner class SourceRule
/// 单条规则字符串的解析结果：识别 @css:/@xpath:/@json:/@@/正则(/开头) 等模式前缀，
/// 拆出 @put:{...} 变量赋值、@get:{...}/{{...}} 内嵌取值/JS段、以及末尾的
/// "##正则##替换##标记" 后缀（用于结果的正则替换）。
///
/// Kotlin 原版是 AnalyzeRule 的 inner class（隐式持有外部实例），
/// Swift 里用显式 `outer` 弱引用替代。
public final class SourceRule {

    public internal(set) var rule: String
    public internal(set) var mode: AnalyzeRule.Mode
    public internal(set) var replaceRegex: String = ""
    public internal(set) var replacement: String = ""
    public internal(set) var replaceFirst: Bool = false
    public internal(set) var putMap: [String: String] = [:]

    private var ruleParam: [String] = []
    private var ruleType: [Int] = []
    private let getRuleType = -2
    private let jsRuleType = -1
    private let defaultRuleType = 0

    private unowned let outer: AnalyzeRule

    public init(_ ruleStr: String, mode: AnalyzeRule.Mode = .css, outer: AnalyzeRule) {
        self.outer = outer
        self.mode = mode

        var mMode = mode
        var r: String

        switch true {
        case mMode == .js || mMode == .regex:
            r = ruleStr
        case Self.hasPrefixCI(ruleStr, "@CSS:"):
            mMode = .css
            r = ruleStr
        case ruleStr.hasPrefix("@@"):
            mMode = .css
            r = String(ruleStr.dropFirst(2))
        case Self.hasPrefixCI(ruleStr, "@XPath:"):
            mMode = .xpath
            r = String(ruleStr.dropFirst(7))
        case Self.hasPrefixCI(ruleStr, "@Json:"):
            mMode = .json
            r = String(ruleStr.dropFirst(6))
        case outer.currentIsJSON || ruleStr.hasPrefix("$.") || ruleStr.hasPrefix("$["):
            mMode = .json
            r = ruleStr
        case ruleStr.hasPrefix("/"):
            mMode = .xpath
            r = ruleStr
        default:
            r = ruleStr
        }

        self.mode = mMode
        r = Self.splitPutRule(r, &putMap)
        self.rule = r

        // @get:{...} 与 {{...}} 拆分
        let ns = r as NSString
        let full = NSRange(location: 0, length: ns.length)
        let evalMatches = AnalyzeRule.evalPatternShared.matches(in: r, range: full)
        var start = 0

        if let first = evalMatches.first {
            let tmpPre = ns.substring(with: NSRange(location: start, length: first.range.location - start))
            if mMode != .js, mMode != .regex, (first.range.location == 0 || !tmpPre.contains("##")) {
                self.mode = .regex
            }
            for m in evalMatches {
                if m.range.location > start {
                    let tmp = ns.substring(with: NSRange(location: start, length: m.range.location - start))
                    splitRegex(tmp)
                }
                let tmp = ns.substring(with: m.range)
                if Self.hasPrefixCI(tmp, "@get:") {
                    ruleType.append(getRuleType)
                    let s = tmp as NSString
                    let sub = s.substring(with: NSRange(location: 6, length: max(0, s.length - 1 - 6)))
                    ruleParam.append(sub)
                } else if tmp.hasPrefix("{{") {
                    ruleType.append(jsRuleType)
                    let s = tmp as NSString
                    let sub = s.substring(with: NSRange(location: 2, length: max(0, s.length - 4)))
                    ruleParam.append(sub)
                } else {
                    splitRegex(tmp)
                }
                start = m.range.location + m.range.length
            }
        }
        if ns.length > start {
            let tmp = ns.substring(with: NSRange(location: start, length: ns.length - start))
            splitRegex(tmp)
        }
    }

    private static func hasPrefixCI(_ s: String, _ prefix: String) -> Bool {
        s.count >= prefix.count && s.lowercased().hasPrefix(prefix.lowercased())
    }

    /// 分离 @put:{...} 规则，合并进 putMap，并返回去除这些片段后的字符串
    private static func splitPutRule(_ ruleStr: String, _ putMap: inout [String: String]) -> String {
        var vRuleStr = ruleStr
        let ns = ruleStr as NSString
        let full = NSRange(location: 0, length: ns.length)
        let matches = AnalyzeRule.putPatternShared.matches(in: ruleStr, range: full)
        for m in matches {
            let whole = ns.substring(with: m.range)
            vRuleStr = vRuleStr.replacingOccurrences(of: whole, with: "")
            guard m.numberOfRanges > 1, m.range(at: 1).location != NSNotFound else { continue }
            let putJsonStr = ns.substring(with: m.range(at: 1))
            if let data = putJsonStr.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                for (k, v) in obj { putMap[k] = "\(v)" }
            }
        }
        return vRuleStr
    }

    /// 拆分 \$\d{1,2} 正则组引用（如 $1 $2），未匹配部分作为普通文本段
    private func splitRegex(_ ruleStr: String) {
        var start = 0
        let ns = ruleStr as NSString
        let ruleStrArray = ruleStr.components(separatedBy: "##")
        let first = ruleStrArray[0]
        let firstNS = first as NSString
        let matches = AnalyzeRule.regexNumPatternShared.matches(in: first, range: NSRange(location: 0, length: firstNS.length))

        if !matches.isEmpty {
            if mode != .js, mode != .regex { mode = .regex }
            for m in matches {
                if m.range.location > start {
                    let tmp = ns.substring(with: NSRange(location: start, length: m.range.location - start))
                    ruleType.append(defaultRuleType)
                    ruleParam.append(tmp)
                }
                let tmp = firstNS.substring(with: m.range)
                let numPart = String(tmp.dropFirst())
                ruleType.append(Int(numPart) ?? defaultRuleType)
                ruleParam.append(tmp)
                start = m.range.location + m.range.length
            }
        }
        if ns.length > start {
            let tmp = ns.substring(with: NSRange(location: start, length: ns.length - start))
            ruleType.append(defaultRuleType)
            ruleParam.append(tmp)
        }
    }

    /// 替换 @get:{...} / {{...}} / $N，得到本次可用的最终 rule 字符串，
    /// 并（每次调用都）重新按 "##" 切出 replaceRegex / replacement / replaceFirst。
    public func makeUpRule(_ result: Any?) {
        var infoVal = ""
        if !ruleParam.isEmpty {
            var index = ruleParam.count
            while index > 0 {
                index -= 1
                let regType = ruleType[index]
                if regType > defaultRuleType {
                    if let list = result as? [String?], list.count > regType, let v = list[regType] {
                        infoVal = v + infoVal
                    } else if let list = result as? [String], list.count > regType {
                        infoVal = list[regType] + infoVal
                    } else {
                        infoVal = ruleParam[index] + infoVal
                    }
                } else if regType == jsRuleType {
                    if Self.isRule(ruleParam[index]) {
                        let ruleList = outer.getOrCreateSingleSourceRuleShared(ruleParam[index])
                        infoVal = outer.getString(ruleList) + infoVal
                    } else {
                        switch outer.evalJS(ruleParam[index], result: result) {
                        case .none:
                            break
                        case let s as String:
                            infoVal = s + infoVal
                        case let d as Double:
                            if d.truncatingRemainder(dividingBy: 1.0) == 0 {
                                infoVal = String(format: "%.0f", d) + infoVal
                            } else {
                                infoVal = "\(d)" + infoVal
                            }
                        case let other?:
                            infoVal = "\(other)" + infoVal
                        }
                    }
                } else if regType == getRuleType {
                    infoVal = outer.get(ruleParam[index]) + infoVal
                } else {
                    infoVal = ruleParam[index] + infoVal
                }
            }
            rule = infoVal
        }
        // 分离正则表达式后缀：形如 规则##正则##替换文本##（末尾出现第4段代表 replaceFirst）
        let ruleStrS = rule.components(separatedBy: "##")
        rule = ruleStrS[0].trimmingCharacters(in: .whitespaces)
        if ruleStrS.count > 1 { replaceRegex = ruleStrS[1] }
        if ruleStrS.count > 2 { replacement = ruleStrS[2] }
        if ruleStrS.count > 3 { replaceFirst = true }
    }

    private static func isRule(_ ruleStr: String) -> Bool {
        ruleStr.hasPrefix("@") || ruleStr.hasPrefix("$.") || ruleStr.hasPrefix("$[") || ruleStr.hasPrefix("//")
    }

    public func getParamSize() -> Int { ruleParam.count }
}
