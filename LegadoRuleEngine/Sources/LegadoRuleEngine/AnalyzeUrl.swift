import Foundation
import JavaScriptCore
#if canImport(CoreFoundation)
import CoreFoundation
#endif

/// 对应 legado: model/analyzeRule/AnalyzeUrl.kt
///
/// 范围说明（相对 Kotlin 原版的取舍）：
/// - URL规则语法解析部分（analyzeJs / replaceKeyPageJs / analyzeUrl / UrlOption / 表单编码）
///   是逐段对照 Kotlin **忠实移植**的，这是书源真正特有、离开这份源码很难猜对细节的部分。
/// - 网络执行部分改用 URLSession + async/await 重写（原版是 OkHttp），行为对齐但不是逐行翻译。
/// - 没有移植：Cronet/自定义DNS解析（dnsIp 字段会被解析出来，但当前不生效，iOS 下可以后续用
///   URLSession 的 `proxyConfiguration`/自定义 `URLProtocol` 实现）、WebView渲染获取结果（用
///   `webJsEvaluator` 注入点）、Glide/ExoPlayer 相关的 GlideUrl/MediaItem 封装（图片库/播放器
///   请求时直接用 `url` + `headerMap` 自己构造请求即可，不需要这些 Android 专属封装）。
/// - Cookie：抽成 `CookieStoring` 协议，默认给了一个内存版实现，你可以换成更持久的存储。
/// - 并发限流：`ConcurrentRateLimiter.kt` 原版源码未在本次输入范围内，这里按同等语义（每来源限制
///   同时并发数）写了一个简化版 `SourceRateLimiter`，不是逐行移植。
public final class AnalyzeUrl {

    public enum RequestMethod: String {
        case get = "GET"
        case post = "POST"
        case head = "HEAD"
    }

    // MARK: - 只读结果属性（对应 Kotlin 的 var xxx private set）

    public private(set) var ruleUrl: String = ""
    public private(set) var url: String = ""
    public private(set) var urlNoQuery: String = ""
    public private(set) var type: String?
    public private(set) var headerMap: [String: String] = [:]
    public private(set) var method: RequestMethod = .get
    public private(set) var serverID: Int64?

    private var body: String?
    private var encodedForm: String?
    private var encodedQuery: String?
    private var charset: String?
    private var proxy: String?
    private var retry: Int = 0
    private var useWebView: Bool = false
    private var webJs: String?
    private var bodyJs: String?
    private var dnsIp: String?
    private var webViewDelayTime: Int64 = 0
    private var baseUrl: String

    // MARK: - JS 绑定用的上下文数据

    private let key: String?
    private let page: Int?
    private let speakText: String?
    private let speakSpeed: Int?
    private var infoMap: [String: String]?
    public weak var ruleData: RuleDataInterface?
    public var chapterVariableGet: ((String) -> String)?
    public var chapterVariablePut: ((String, String) -> Void)?

    // MARK: - 可注入扩展点

    /// enabledCookieJar：书源是否启用cookie记忆（对应 source.enabledCookieJar）
    public var enabledCookieJar: Bool = false
    public static var cookieStore: CookieStoring = InMemoryCookieStore.shared
    /// useWebView 命中时（urlOption里 "webView":true）如何取结果，需要注入真实 WKWebView 渲染实现
    public var webViewEvaluator: ((_ url: String, _ headerMap: [String: String], _ js: String?) async throws -> HTTPStrResponse)?
    /// JS 里 java.ajax(url) 用到的网络层，需要注入
    public var ajaxEvaluator: ((_ url: String) -> String?)?
    /// JS 里 java.xxx() 里除 put/get/log 外的能力，可在这里追加
    public var extraJSSetup: ((JSContext) -> Void)?
    /// 书源的公共JS库（BookSource.jsLib），每次 evalJS 都会先跑一遍
    public var jsLib: String?
    /// 书源级别的持久变量 + 登录信息绑定，暴露为JS里的 `this.source`
    public weak var sourceContext: SourceJSContext?
    /// java.toast/longToast
    public var toastHandler: ((_ msg: String) -> Void)?
    /// java.open/showBrowser/startBrowser*
    public var browserOpener: ((_ url: String, _ title: String?) -> Void)?

    private static let paramPattern = try! NSRegularExpression(pattern: "\\s*,\\s*(?=\\{)")
    /// 供 CustomUrl.swift 复用
    static let paramPatternShared = paramPattern
    private static let pagePattern = try! NSRegularExpression(pattern: "<(.*?)>")
    private static let dataUriPattern = try! NSRegularExpression(pattern: "^data:.*?;base64,(.*)")

    public init(
        url mUrl: String,
        key: String? = nil,
        page: Int? = nil,
        speakText: String? = nil,
        speakSpeed: Int? = nil,
        baseUrl: String = "",
        headerMap: [String: String]? = nil,
        ruleData: RuleDataInterface? = nil,
        infoMap: [String: String]? = nil
    ) {
        self.key = key
        self.page = page
        self.speakText = speakText
        self.speakSpeed = speakSpeed
        self.baseUrl = baseUrl
        self.ruleData = ruleData
        self.infoMap = infoMap

        // baseUrl 若本身带 urlOption 后缀（",{...}"），只取前面的地址部分
        let ns = baseUrl as NSString
        if let m = Self.paramPattern.firstMatch(in: baseUrl, range: NSRange(location: 0, length: ns.length)) {
            self.baseUrl = ns.substring(to: m.range.location)
        }
        if let headerMap = headerMap {
            self.headerMap = headerMap
            if let p = self.headerMap["proxy"] {
                self.proxy = p
                self.headerMap.removeValue(forKey: "proxy")
            }
        }
        initUrl(mUrl)
    }

    // MARK: - URL 规则解析主流程

    private func initUrl(_ mUrl: String) {
        ruleUrl = mUrl
        analyzeJs()
        replaceKeyPageJs()
        analyzeUrl()
    }

    /// 执行 URL 规则里嵌入的 <js>...</js> / @js:...，支持用 "@result" 引用当前累积结果
    private func analyzeJs() {
        var start = 0
        let ns = ruleUrl as NSString
        var result = ruleUrl
        let matches = AnalyzeRule.jsPatternShared.matches(in: ruleUrl, range: NSRange(location: 0, length: ns.length))

        for m in matches {
            if m.range.location > start {
                let seg = ns.substring(with: NSRange(location: start, length: m.range.location - start))
                    .trimmingCharacters(in: .whitespaces)
                if !seg.isEmpty {
                    result = seg.replacingOccurrences(of: "@result", with: result)
                }
            }
            let g2 = m.range(at: 2)
            let g1 = m.range(at: 1)
            let jsBody = g2.location != NSNotFound ? ns.substring(with: g2)
                : (g1.location != NSNotFound ? ns.substring(with: g1) : "")
            if let evaluated = evalJS(jsBody, result: result) {
                result = "\(evaluated)"
            }
            start = m.range.location + m.range.length
        }
        if ns.length > start {
            let seg = ns.substring(with: NSRange(location: start, length: ns.length - start))
                .trimmingCharacters(in: .whitespaces)
            if !seg.isEmpty {
                result = seg.replacingOccurrences(of: "@result", with: result)
            }
        }
        ruleUrl = result
    }

    /// 替换 {{js}} 内嵌规则与 <page1,page2,...> 分页规则
    private func replaceKeyPageJs() {
        if ruleUrl.contains("{{"), ruleUrl.contains("}}") {
            let analyzer = RuleAnalyzer(ruleUrl)
            let replaced = analyzer.innerRule(startStr: "{{", endStr: "}}") { js in
                switch self.evalJS(js) {
                case .none:
                    return ""
                case let s as String:
                    return s
                case let d as Double:
                    if d.truncatingRemainder(dividingBy: 1.0) == 0 {
                        return String(format: "%.0f", d)
                    }
                    return "\(d)"
                case let other?:
                    return "\(other)"
                }
            }
            if !replaced.isEmpty { ruleUrl = replaced }
        }

        if let page = page {
            let ns = ruleUrl as NSString
            var searchRange = NSRange(location: 0, length: ns.length)
            while let m = Self.pagePattern.firstMatch(in: ruleUrl, range: searchRange) {
                let whole = ns.substring(with: m.range)
                let inner = ns.substring(with: m.range(at: 1))
                let pages = inner.components(separatedBy: ",")
                let picked: String
                if page - 1 < pages.count, page >= 1 {
                    picked = pages[page - 1].trimmingCharacters(in: .whitespaces)
                } else {
                    picked = (pages.last ?? "").trimmingCharacters(in: .whitespaces)
                }
                ruleUrl = ruleUrl.replacingOccurrences(of: whole, with: picked)
                let newNs = ruleUrl as NSString
                searchRange = NSRange(location: 0, length: newNs.length)
            }
        }
    }

    /// 解析出真正的 url + urlOption(json) + query/form 编码
    private func analyzeUrl() {
        let ns = ruleUrl as NSString
        let full = NSRange(location: 0, length: ns.length)
        let urlNoOption: String
        var optionEnd = ns.length
        if let m = Self.paramPattern.firstMatch(in: ruleUrl, range: full) {
            urlNoOption = ns.substring(to: m.range.location)
            optionEnd = m.range.location + m.range.length
        } else {
            urlNoOption = ruleUrl
        }

        url = NetworkUtils.absoluteURL(baseUrl, urlNoOption)
        if let newBase = NetworkUtils.baseURL(of: url) {
            baseUrl = newBase
        }

        if urlNoOption.count != ruleUrl.count {
            let urlOptionStr = ns.substring(from: optionEnd)
            if let option = UrlOption(jsonString: urlOptionStr) {
                if let m = option.method {
                    switch m.uppercased() {
                    case "POST": method = .post
                    case "HEAD": method = .head
                    default: method = .get
                    }
                }
                for (k, v) in option.headerMap ?? [:] { headerMap[k] = v }
                if let b = option.body { body = b }
                type = option.type
                charset = option.charset
                retry = option.retry ?? 0
                useWebView = option.useWebView ?? false
                webJs = option.webJs
                bodyJs = option.bodyJs
                dnsIp = option.dnsIp
                if let js = option.js, let evaluated = evalJS(js, result: url) {
                    url = "\(evaluated)"
                }
                serverID = option.serverID
                webViewDelayTime = max(0, option.webViewDelayTime ?? 0)
            }
        }

        urlNoQuery = url
        switch method {
        case .post:
            if let b = body,
               !Self.looksLikeJSON(b), !Self.looksLikeXML(b),
               (headerMap["Content-Type"]?.isEmpty ?? true) {
                encodedForm = Self.encodeParams(b, charset: charset, isQuery: false)
            }
        default:
            if let pos = url.firstIndex(of: "?") {
                let query = String(url[url.index(after: pos)...])
                encodedQuery = Self.encodeParams(query, charset: charset, isQuery: true)
                urlNoQuery = String(url[url.startIndex..<pos])
            }
        }
    }

    private static func looksLikeJSON(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return (t.hasPrefix("{") && t.hasSuffix("}")) || (t.hasPrefix("[") && t.hasSuffix("]"))
    }

    private static func looksLikeXML(_ s: String) -> Bool {
        s.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<")
    }

    // MARK: - 表单/query 编码（简化版：统一按 RFC3986 non-alphanumeric 编码，未完全复刻 hutool 的"识别已编码内容"逻辑）

    private static func encodeParams(_ params: String, charset: String?, isQuery: Bool) -> String {
        let enc = charsetEncoding(charset)
        var pairs: [String] = []
        var pos = params.startIndex
        while pos <= params.endIndex {
            let ampRange = params.range(of: "&", range: pos..<params.endIndex)
            let ampEnd = ampRange?.lowerBound ?? params.endIndex
            let eqRange = params.range(of: "=", range: pos..<params.endIndex)

            let key: Substring
            var value: Substring?
            if let eqRange = eqRange, eqRange.lowerBound < ampEnd {
                key = params[pos..<eqRange.lowerBound]
                value = params[params.index(after: eqRange.lowerBound)..<ampEnd]
            } else {
                key = params[pos..<ampEnd]
                value = nil
            }

            var pair = encodeComponent(String(key), enc)
            if let value = value {
                pair += "=" + encodeComponent(String(value), enc)
            }
            pairs.append(pair)

            if ampEnd == params.endIndex { break }
            pos = params.index(after: ampEnd)
        }
        return pairs.joined(separator: "&")
    }

    private static func encodeComponent(_ s: String, _ enc: String.Encoding?) -> String {
        guard let enc = enc else { return s } // charset == "escape" 表示不编码，原样传
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        if enc == .utf8 {
            return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
        }
        // 非UTF-8字符集：转换编码后再按字节百分号编码
        guard let data = s.data(using: enc) else {
            return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
        }
        var out = ""
        for byte in data {
            let scalar = UnicodeScalar(byte)
            let ch = Character(scalar)
            if allowed.contains(scalar) {
                out.append(ch)
            } else {
                out += String(format: "%%%02X", byte)
            }
        }
        return out
    }

    private static func charsetEncoding(_ charset: String?) -> String.Encoding? {
        guard let charset = charset, !charset.isEmpty else { return .utf8 }
        switch charset.lowercased() {
        case "escape": return nil
        case "utf-8", "utf8": return .utf8
        case "gbk", "gb2312", "gb18030":
            let cf = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
            return String.Encoding(rawValue: cf)
        case "big5":
            let cf = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.big5.rawValue))
            return String.Encoding(rawValue: cf)
        case "utf-16", "utf16": return .utf16
        default: return .utf8
        }
    }

    // MARK: - 变量存取（@put/@get，与 AnalyzeRule 一致的语义，转给外部注入的 chapter/ruleData）

    @discardableResult
    public func put(_ key: String, _ value: String) -> String {
        if let putFn = chapterVariablePut {
            putFn(key, value)
        } else {
            ruleData?.variableMap[key] = value
        }
        return value
    }

    public func get(_ key: String) -> String {
        if let getFn = chapterVariableGet {
            let v = getFn(key)
            if !v.isEmpty { return v }
        }
        if let v = ruleData?.variableMap[key], !v.isEmpty { return v }
        return ""
    }

    // MARK: - JS 执行

    @discardableResult
    public func evalJS(_ jsStr: String, result: Any? = nil) -> Any? {
        guard let context = JSContext() else { return nil }
        var errorMsg: String?
        context.exceptionHandler = { _, exception in errorMsg = exception?.toString() }

        let bridge = AnalyzeUrlJSBridge(self)
        context.setObject(bridge, forKeyedSubscript: "java" as NSString)
        context.setObject(SourceJSBridge(sourceContext), forKeyedSubscript: "source" as NSString)
        context.setObject(CookieJSBridge(), forKeyedSubscript: "cookie" as NSString)
        context.setObject(baseUrl, forKeyedSubscript: "baseUrl" as NSString)
        context.setObject(page ?? NSNull(), forKeyedSubscript: "page" as NSString)
        context.setObject(key ?? "", forKeyedSubscript: "key" as NSString)
        context.setObject(speakText ?? "", forKeyedSubscript: "speakText" as NSString)
        context.setObject(speakSpeed ?? NSNull(), forKeyedSubscript: "speakSpeed" as NSString)
        context.setObject(infoMap ?? [:], forKeyedSubscript: "infoMap" as NSString)
        if let result = result {
            context.setObject(result, forKeyedSubscript: "result" as NSString)
        }
        extraJSSetup?(context)

        if let jsLib = jsLib, !jsLib.isEmpty {
            context.evaluateScript(jsLib)
            if errorMsg != nil { errorMsg = nil } // jsLib本身出错不阻断后续脚本执行尝试
        }

        let value = context.evaluateScript(jsStr)
        if let errorMsg = errorMsg {
            print("AnalyzeUrl evalJS 出错: \(errorMsg)\n脚本: \(jsStr)")
            return nil
        }
        return value?.toObject()
    }

    // MARK: - 网络请求执行

    /// 构造好的 URLRequest（GET/HEAD 走 query，POST 走 form/json/自定义 Content-Type）
    public func buildURLRequest() -> URLRequest {
        var comps = URLComponents(string: urlNoQuery)
        if method != .post, let q = encodedQuery, !q.isEmpty {
            comps?.percentEncodedQuery = q
        }
        var request = URLRequest(url: comps?.url ?? URL(string: urlNoQuery) ?? URL(string: "about:blank")!)
        request.httpMethod = method.rawValue

        for (k, v) in headerMap where k.lowercased() != "cookie" {
            request.setValue(v, forHTTPHeaderField: k)
        }

        let domain = NetworkUtils.subDomain(url)
        let cookie = Self.cookieStore.getCookie(domain)
        let headerCookie = headerMap["Cookie"]
        let mergedCookie = Self.mergeCookies(cookie, headerCookie)
        if let mergedCookie = mergedCookie, !mergedCookie.isEmpty {
            request.setValue(mergedCookie, forHTTPHeaderField: "Cookie")
        }

        if method == .post {
            if let form = encodedForm, !form.isEmpty {
                request.httpBody = form.data(using: .utf8)
                if headerMap["Content-Type"] == nil {
                    request.setValue("application/x-www-form-urlencoded;charset=UTF-8", forHTTPHeaderField: "Content-Type")
                }
            } else if let body = body, !body.isEmpty {
                request.httpBody = body.data(using: .utf8)
                if let contentType = headerMap["Content-Type"] {
                    request.setValue(contentType, forHTTPHeaderField: "Content-Type")
                } else {
                    request.setValue("application/json;charset=UTF-8", forHTTPHeaderField: "Content-Type")
                }
            }
        }
        return request
    }

    /// 发起请求，返回字符串响应。webView 分支需要通过 `webViewEvaluator` 注入实现，否则会抛错。
    public func getStrResponse() async throws -> HTTPStrResponse {
        if let dataBytes = dataURIBytes() {
            return HTTPStrResponse(url: url, body: String(data: dataBytes, encoding: .utf8), statusCode: 200, headers: [:], callTimeMs: 0)
        }

        if useWebView {
            guard let evaluator = webViewEvaluator else {
                throw AnalyzeUrlError.webViewNotConfigured
            }
            return try await evaluator(url, headerMap, webJs)
        }

        let start = Date()
        let request = buildURLRequest()
        var attempt = 0
        var lastError: Error?

        while attempt <= retry {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                let http = response as? HTTPURLResponse
                var text = String(data: data, encoding: Self.responseEncoding(from: http, fallback: charset)) ?? ""

                if let bodyJs = bodyJs {
                    if let evaluated = evalJS(bodyJs, result: text) {
                        text = "\(evaluated)"
                    }
                }

                let callTime = Int(Date().timeIntervalSince(start) * 1000)
                var headers: [String: String] = [:]
                for (k, v) in http?.allHeaderFields ?? [:] {
                    headers["\(k)"] = "\(v)"
                }
                return HTTPStrResponse(
                    url: response.url?.absoluteString ?? url,
                    body: text,
                    statusCode: http?.statusCode ?? 0,
                    headers: headers,
                    callTimeMs: callTime
                )
            } catch {
                lastError = error
                attempt += 1
            }
        }
        throw lastError ?? URLError(.unknown)
    }

    /// 只取字节（用于图片/音频等二进制资源）
    public func getData() async throws -> Data {
        if let bytes = dataURIBytes() { return bytes }
        let request = buildURLRequest()
        let (data, _) = try await URLSession.shared.data(for: request)
        return data
    }

    private func dataURIBytes() -> Data? {
        guard urlNoQuery.hasPrefix("data:") else { return nil }
        let ns = urlNoQuery as NSString
        guard let m = Self.dataUriPattern.firstMatch(in: urlNoQuery, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let base64 = ns.substring(with: m.range(at: 1))
        return Data(base64Encoded: base64)
    }

    private static func responseEncoding(from response: HTTPURLResponse?, fallback: String?) -> String.Encoding {
        if let ct = response?.allHeaderFields["Content-Type"] as? String,
           let range = ct.range(of: "charset=", options: .caseInsensitive) {
            let cs = ct[range.upperBound...].trimmingCharacters(in: .whitespaces)
            if let enc = charsetEncoding(cs) { return enc }
        }
        return charsetEncoding(fallback) ?? .utf8
    }

    private static func mergeCookies(_ a: String, _ b: String?) -> String? {
        guard let b = b, !b.isEmpty else { return a.isEmpty ? nil : a }
        if a.isEmpty { return b }
        var seen: [String: String] = [:]
        var order: [String] = []
        for part in (a + ";" + b).components(separatedBy: ";") {
            let kv = part.trimmingCharacters(in: .whitespaces)
            guard !kv.isEmpty else { continue }
            let name = kv.split(separator: "=", maxSplits: 1).first.map(String.init) ?? kv
            if seen[name] == nil { order.append(name) }
            seen[name] = kv
        }
        return order.compactMap { seen[$0] }.joined(separator: "; ")
    }
}

// MARK: - 结果类型

public struct HTTPStrResponse {
    public let url: String
    public let body: String?
    public let statusCode: Int
    public let headers: [String: String]
    public let callTimeMs: Int
}

public enum AnalyzeUrlError: Error {
    case webViewNotConfigured
}

// MARK: - Cookie 存取协议

public protocol CookieStoring {
    func getCookie(_ domain: String) -> String
    func setCookie(_ domain: String, _ cookie: String)
}

/// 默认内存版 Cookie 存储，仅供跑通流程用。生产环境建议换成基于文件/数据库的持久化实现。
public final class InMemoryCookieStore: CookieStoring {
    public static let shared = InMemoryCookieStore()
    private var store: [String: String] = [:]
    private let lock = NSLock()

    public func getCookie(_ domain: String) -> String {
        lock.lock(); defer { lock.unlock() }
        return store[domain] ?? ""
    }

    public func setCookie(_ domain: String, _ cookie: String) {
        lock.lock(); defer { lock.unlock() }
        store[domain] = cookie
    }
}

// MARK: - UrlOption：",{...}" 后缀的 JSON 参数

struct UrlOption {
    var method: String?
    var charset: String?
    var headerMap: [String: String]?
    var body: String?
    var retry: Int?
    var type: String?
    var useWebView: Bool?
    var webJs: String?
    var dnsIp: String?
    var js: String?
    var bodyJs: String?
    var serverID: Int64?
    var webViewDelayTime: Int64?

    init?(jsonString: String) {
        guard let data = jsonString.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        method = obj["method"] as? String
        charset = obj["charset"] as? String
        type = obj["type"] as? String
        webJs = obj["webJs"] as? String
        dnsIp = obj["dnsIp"] as? String
        js = obj["js"] as? String
        bodyJs = obj["bodyJs"] as? String

        if let r = obj["retry"] { retry = Self.asInt(r) }
        if let s = obj["serverID"] { serverID = Self.asInt64(s) }
        if let w = obj["webViewDelayTime"] { webViewDelayTime = Self.asInt64(w) }

        switch obj["webView"] {
        case nil, is NSNull:
            useWebView = false
        case let b as Bool:
            useWebView = b
        case let s as String:
            useWebView = !(s.isEmpty || s.lowercased() == "false")
        default:
            useWebView = true
        }

        if let h = obj["headers"] as? [String: Any] {
            var m: [String: String] = [:]
            for (k, v) in h { m[k] = "\(v)" }
            headerMap = m
        } else if let h = obj["headers"] as? String,
                  let hd = h.data(using: .utf8),
                  let ho = try? JSONSerialization.jsonObject(with: hd) as? [String: Any] {
            var m: [String: String] = [:]
            for (k, v) in ho { m[k] = "\(v)" }
            headerMap = m
        }

        switch obj["body"] {
        case let s as String:
            body = s
        case .some(let other):
            if JSONSerialization.isValidJSONObject(other),
               let bd = try? JSONSerialization.data(withJSONObject: other) {
                body = String(data: bd, encoding: .utf8)
            }
        default:
            break
        }
    }

    private static func asInt(_ v: Any) -> Int? {
        if let i = v as? Int { return i }
        if let d = v as? Double { return Int(d) }
        if let s = v as? String { return Int(s) }
        return nil
    }

    private static func asInt64(_ v: Any) -> Int64? {
        if let i = v as? Int64 { return i }
        if let i = v as? Int { return Int64(i) }
        if let d = v as? Double { return Int64(d) }
        if let s = v as? String { return Int64(s) }
        return nil
    }
}

// MARK: - JS 桥接（java.put/get/log 等，与 LegadoJSBridge 同一套方法面，实现委托给 JSCommonMethods）

@objc protocol AnalyzeUrlJSBridgeExport: JSExport {
    func put(_ key: String, _ value: String) -> String
    func get(_ key: String) -> String
    func log(_ msg: String) -> String
    func ajax(_ url: String) -> String?
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
    func open(_ action: String, _ url: String?, _ title: String?) -> String
    func showBrowser(_ url: String, _ title: String?) -> String
    func startBrowser(_ url: String, _ title: String?) -> String
    func qread() -> String
}

@objc final class AnalyzeUrlJSBridge: NSObject, AnalyzeUrlJSBridgeExport {
    weak var owner: AnalyzeUrl?
    init(_ owner: AnalyzeUrl) { self.owner = owner }

    func put(_ key: String, _ value: String) -> String {
        owner?.put(key, value) ?? value
    }
    func get(_ key: String) -> String {
        owner?.get(key) ?? ""
    }
    func ajax(_ url: String) -> String? {
        owner?.ajaxEvaluator?(url)
    }
    func base64Encode(_ s: String) -> String { JSCommonMethods.base64Encode(s) }
    func base64Decode(_ s: String) -> String { JSCommonMethods.base64Decode(s) }
    func base64DecodeToByteArray(_ s: String) -> [Int] { JSCommonMethods.base64DecodeToByteArray(s) }
    func hexDecodeToString(_ hex: String) -> String { JSCommonMethods.hexDecodeToString(hex) }
    func timeFormat(_ millis: Double) -> String { JSCommonMethods.timeFormat(millis) }
    func toast(_ msg: String) -> String {
        print("[toast] \(msg)"); owner?.toastHandler?(msg); return msg
    }
    func longToast(_ msg: String) -> String {
        print("[longToast] \(msg)"); owner?.toastHandler?(msg); return msg
    }
    func androidId() -> String { JSCommonMethods.deviceIdentifier }
    func deviceID() -> String { JSCommonMethods.deviceIdentifier }
    func getWebViewUA() -> String { JSCommonMethods.defaultUserAgent }
    func createSymmetricCrypto(_ transformation: String, _ key: String, _ iv: String) -> SymmetricCryptoJSBridge? {
        SymmetricCryptoJSBridge(transformation: transformation, key: key, iv: iv)
    }
    func open(_ action: String, _ url: String?, _ title: String?) -> String {
        if let url = url { owner?.browserOpener?(url, title) }
        return ""
    }
    func showBrowser(_ url: String, _ title: String?) -> String {
        owner?.browserOpener?(url, title); return ""
    }
    func startBrowser(_ url: String, _ title: String?) -> String {
        owner?.browserOpener?(url, title); return ""
    }
    func qread() -> String { "0" }
    func log(_ msg: String) -> String {
        print("[URL规则日志] \(msg)")
        return msg
    }
}

// MARK: - 简化版 NetworkUtils

enum NetworkUtils {
    static func absoluteURL(_ base: String, _ urlStr: String) -> String {
        let u = urlStr.trimmingCharacters(in: .whitespaces)
        if u.isEmpty { return base }
        if u.hasPrefix("http://") || u.hasPrefix("https://") || u.hasPrefix("data:") { return u }
        if u.hasPrefix("//") {
            let scheme = URL(string: base)?.scheme ?? "https"
            return "\(scheme):\(u)"
        }
        guard let baseURL = URL(string: base), let resolved = URL(string: u, relativeTo: baseURL) else {
            return u
        }
        return resolved.absoluteURL.absoluteString
    }

    static func baseURL(of urlStr: String) -> String? {
        guard let url = URL(string: urlStr), let scheme = url.scheme, let host = url.host else { return nil }
        if let port = url.port { return "\(scheme)://\(host):\(port)/" }
        return "\(scheme)://\(host)/"
    }

    /// 简化：直接用 host 作为 cookie 存取的分域 key（原版按二级域名分组，这里从简）
    static func subDomain(_ urlOrKey: String) -> String {
        if let url = URL(string: urlOrKey), let host = url.host { return host }
        return urlOrKey
    }
}

// MARK: - 简化版并发限流（非逐行移植，语义等价：限制某个来源同时进行中的请求数）

public actor SourceRateLimiter {
    public static let shared = SourceRateLimiter()

    private var inFlight: [String: Int] = [:]
    private var requestTimes: [String: [Date]] = [:]

    public init() {}

    /// 简单并发数限制：同一个key最多同时有 maxConcurrent 个请求在跑
    public func withLimit<T>(_ key: String, maxConcurrent: Int = 1, _ block: () async throws -> T) async rethrows -> T {
        while (inFlight[key] ?? 0) >= maxConcurrent {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        inFlight[key, default: 0] += 1
        defer { inFlight[key, default: 1] -= 1 }
        return try await block()
    }

    /// 按时间窗口限流：解析书源 `concurrentRate` 字段（形如 "1/1000" 表示1000ms内最多1个请求，
    /// 纯数字 "3" 表示只限并发数不限时间间隔），达到上限就异步等到窗口腾出空位再放行。
    /// 在发起真正的网络请求前调用一次即可，不需要包一层闭包。
    public func acquire(key: String, concurrentRate: String?) async {
        guard let rate = concurrentRate, !rate.isEmpty else { return }
        let parts = rate.split(separator: "/")
        guard let count = Int(parts[0].trimmingCharacters(in: .whitespaces)), count > 0 else { return }

        guard parts.count > 1, let windowMs = Int(parts[1].trimmingCharacters(in: .whitespaces)), windowMs > 0 else {
            // 只有数量、没有时间窗口：退化成简单并发数限制
            while (inFlight[key] ?? 0) >= count {
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
            inFlight[key, default: 0] += 1
            return
        }

        while true {
            let now = Date()
            let windowStart = now.addingTimeInterval(-Double(windowMs) / 1000.0)
            var times = (requestTimes[key] ?? []).filter { $0 > windowStart }
            if times.count < count {
                times.append(now)
                requestTimes[key] = times
                return
            }
            let oldest = times.first ?? now
            let waitSeconds = max(0.01, oldest.timeIntervalSince(windowStart))
            try? await Task.sleep(nanoseconds: UInt64(waitSeconds * 1_000_000_000))
        }
    }

    /// 配合 acquire(key:concurrentRate:) 使用：若走的是"只限并发数"分支，请求结束后调用释放占用
    public func release(key: String) {
        if let n = inFlight[key], n > 0 {
            inFlight[key] = n - 1
        }
    }
}
