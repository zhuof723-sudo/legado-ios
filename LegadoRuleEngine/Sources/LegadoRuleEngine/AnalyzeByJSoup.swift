import Foundation
import SwiftSoup

/// 对应 legado: model/analyzeRule/AnalyzeByJSoup.kt
/// 书源 CSS 规则解析，基于 SwiftSoup（jsoup 的 Swift 移植）。
///
/// 注意：SwiftSoup 各版本的方法签名（是否 throws、方法名大小写）可能略有出入，
/// 集成时以你实际引入的 SwiftSoup 版本 API 为准做少量调整（这里按目前主流版本书写）。
public final class AnalyzeByJSoup {

    private let element: Element

    /// doc 可传入 SwiftSoup.Element，或任意可 toString 的对象（html 字符串）
    public init(_ doc: Any) throws {
        self.element = try AnalyzeByJSoup.parse(doc)
    }

    private static func parse(_ doc: Any) throws -> Element {
        if let el = doc as? Element {
            return el
        }
        let html = "\(doc)"
        return try SwiftSoup.parse(html)
    }

    // MARK: - 对外API

    /// 获取列表
    public func getElements(_ rule: String) -> Elements {
        getElements(element, rule)
    }

    /// 合并内容列表,得到内容
    public func getString(_ ruleStr: String) -> String? {
        if ruleStr.isEmpty { return nil }
        let list = getStringList(ruleStr)
        if list.isEmpty { return nil }
        if list.count == 1 { return list[0] }
        return list.joined(separator: "\n")
    }

    /// 获取一个字符串（第一条）
    public func getString0(_ ruleStr: String) -> String {
        let list = getStringList(ruleStr)
        return list.isEmpty ? "" : list[0]
    }

    /// 获取所有内容列表
    public func getStringList(_ ruleStr: String) -> [String] {
        var textS: [String] = []
        if ruleStr.isEmpty { return textS }

        let sourceRule = SourceRule(ruleStr)

        if sourceRule.elementsRule.isEmpty {
            textS.append((try? element.data()) ?? "")
            return textS
        }

        let ruleAnalyzer = RuleAnalyzer(sourceRule.elementsRule)
        guard let ruleStrS = try? ruleAnalyzer.splitRule(["&&", "||", "%%"]) else { return textS }

        var results: [[String]] = []
        for ruleStrX in ruleStrS {
            var temp: [String]?
            if sourceRule.isCss {
                if let lastIndex = ruleStrX.lastIndex(of: "@") {
                    let selector = String(ruleStrX[ruleStrX.startIndex..<lastIndex])
                    let attr = String(ruleStrX[ruleStrX.index(after: lastIndex)...])
                    let selected = (try? element.select(selector)) ?? Elements()
                    temp = getResultLast(selected, attr)
                } else {
                    temp = nil
                }
            } else {
                temp = getResultList(ruleStrX)
            }

            if let temp = temp, !temp.isEmpty {
                results.append(temp)
                if ruleAnalyzer.elementsType == "||" { break }
            }
        }

        if !results.isEmpty {
            if ruleAnalyzer.elementsType == "%%" {
                for i in results[0].indices {
                    for temp in results where i < temp.count {
                        textS.append(temp[i])
                    }
                }
            } else {
                for temp in results { textS.append(contentsOf: temp) }
            }
        }
        return textS
    }

    // MARK: - Elements 获取

    private func getElements(_ temp: Element?, _ rule: String) -> Elements {
        guard let temp = temp, !rule.isEmpty else { return Elements() }

        let elements = Elements()
        let sourceRule = SourceRule(rule)
        let ruleAnalyzer = RuleAnalyzer(sourceRule.elementsRule)
        guard let ruleStrS = try? ruleAnalyzer.splitRule(["&&", "||", "%%"]) else { return elements }

        var elementsList: [Elements] = []

        if sourceRule.isCss {
            for ruleStr in ruleStrS {
                let tempS = (try? temp.select(ruleStr)) ?? Elements()
                elementsList.append(tempS)
                if !tempS.isEmpty(), ruleAnalyzer.elementsType == "||" { break }
            }
        } else {
            for ruleStr in ruleStrS {
                let rsRule = RuleAnalyzer(ruleStr)
                rsRule.trim() // 修剪当前规则之前的"@"或者空白符
                let rs = (try? rsRule.splitRule(["@"])) ?? [ruleStr]

                let el: Elements
                if rs.count > 1 {
                    let acc = Elements()
                    acc.add(temp)
                    var current = acc
                    for rl in rs {
                        let es = Elements()
                        for et in current.array() {
                            for e in getElements(et, rl).array() { es.add(e) }
                        }
                        current = es
                    }
                    el = current
                } else {
                    el = ElementsSingle().getElementsSingle(temp, ruleStr)
                }

                elementsList.append(el)
                if el.size() > 0, ruleAnalyzer.elementsType == "||" { break }
            }
        }

        if !elementsList.isEmpty {
            if ruleAnalyzer.elementsType == "%%" {
                for i in 0..<elementsList[0].size() {
                    for es in elementsList where i < es.size() {
                        elements.add(es.get(i))
                    }
                }
            } else {
                for es in elementsList { for e in es.array() { elements.add(e) } }
            }
        }
        return elements
    }

    /// 获取内容列表（rule 为单条 @ 分隔子句时的完整链路：前置选择器链 + 最后一个取值动作）
    private func getResultList(_ ruleStr: String) -> [String]? {
        if ruleStr.isEmpty { return nil }

        var elements = Elements()
        elements.add(element)

        let rule = RuleAnalyzer(ruleStr)
        rule.trim()
        guard let rules = try? rule.splitRule(["@"]) else { return nil }

        let last = rules.count - 1
        for i in 0..<last {
            let es = Elements()
            for elt in elements.array() {
                for e in ElementsSingle().getElementsSingle(elt, rules[i]).array() { es.add(e) }
            }
            elements = es
        }
        return elements.isEmpty() ? nil : getResultLast(elements, rules[last])
    }

    /// 根据最后一个规则获取内容（text/textNodes/ownText/html/all/属性名）
    private func getResultLast(_ elements: Elements, _ lastRule: String) -> [String] {
        var textS: [String] = []
        switch lastRule {
        case "text":
            for el in elements.array() {
                let text = (try? el.text()) ?? ""
                if !text.isEmpty { textS.append(text) }
            }
        case "textNodes":
            for el in elements.array() {
                var tn: [String] = []
                let contentEs = el.getChildNodes().compactMap { $0 as? TextNode }
                for item in contentEs {
                    let text = item.text().trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty { tn.append(text) }
                }
                if !tn.isEmpty { textS.append(tn.joined(separator: "\n")) }
            }
        case "ownText":
            for el in elements.array() {
                let text = (try? el.ownText()) ?? ""
                if !text.isEmpty { textS.append(text) }
            }
        case "html":
            try? elements.select("script").remove()
            for el in elements.array() {
                if let html = try? el.html(), !html.isEmpty {
                    textS.append(html)
                }
            }
        case "all":
            if let html = try? elements.outerHtml() {
                textS.append(html)
            }
        default:
            for el in elements.array() {
                let url = (try? el.attr(lastRule)) ?? ""
                if url.trimmingCharacters(in: .whitespaces).isEmpty || textS.contains(url) { continue }
                textS.append(url)
            }
        }
        return textS
    }

    // MARK: - SourceRule：识别 @CSS: 前缀

    struct SourceRule {
        var isCss = false
        var elementsRule: String

        init(_ ruleStr: String) {
            if ruleStr.lowercased().hasPrefix("@css:") {
                isCss = true
                let idx = ruleStr.index(ruleStr.startIndex, offsetBy: 5)
                elementsRule = String(ruleStr[idx...]).trimmingCharacters(in: .whitespaces)
            } else {
                elementsRule = ruleStr
            }
        }
    }

    // MARK: - ElementsSingle：阅读原生索引选择器语法

    /// 1. 支持阅读原有写法，':'分隔索引，'!'或'.'表示筛选方式，索引可为负数
    ///    例如 tag.div.-1:10:2 或 tag.div!0:3
    /// 2. 支持与 jsonPath 类似的 []索引写法
    ///    格式形如 [it,it,...] 或 [!it,it,...]，其中 [! 开头表示筛选方式为排除，
    ///    it 为单个索引或区间。区间格式为 start:end 或 start:end:step，
    ///    索引、区间两端及间隔都支持负数。例如 tag.div[-1, 3:-2:-10, 2]
    ///    特殊用法 tag.div[-1:0] 可在任意地方让列表反向
    final class ElementsSingle {
        private enum IndexKind {
            case single(Int)
            case range(start: Int?, end: Int?, step: Int)
        }

        private var split: Character = "."
        private var beforeRule: String = ""
        private var indexDefault: [Int] = []      // 阅读原写法收集的索引（正序追加，逆向解析产生）
        private var indexes: [IndexKind] = []      // []写法收集的索引/区间

        func getElementsSingle(_ temp: Element, _ rule: String) -> Elements {
            findIndexSet(rule)

            // 获取所有元素
            let elements: Elements
            if beforeRule.isEmpty {
                elements = (try? temp.children()) ?? Elements()
            } else {
                let rules = beforeRule.components(separatedBy: ".")
                switch rules[0] {
                case "children":
                    elements = (try? temp.children()) ?? Elements()
                case "class":
                    elements = (try? temp.getElementsByClass(rules.count > 1 ? rules[1] : "")) ?? Elements()
                case "tag":
                    elements = (try? temp.getElementsByTag(rules.count > 1 ? rules[1] : "")) ?? Elements()
                case "id":
                    let es = Elements()
                    if rules.count > 1, let byId = try? temp.getElementById(rules[1]) {
                        es.add(byId)
                    }
                    elements = es
                case "text":
                    elements = (try? temp.getElementsContainingOwnText(rules.count > 1 ? rules[1] : "")) ?? Elements()
                default:
                    elements = (try? temp.select(beforeRule)) ?? Elements()
                }
            }

            let len = elements.size()
            let lastIndexes = (indexDefault.count - 1 >= 0) ? indexDefault.count - 1 : indexes.count - 1
            var indexSet: [Int] = []
            var seen = Set<Int>()
            func addIndex(_ i: Int) {
                if !seen.contains(i) { seen.insert(i); indexSet.append(i) }
            }

            if indexes.isEmpty {
                // 非[]式索引，逆向遍历插入，最后再反转以还原顺序
                var collected: [Int] = []
                var ix = lastIndexes
                while ix >= 0 {
                    let it = indexDefault[ix]
                    if it >= 0, it < len { collected.append(it) }
                    else if it < 0, len >= -it { collected.append(it + len) }
                    ix -= 1
                }
                for v in collected.reversed() { addIndex(v) }
            } else {
                var collected: [Int] = []
                var ix = lastIndexes
                while ix >= 0 {
                    switch indexes[ix] {
                    case .range(let startX, let endX, let stepX):
                        var start = startX ?? 0
                        if start < 0 { start += len }
                        var end = endX ?? (len - 1)
                        if end < 0 { end += len }

                        if (start < 0 && end < 0) || (start >= len && end >= len) {
                            ix -= 1
                            continue
                        }
                        if start >= len { start = len - 1 } else if start < 0 { start = 0 }
                        if end >= len { end = len - 1 } else if end < 0 { end = 0 }

                        if start == end || abs(stepX) >= len {
                            collected.append(start)
                            ix -= 1
                            continue
                        }

                        let step = stepX > 0 ? stepX : (-stepX < len ? stepX + len : 1)
                        if end > start {
                            var v = start
                            while v <= end { collected.append(v); v += step }
                        } else {
                            var v = start
                            while v >= end { collected.append(v); v += step } // step 为负数
                        }
                    case .single(let it):
                        if it >= 0, it < len { collected.append(it) }
                        else if it < 0, len >= -it { collected.append(it + len) }
                    }
                    ix -= 1
                }
                for v in collected.reversed() { addIndex(v) }
            }

            let all = elements.array()
            if split == "!" {
                let excluded = Set(indexSet)
                let kept = all.enumerated().filter { !excluded.contains($0.offset) }.map { $0.element }
                let es = Elements()
                for e in kept { es.add(e) }
                return es
            } else if split == "." {
                let es = Elements()
                for i in indexSet where i >= 0 && i < all.count { es.add(all[i]) }
                return es
            }
            return elements
        }

        private func findIndexSet(_ rule: String) {
            let rus = Array(rule.trimmingCharacters(in: .whitespaces))
            var len = rus.count
            var curMinus = false
            var curList: [Int?] = []
            var l = ""

            guard !rus.isEmpty else { split = " "; beforeRule = String(rus); return }

            let head = rus.last == "]"

            if head {
                len -= 1 // 跳过尾部']'
                var idx = len
                loop: while idx >= 0 {
                    defer { idx -= 1 }
                    if idx >= rus.count { continue }
                    var rl = rus[idx]
                    if rl == " " { continue }

                    if rl >= "0" && rl <= "9" {
                        l = String(rl) + l
                    } else if rl == "-" {
                        curMinus = true
                    } else {
                        let curInt: Int? = l.isEmpty ? nil : (curMinus ? -(Int(l) ?? 0) : Int(l))

                        if rl == ":" {
                            curList.append(curInt)
                        } else {
                            if curList.isEmpty {
                                guard let curInt = curInt else { break loop } // 是选择器而非索引列表
                                indexes.append(.single(curInt))
                            } else {
                                let stepVal = curList.count == 2 ? (curList.first.flatMap { $0 } ?? 1) : 1
                                indexes.append(.range(start: curInt, end: curList.last.flatMap { $0 }, step: stepVal))
                                curList.removeAll()
                            }

                            if rl == "!" {
                                split = "!"
                                idx -= 1
                                while idx > 0, idx < rus.count, rus[idx] == " " { idx -= 1 }
                                if idx >= 0, idx < rus.count { rl = rus[idx] }
                            }

                            if idx >= 0, idx < rus.count, rus[idx] == "[" {
                                beforeRule = String(rus[0..<idx])
                                return
                            }

                            if rl != "," { break loop }
                        }

                        l = ""
                        curMinus = false
                    }
                }
            } else {
                var idx = len - 1
                loop2: while idx >= 0 {
                    defer { idx -= 1 }
                    let rl = rus[idx]
                    if rl == " " { continue }

                    if rl >= "0" && rl <= "9" {
                        l = String(rl) + l
                    } else if rl == "-" {
                        curMinus = true
                    } else {
                        if rl == "!" || rl == "." || rl == ":" {
                            let v = curMinus ? -(Int(l) ?? 0) : (Int(l) ?? 0)
                            indexDefault.append(v)
                            if rl != ":" {
                                split = rl
                                beforeRule = String(rus[0..<idx])
                                return
                            }
                        } else {
                            break loop2
                        }
                        l = ""
                        curMinus = false
                    }
                }
            }

            split = " "
            beforeRule = String(rus)
        }
    }
}
