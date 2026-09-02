import Foundation
import JavaScriptCore

/// 对应 legado: model/analyzeRule/RuleDataInterface.kt
/// book / chapter / rssArticle 等承载 @put/@get 变量的对象需要实现这个协议。
public protocol RuleDataInterface: AnyObject {
    var variableMap: [String: String] { get set }
}

public extension RuleDataInterface {
    @discardableResult
    func putVariable(_ key: String, _ value: String?) -> Bool {
        let existed = variableMap[key] != nil
        if let value = value {
            variableMap[key] = value
            return true
        } else {
            variableMap.removeValue(forKey: key)
            return existed
        }
    }

    func getVariable(_ key: String) -> String {
        variableMap[key] ?? ""
    }
}

/// JS 里 java.xxx() 调用的桥接对象。对应 legado 的 JsExtensions。
/// 目前实现了 put/get/log；ajax（跨域请求）需要你注入网络层实现（见 AnalyzeRule.ajaxEvaluator）。
@objc public protocol LegadoJSBridgeExport: JSExport {
    func put(_ key: String, _ value: String) -> String
    func get(_ key: String) -> String
    func log(_ msg: String) -> String
    func ajax(_ url: String) -> String?
    func ajaxAll(_ urls: [String]) -> [String]
    func base64Encode(_ s: String) -> String
    func base64Decode(_ s: String) -> String
    func base64DecodeToByteArray(_ s: String) -> [Int]
    func hexDecodeToString(_ hex: String) -> String
    func timeFormat(_ millis: Double) -> String
    func toast(_ msg: String) -> String
    func longToast(_ msg: String) -> String
    func androidId() -> String
    func deviceID() -> String
    func getWebViewUA() -> String
    func createSymmetricCrypto(_ transformation: String, _ key: String, _ iv: String) -> SymmetricCryptoJSBridge?
    // 以下几个是"打开浏览器/触发App动作"类，需要真实UI才有意义，默认是弱化实现（见各方法说明）
    func open(_ action: String, _ url: String?, _ title: String?) -> String
    func showBrowser(_ url: String, _ title: String?) -> String
    func startBrowser(_ url: String, _ title: String?) -> String
    func startBrowserAwait(_ url: String, _ title: String?) -> String
    func startBrowserDp(_ url: String, _ title: String?) -> String
    func refreshExplore() -> String
    func searchBook(_ keyword: String, _ sourceFilter: String?) -> String
    func qread() -> String
}

@objc public final class LegadoJSBridge: NSObject, LegadoJSBridgeExport {
    weak var rule: AnalyzeRule?
    init(_ rule: AnalyzeRule) { self.rule = rule }

    public func put(_ key: String, _ value: String) -> String {
        rule?.put(key, value) ?? value
    }
    public func get(_ key: String) -> String {
        rule?.get(key) ?? ""
    }
    public func log(_ msg: String) -> String {
        print("[书源日志] \(msg)")
        return msg
    }
    public func ajax(_ url: String) -> String? {
        rule?.ajaxEvaluator?(url)
    }
    public func ajaxAll(_ urls: [String]) -> [String] {
        urls.map { rule?.ajaxEvaluator?($0) ?? "" }
    }
    public func base64Encode(_ s: String) -> String { JSCommonMethods.base64Encode(s) }
    public func base64Decode(_ s: String) -> String { JSCommonMethods.base64Decode(s) }
    public func base64DecodeToByteArray(_ s: String) -> [Int] { JSCommonMethods.base64DecodeToByteArray(s) }
    public func hexDecodeToString(_ hex: String) -> String { JSCommonMethods.hexDecodeToString(hex) }
    public func timeFormat(_ millis: Double) -> String { JSCommonMethods.timeFormat(millis) }
    public func toast(_ msg: String) -> String {
        print("[toast] \(msg)")
        rule?.toastHandler?(msg)
        return msg
    }
    public func longToast(_ msg: String) -> String {
        print("[longToast] \(msg)")
        rule?.toastHandler?(msg)
        return msg
    }
    public func androidId() -> String { JSCommonMethods.deviceIdentifier }
    public func deviceID() -> String { JSCommonMethods.deviceIdentifier }
    public func getWebViewUA() -> String { JSCommonMethods.defaultUserAgent }
    public func createSymmetricCrypto(_ transformation: String, _ key: String, _ iv: String) -> SymmetricCryptoJSBridge? {
        SymmetricCryptoJSBridge(transformation: transformation, key: key, iv: iv)
    }
    public func open(_ action: String, _ url: String?, _ title: String?) -> String {
        if let url = url { rule?.browserOpener?(url, title) }
        return ""
    }
    public func showBrowser(_ url: String, _ title: String?) -> String {
        rule?.browserOpener?(url, title); return ""
    }
    public func startBrowser(_ url: String, _ title: String?) -> String {
        rule?.browserOpener?(url, title); return ""
    }
    public func startBrowserAwait(_ url: String, _ title: String?) -> String {
        // 真实语义是"打开浏览器并等它关闭后拿返回值"，这里没法同步等UI交互，弱化成"打开就返回空"
        rule?.browserOpener?(url, title); return ""
    }
    public func startBrowserDp(_ url: String, _ title: String?) -> String {
        rule?.browserOpener?(url, title); return ""
    }
    public func refreshExplore() -> String {
        rule?.refreshExploreHandler?(); return ""
    }
    public func searchBook(_ keyword: String, _ sourceFilter: String?) -> String {
        rule?.searchBookHandler?(keyword, sourceFilter); return ""
    }
    public func qread() -> String { "0" }
}

/// 对应 legado: model/analyzeRule/AnalyzeRule.kt
/// 解析规则获取结果 —— 书源规则引擎的总调度器。
///
/// 范围说明（相对 Kotlin 原版的删减）：
/// - Mode.xpath: AnalyzeByXPath 未移植（JXPath 无直接对应库），命中时会打印告警并返回空结果。
///   多数书源规则以 CSS 为主，XPath 规则占比较小，可作为后续任务单独用 libxml2 实现。
/// - Mode.webJs: 依赖真实 WebView 渲染执行 JS 再取值，请通过 `webJsEvaluator` 注入你的 WKWebView 实现。
/// - ajax（JS 里 java.ajax(url)）：依赖网络层（对应 Kotlin 的 AnalyzeUrl.kt，未在本次移植范围内），
///   通过 `ajaxEvaluator` 注入。
public final class AnalyzeRule {

    public enum Mode {
        case xpath, json, css, js, regex, webJs
    }

    // MARK: - 可注入扩展点

    /// 承载 @put/@get 变量的数据对象（对应 book/chapter/rssArticle）
    public var ruleData: RuleDataInterface?
    /// 变量存取兜底（对应书源级 source.get/put）
    public var sourceGet: ((String) -> String?)?
    public var sourcePut: ((String, String) -> Void)?
    /// @webJs: 规则求值，需要注入真实 WebView 实现
    public var webJsEvaluator: ((_ js: String, _ result: Any) -> String)?
    /// JS 里 java.ajax(url) 用到的网络层，需要注入
    public var ajaxEvaluator: ((_ url: String) -> String?)?
    /// java.toast/longToast 的UI提示，不注入的话只会打印到控制台
    public var toastHandler: ((_ msg: String) -> Void)?
    /// java.open/showBrowser/startBrowser* 系列，注入你的应用内浏览器/WebView展示逻辑
    public var browserOpener: ((_ url: String, _ title: String?) -> Void)?
    /// java.refreshExplore()：书源想让"发现"页刷新时调用
    public var refreshExploreHandler: (() -> Void)?
    /// java.searchBook(keyword, sourceFilter)：书源想触发一次App内搜索时调用
    public var searchBookHandler: ((_ keyword: String, _ sourceFilter: String?) -> Void)?
    /// 书源的公共JS库（BookSource.jsLib），每次 evalJS 都会先跑一遍，
    /// 让规则脚本能直接调用里面定义的公共函数
    public var jsLib: String?
    /// 书源级别的持久变量 + 登录信息绑定，暴露为JS里的 `this.source`
    public weak var sourceContext: SourceJSContext?

    public var bookName: String?
    public var chapterTitle: String?

    // MARK: - 内部状态

    private var content: Any?
    private var baseUrl: String?
    private var redirectUrl: URL?
    private var isJSON: Bool = false
    private var isRegex: Bool = false

    private var analyzeByJSoup: AnalyzeByJSoup?
    private var analyzeByJSonPath: AnalyzeByJSonPath?

    private var stringRuleCache: [String: [SourceRule]] = [:]
    private var regexCache: [String: NSRegularExpression?] = [:]
    private var loggedXPathWarning = false

    private static let jsPattern = try! NSRegularExpression(pattern: "<js>([\\w\\W]*?)</js>|@js:([\\w\\W]*)", options: [.caseInsensitive])
    private static let webJsPattern = try! NSRegularExpression(pattern: "@webjs:([\\w\\W]{5,})", options: [.caseInsensitive])
    /// 供 AnalyzeUrl.swift 复用（<js>...</js> / @js:... 匹配）
    static let jsPatternShared = jsPattern

    // 供 SourceRule.swift 复用的共享正则（跨实例只编译一次）
    static let putPatternShared = try! NSRegularExpression(pattern: "@put:(\\{[^}]+?\\})", options: [.caseInsensitive])
    static let evalPatternShared = try! NSRegularExpression(pattern: "@get:\\{[^}]+?\\}|\\{\\{[\\w\\W]*?\\}\\}", options: [.caseInsensitive])
    static let regexNumPatternShared = try! NSRegularExpression(pattern: "\\$\\d{1,2}")

    /// 供 SourceRule 判断当前内容是否是 JSON（决定规则默认走 json 还是 css 模式）
    var currentIsJSON: Bool { isJSON }

    public init(ruleData: RuleDataInterface? = nil) {
        self.ruleData = ruleData
    }

    // MARK: - 内容设置

    @discardableResult
    public func setContent(_ content: Any, baseUrl: String? = nil) -> AnalyzeRule {
        self.content = content
        isJSON = Self.looksLikeJSON(content)
        setBaseUrl(baseUrl)
        analyzeByJSoup = nil
        analyzeByJSonPath = nil
        return self
    }

    @discardableResult
    public func setBaseUrl(_ baseUrl: String?) -> AnalyzeRule {
        if let baseUrl = baseUrl { self.baseUrl = baseUrl }
        return self
    }

    @discardableResult
    public func setRedirectUrl(_ url: String) -> URL? {
        if url.hasPrefix("data:") { return redirectUrl }
        redirectUrl = URL(string: url)
        return redirectUrl
    }

    private static func looksLikeJSON(_ content: Any) -> Bool {
        guard let s = (content as? String) ?? (content as? CustomStringConvertible)?.description else { return false }
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return (t.hasPrefix("{") && t.hasSuffix("}")) || (t.hasPrefix("[") && t.hasSuffix("]"))
    }

    // MARK: - 子解析器获取

    private func getAnalyzeByJSoup(_ o: Any) -> AnalyzeByJSoup? {
        try? AnalyzeByJSoup(o)
    }

    private func getAnalyzeByJSonPath(_ o: Any) -> AnalyzeByJSonPath {
        AnalyzeByJSonPath(o)
    }

    // MARK: - 变量存取

    @discardableResult
    public func put(_ key: String, _ value: String) -> String {
        if ruleData != nil {
            ruleData?.variableMap[key] = value
        } else {
            sourcePut?(key, value)
        }
        return value
    }

    public func get(_ key: String) -> String {
        if key == "bookName", let bookName = bookName { return bookName }
        if key == "title", let chapterTitle = chapterTitle { return chapterTitle }
        if let v = ruleData?.variableMap[key], !v.isEmpty { return v }
        if let v = sourceGet?(key), !v.isEmpty { return v }
        return ""
    }

    // MARK: - JS 执行

    @discardableResult
    public func evalJS(_ jsStr: String, result: Any? = nil) -> Any? {
        guard let context = JSContext() else { return nil }
        var errorMsg: String?
        context.exceptionHandler = { _, exception in
            errorMsg = exception?.toString()
        }
        let bridge = LegadoJSBridge(self)
        context.setObject(bridge, forKeyedSubscript: "java" as NSString)
        context.setObject(SourceJSBridge(sourceContext), forKeyedSubscript: "source" as NSString)
        context.setObject(CookieJSBridge(), forKeyedSubscript: "cookie" as NSString)
        context.setObject(baseUrl ?? "", forKeyedSubscript: "baseUrl" as NSString)
        context.setObject(bookName ?? "", forKeyedSubscript: "bookName" as NSString)
        context.setObject(chapterTitle ?? "", forKeyedSubscript: "title" as NSString)
        if let content = content {
            context.setObject(content, forKeyedSubscript: "src" as NSString)
        }
        if let result = result {
            context.setObject(result, forKeyedSubscript: "result" as NSString)
        }
        if let jsLib = jsLib, !jsLib.isEmpty {
            context.evaluateScript(jsLib)
            if let libError = errorMsg {
                print("jsLib 出错: \(libError)")
                errorMsg = nil // jsLib本身出错不阻断后续规则脚本的执行尝试
            }
        }
        let value = context.evaluateScript(jsStr)
        if let errorMsg = errorMsg {
            print("evalJS 出错: \(errorMsg)\n脚本: \(jsStr)")
            return nil
        }
        return value?.toObject()
    }

    private func getWebJsResult(_ jsStr: String, _ result: Any) -> String {
        webJsEvaluator?(jsStr, result) ?? ""
    }

    // MARK: - 正则替换 (##match##replace### 后缀)

    private func replaceRegex(_ result: String, _ rule: SourceRule) -> String {
        if rule.replaceRegex.isEmpty { return result }
        let regex = compileRegexCache(rule.replaceRegex)
        if rule.replaceFirst {
            guard let regex = regex else { return rule.replacement }
            let ns = result as NSString
            guard let m = regex.firstMatch(in: result, range: NSRange(location: 0, length: ns.length)) else {
                return ""
            }
            let matched = ns.substring(with: m.range)
            return regex.stringByReplacingMatches(
                in: matched, range: NSRange(location: 0, length: (matched as NSString).length),
                withTemplate: rule.replacement
            )
        } else {
            guard let regex = regex else {
                return result.replacingOccurrences(of: rule.replaceRegex, with: rule.replacement)
            }
            let ns = result as NSString
            return regex.stringByReplacingMatches(
                in: result, range: NSRange(location: 0, length: ns.length),
                withTemplate: rule.replacement
            )
        }
    }

    private func compileRegexCache(_ pattern: String) -> NSRegularExpression? {
        if let cached = regexCache[pattern] { return cached }
        let regex = try? NSRegularExpression(pattern: pattern)
        regexCache[pattern] = regex
        return regex
    }

    // MARK: - 规则切分

    private func splitSourceRuleCacheString(_ ruleStr: String?) -> [SourceRule] {
        guard let ruleStr = ruleStr, !ruleStr.isEmpty else { return [] }
        if let cached = stringRuleCache[ruleStr] { return cached }
        let result = splitSourceRule(ruleStr)
        stringRuleCache[ruleStr] = result
        return result
    }

    /// 分解规则生成规则列表：按 <js>...</js> / @js:... / @webjs:... 切出 JS/WebJS 段，其余归为普通段
    public func splitSourceRule(_ ruleStr: String?, allInOne: Bool = false) -> [SourceRule] {
        guard let ruleStr = ruleStr, !ruleStr.isEmpty else { return [] }
        var ruleList: [SourceRule] = []
        var mMode: Mode = .css
        var start = 0

        // 仅首字符为":"时为 AllInOne（正则模式）
        if allInOne, ruleStr.hasPrefix(":") {
            mMode = .regex
            isRegex = true
            start = 1
        } else if isRegex {
            mMode = .regex
        }

        let ns = ruleStr as NSString
        let full = NSRange(location: 0, length: ns.length)

        let jsMatches = Self.jsPattern.matches(in: ruleStr, range: full)
        for m in jsMatches {
            if m.range.location > start {
                let tmp = ns.substring(with: NSRange(location: start, length: m.range.location - start))
                    .trimmingCharacters(in: .whitespaces)
                if !tmp.isEmpty {
                    ruleList.append(SourceRule(tmp, mode: mMode, outer: self))
                }
            }
            let g2 = m.range(at: 2)
            let g1 = m.range(at: 1)
            let jsBody = g2.location != NSNotFound ? ns.substring(with: g2)
                : (g1.location != NSNotFound ? ns.substring(with: g1) : "")
            ruleList.append(SourceRule(jsBody, mode: .js, outer: self))
            start = m.range.location + m.range.length
        }

        let webJsMatches = Self.webJsPattern.matches(in: ruleStr, range: full)
        for m in webJsMatches {
            if m.range.location > start {
                let tmp = ns.substring(with: NSRange(location: start, length: m.range.location - start))
                    .trimmingCharacters(in: .whitespaces)
                if !tmp.isEmpty {
                    ruleList.append(SourceRule(tmp, mode: mMode, outer: self))
                }
            }
            let g1 = m.range(at: 1)
            let body = g1.location != NSNotFound ? ns.substring(with: g1) : ""
            ruleList.append(SourceRule(body, mode: .webJs, outer: self))
            start = m.range.location + m.range.length
        }

        if ns.length > start {
            let tmp = ns.substring(with: NSRange(location: start, length: ns.length - start))
                .trimmingCharacters(in: .whitespaces)
            if !tmp.isEmpty {
                ruleList.append(SourceRule(tmp, mode: mMode, outer: self))
            }
        }
        return ruleList
    }

    private func getOrCreateSingleSourceRule(_ rule: String) -> [SourceRule] {
        if let cached = stringRuleCache[rule] { return cached }
        let result = [SourceRule(rule, outer: self)]
        stringRuleCache[rule] = result
        return result
    }

    /// 供 SourceRule.makeUpRule 里 {{ 嵌套规则 }} 场景调用
    func getOrCreateSingleSourceRuleShared(_ rule: String) -> [SourceRule] {
        getOrCreateSingleSourceRule(rule)
    }

    // MARK: - getString / getStringList / getElement / getElements

    public func getString(_ ruleStr: String?, mContent: Any? = nil, isUrl: Bool = false) -> String {
        guard let ruleStr = ruleStr, !ruleStr.isEmpty else { return "" }
        let ruleList = splitSourceRuleCacheString(ruleStr)
        return getString(ruleList, mContent: mContent, isUrl: isUrl)
    }

    public func getString(
        _ ruleList: [SourceRule],
        mContent: Any? = nil,
        isUrl: Bool = false,
        unescape: Bool = true
    ) -> String {
        var result: Any? = mContent ?? content
        if result != nil, !ruleList.isEmpty {
            for sourceRule in ruleList {
                putRule(sourceRule.putMap)
                sourceRule.makeUpRule(result)
                guard let cur = result else { continue }
                let rule = sourceRule.rule
                if !rule.trimmingCharacters(in: .whitespaces).isEmpty || sourceRule.replaceRegex.isEmpty {
                    switch sourceRule.mode {
                    case .webJs:
                        result = getWebJsResult(rule, cur)
                    case .js:
                        result = evalJS(rule, result: cur)
                    case .json:
                        result = getAnalyzeByJSonPath(cur).getString(rule)
                    case .xpath:
                        result = xpathFallback(rule)
                    case .css:
                        guard let jsoup = getAnalyzeByJSoup(cur) else { result = nil; break }
                        result = isUrl ? jsoup.getString0(rule) : jsoup.getString(rule)
                    default:
                        result = rule
                    }
                }
                if let r = result, !sourceRule.replaceRegex.isEmpty {
                    result = replaceRegex("\(r)", sourceRule)
                }
            }
        }
        var resultStr = result.map { "\($0)" } ?? ""
        if unescape, resultStr.contains("&") {
            resultStr = Self.unescapeHTML(resultStr)
        }
        if isUrl {
            if resultStr.trimmingCharacters(in: .whitespaces).isEmpty {
                return baseUrl ?? ""
            }
            return Self.absoluteURL(effectiveBaseURL, resultStr)
        }
        return resultStr
    }

    /// 优先用 setRedirectUrl 设置的重定向地址，没有则退回 setBaseUrl 设置的地址
    private var effectiveBaseURL: URL? {
        redirectUrl ?? baseUrl.flatMap { URL(string: $0) }
    }

    public func getStringList(_ ruleStr: String?, mContent: Any? = nil, isUrl: Bool = false) -> [String]? {
        guard let ruleStr = ruleStr, !ruleStr.isEmpty else { return nil }
        let ruleList = splitSourceRuleCacheString(ruleStr)
        return getStringList(ruleList, mContent: mContent, isUrl: isUrl)
    }

    public func getStringList(
        _ ruleList: [SourceRule],
        mContent: Any? = nil,
        isUrl: Bool = false
    ) -> [String]? {
        var result: Any? = mContent ?? content
        if result != nil, !ruleList.isEmpty {
            for sourceRule in ruleList {
                putRule(sourceRule.putMap)
                sourceRule.makeUpRule(result)
                guard let cur = result else { continue }
                let rule = sourceRule.rule
                if !rule.isEmpty {
                    switch sourceRule.mode {
                    case .webJs:
                        let s = getWebJsResult(rule, cur)
                        if let data = s.data(using: .utf8),
                           let arr = try? JSONSerialization.jsonObject(with: data) as? [String] {
                            result = arr
                        } else {
                            result = s
                        }
                    case .js:
                        result = evalJS(rule, result: cur)
                    case .json:
                        result = getAnalyzeByJSonPath(cur).getStringList(rule)
                    case .xpath:
                        result = xpathFallbackList(rule)
                    case .css:
                        result = getAnalyzeByJSoup(cur)?.getStringList(rule) ?? []
                    default:
                        result = rule
                    }
                }
                if let arr = result as? [String], !sourceRule.replaceRegex.isEmpty {
                    result = arr.map { replaceRegex($0, sourceRule) }
                } else if let r = result, !sourceRule.replaceRegex.isEmpty {
                    result = replaceRegex("\(r)", sourceRule)
                }
            }
        }
        guard var finalResult = result else { return nil }
        if let s = finalResult as? String {
            finalResult = s.components(separatedBy: "\n")
        }
        if isUrl {
            var urlList: [String] = []
            if let arr = finalResult as? [Any] {
                for u in arr {
                    let abs = Self.absoluteURL(effectiveBaseURL, "\(u)")
                    if !abs.isEmpty, !urlList.contains(abs) { urlList.append(abs) }
                }
            }
            return urlList
        }
        return finalResult as? [String]
    }

    public func getElement(_ ruleStr: String) -> Any? {
        guard !ruleStr.isEmpty else { return nil }
        var result: Any? = content
        let ruleList = splitSourceRule(ruleStr, allInOne: true)
        if result != nil, !ruleList.isEmpty {
            for sourceRule in ruleList {
                putRule(sourceRule.putMap)
                sourceRule.makeUpRule(result)
                guard let cur = result else { continue }
                let rule = sourceRule.rule
                switch sourceRule.mode {
                case .regex:
                    result = AnalyzeByRegex.getElement("\(cur)", splitNotBlank(rule, "&&"))
                case .webJs:
                    let s = getWebJsResult(rule, cur)
                    if let data = s.data(using: .utf8) {
                        result = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                    }
                case .js:
                    result = evalJS(rule, result: cur)
                case .json:
                    result = getAnalyzeByJSonPath(cur).getObject(rule)
                case .xpath:
                    result = xpathFallback(rule)
                default:
                    result = getAnalyzeByJSoup(cur)?.getElements(rule)
                }
                if !sourceRule.replaceRegex.isEmpty, let r = result {
                    result = replaceRegex("\(r)", sourceRule)
                }
            }
        }
        return result
    }

    public func getElements(_ ruleStr: String) -> [Any] {
        var result: Any? = content
        let ruleList = splitSourceRule(ruleStr, allInOne: true)
        if result != nil, !ruleList.isEmpty {
            for sourceRule in ruleList {
                putRule(sourceRule.putMap)
                guard let cur = result else { continue }
                let rule = sourceRule.rule
                switch sourceRule.mode {
                case .regex:
                    result = AnalyzeByRegex.getElements("\(cur)", splitNotBlank(rule, "&&"))
                case .webJs:
                    let s = getWebJsResult(rule, cur)
                    if let data = s.data(using: .utf8) {
                        result = try? JSONSerialization.jsonObject(with: data) as? [Any]
                    }
                case .js:
                    result = evalJS(rule, result: cur)
                case .json:
                    result = getAnalyzeByJSonPath(cur).getList(rule)
                case .xpath:
                    result = xpathFallbackList(rule)
                default:
                    result = getAnalyzeByJSoup(cur)?.getElements(rule).array()
                }
            }
        }
        if let arr = result as? [Any] { return arr }
        return []
    }

    // MARK: - 内部辅助

    private func putRule(_ map: [String: String]) {
        for (key, value) in map {
            put(key, getString(value))
        }
    }

    private func splitNotBlank(_ s: String, _ sep: String) -> [String] {
        s.components(separatedBy: sep).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private func xpathFallback(_ rule: String) -> Any? {
        if !loggedXPathWarning {
            print("⚠️ AnalyzeByXPath 未移植，XPath 规则「\(rule)」暂不生效。多数书源以CSS规则为主，如需完整XPath支持请单独用libxml2实现。")
            loggedXPathWarning = true
        }
        return nil
    }

    private func xpathFallbackList(_ rule: String) -> [Any] {
        _ = xpathFallback(rule)
        return []
    }

    private static func unescapeHTML(_ s: String) -> String {
        var result = s
        let named: [String: String] = [
            "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"",
            "&#39;": "'", "&apos;": "'", "&nbsp;": " ", "&hellip;": "…",
            "&mdash;": "—", "&ndash;": "–", "&ldquo;": "\u{201C}", "&rdquo;": "\u{201D}",
            "&lsquo;": "\u{2018}", "&rsquo;": "\u{2019}", "&copy;": "©", "&reg;": "®"
        ]
        for (k, v) in named {
            result = result.replacingOccurrences(of: k, with: v)
        }
        if result.contains("&#") {
            let pattern = "&#(x[0-9a-fA-F]+|[0-9]+);"
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let ns = result as NSString
                let matches = regex.matches(in: result, range: NSRange(location: 0, length: ns.length))
                var output = ""
                var last = 0
                for m in matches {
                    output += ns.substring(with: NSRange(location: last, length: m.range.location - last))
                    let raw = ns.substring(with: m.range(at: 1))
                    var code: UInt32 = 0
                    if raw.lowercased().hasPrefix("x") {
                        code = UInt32(raw.dropFirst(), radix: 16) ?? 0
                    } else {
                        code = UInt32(raw) ?? 0
                    }
                    if let scalar = UnicodeScalar(code) {
                        output += String(scalar)
                    }
                    last = m.range.location + m.range.length
                }
                output += ns.substring(from: last)
                result = output
            }
        }
        return result
    }

    /// 简化版绝对URL拼接（对应 Kotlin 的 NetworkUtils.getAbsoluteURL）
    private static func absoluteURL(_ base: URL?, _ url: String) -> String {
        let trimmed = url.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return "" }
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") || trimmed.hasPrefix("data:") {
            return trimmed
        }
        if trimmed.hasPrefix("//") { // 协议相对路径，沿用 base 的 scheme
            let scheme = base?.scheme ?? "https"
            return "\(scheme):\(trimmed)"
        }
        guard let base = base, let resolved = URL(string: trimmed, relativeTo: base) else { return trimmed }
        return resolved.absoluteURL.absoluteString
    }
}
