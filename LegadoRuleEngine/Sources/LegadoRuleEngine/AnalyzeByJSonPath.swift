import Foundation

/// 对应 legado: model/analyzeRule/AnalyzeByJSonPath.kt
/// 基于 MiniJSONPath，处理 "&&"、"||"、"%%" 组合以及 {$.rule} 内嵌规则替换，
/// 解决阅读规则里 "&&"、"||" 与 jsonPath 语法本身冲突的问题（RuleAnalyzer 负责这部分）。
public final class AnalyzeByJSonPath {

    private let rootAny: Any

    /// json 可传入已解析对象（[String:Any] / [Any] / ...），或原始 JSON 字符串
    public init(_ json: Any) {
        if let s = json as? String {
            if let data = s.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) {
                self.rootAny = obj
            } else {
                self.rootAny = s
            }
        } else {
            self.rootAny = json
        }
    }

    private func stringify(_ v: Any) -> String {
        if let s = v as? String { return s }
        if v is NSNull { return "null" }
        if let n = v as? NSNumber { return n.stringValue }
        if let arr = v as? [Any] {
            return arr.map { stringify($0) }.joined(separator: "\n")
        }
        if JSONSerialization.isValidJSONObject(v),
           let data = try? JSONSerialization.data(withJSONObject: v, options: [.sortedKeys]) {
            return String(data: data, encoding: .utf8) ?? ""
        }
        return "\(v)"
    }

    /// 改进解析方法：
    /// 解决阅读"&&""||"与 jsonPath 支持的"&&""||"之间的冲突
    /// 解决 {$.rule} 形式规则可能匹配错误的问题，用平衡嵌套方法而非正则解决
    public func getString(_ rule: String) -> String? {
        if rule.isEmpty { return nil }
        var result = ""
        let ruleAnalyzer = RuleAnalyzer(rule, code: true) // 设置平衡组为代码平衡
        guard let rules = try? ruleAnalyzer.splitRule(["&&", "||"]) else { return nil }

        if rules.count == 1 {
            ruleAnalyzer.reSetPos() // 复用解析器

            result = (try? ruleAnalyzer.innerRule("{$.", { self.getString($0) })) ?? ""

            if result.isEmpty { // 无成功替换的内嵌规则
                if let matched = try? MiniJSONPath.query(rootAny, rule), !matched.isEmpty {
                    result = matched.count == 1
                        ? stringify(matched[0])
                        : matched.map { stringify($0) }.joined(separator: "\n")
                }
            }
            return result
        } else {
            var textList: [String] = []
            for rl in rules {
                if let temp = getString(rl), !temp.isEmpty {
                    textList.append(temp)
                    if ruleAnalyzer.elementsType == "||" { break }
                }
            }
            return textList.joined(separator: "\n")
        }
    }

    public func getStringList(_ rule: String) -> [String] {
        var result: [String] = []
        if rule.isEmpty { return result }
        let ruleAnalyzer = RuleAnalyzer(rule, code: true)
        guard let rules = try? ruleAnalyzer.splitRule(["&&", "||", "%%"]) else { return result }

        if rules.count == 1 {
            ruleAnalyzer.reSetPos()
            let st = (try? ruleAnalyzer.innerRule("{$.", { self.getString($0) })) ?? ""
            if st.isEmpty {
                if let matched = try? MiniJSONPath.query(rootAny, rule) {
                    for o in matched { result.append(stringify(o)) }
                }
            } else {
                result.append(st)
            }
            return result
        } else {
            var results: [[String]] = []
            for rl in rules {
                let temp = getStringList(rl)
                if !temp.isEmpty {
                    results.append(temp)
                    if ruleAnalyzer.elementsType == "||" { break }
                }
            }
            if !results.isEmpty {
                if ruleAnalyzer.elementsType == "%%" {
                    for i in results[0].indices {
                        for temp in results where i < temp.count {
                            result.append(temp[i])
                        }
                    }
                } else {
                    for temp in results { result.append(contentsOf: temp) }
                }
            }
            return result
        }
    }

    public func getObject(_ rule: String) -> Any? {
        (try? MiniJSONPath.query(rootAny, rule))?.first
    }

    public func getList(_ rule: String) -> [Any]? {
        var result: [Any] = []
        if rule.isEmpty { return result }
        let ruleAnalyzer = RuleAnalyzer(rule, code: true)
        guard let rules = try? ruleAnalyzer.splitRule(["&&", "||", "%%"]) else { return result }

        if rules.count == 1 {
            return (try? MiniJSONPath.query(rootAny, rules[0])) ?? []
        } else {
            var results: [[Any]] = []
            for rl in rules {
                if let temp = getList(rl), !temp.isEmpty {
                    results.append(temp)
                    if ruleAnalyzer.elementsType == "||" { break }
                }
            }
            if !results.isEmpty {
                if ruleAnalyzer.elementsType == "%%" {
                    for i in 0..<results[0].count {
                        for temp in results where i < temp.count {
                            result.append(temp[i])
                        }
                    }
                } else {
                    for temp in results { result.append(contentsOf: temp) }
                }
            }
        }
        return result
    }
}
