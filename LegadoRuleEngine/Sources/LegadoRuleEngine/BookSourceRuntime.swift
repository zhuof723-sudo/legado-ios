import Foundation

/// 把 `BookSource` + `AnalyzeUrl` + `AnalyzeRule` 串起来的胶水层：
/// 搜索 → 目录 → 正文 三步，并对齐 legado 原版的若干行为（目录倒序/去重/空链接兜底）。
/// 每一步都写引擎日志，方便定位"搜得到但打不开"的问题。
public struct ExploreKindInfo: Identifiable, Equatable, Codable, Sendable {
    public let title: String
    public let url: String
    public let type: String
    public var id: String { title + "|" + url }

    public init(title: String, url: String, type: String = "url") {
        self.title = title
        self.url = url
        self.type = type
    }
}

public struct SearchResult: Codable, Sendable {
    public let name: String
    public let author: String
    public let intro: String
    public let kind: String
    public let lastChapter: String
    public let bookUrl: String
    public let coverUrl: String
    public let wordCount: String
}

public struct ChapterInfo: Equatable {
    public let name: String
    public let url: String

    public init(name: String, url: String) {
        self.name = name
        self.url = url
    }
}

/// 书籍详情信息（ruleBookInfo 解析结果）
public struct BookInfo {
    public let name: String
    public let author: String
    public let intro: String
    public let coverUrl: String
    public let kind: String
    public let tocUrl: String

    public init(name: String = "", author: String = "", intro: String = "",
                coverUrl: String = "", kind: String = "", tocUrl: String = "") {
        self.name = name
        self.author = author
        self.intro = intro
        self.coverUrl = coverUrl
        self.kind = kind
        self.tocUrl = tocUrl
    }
}

public final class BookSourceRuntime {
    public var source: BookSource

    public var sourceContext: SourceJSContext?
    public var toastHandler: ((_ msg: String) -> Void)?
    public var browserOpener: ((_ url: String, _ title: String?) -> Void)?
    public var browserOpenerAdvanced: ((_ url: String, _ title: String?, _ injectJs: String?, _ optsJson: String?) -> Void)?
    public var refreshExploreHandler: (() -> Void)?
    public var searchBookHandler: ((_ keyword: String, _ sourceFilter: String?) -> Void)?
    /// 书源级 KV（cache.put / cache.get / java.put / java.get 的数据后端）
    public var sourceKeyValueStore: SourceKeyValueStore?
    private var resolvedHeaderCache: [String: String]?

    public init(_ source: BookSource) {
        self.source = source
        self.sourceKeyValueStore = UserDefaultsKeyValueStore(namespace: source.bookSourceUrl)
        self.sourceContext = nil
        self.sourceContext = RuntimeSourceJSContext(owner: self)
    }

    // MARK: - 构造

    func makeAnalyzeUrl(_ urlRule: String, key: String? = nil, page: Int? = nil, bookUrl: String? = nil) -> AnalyzeUrl {
        let au = AnalyzeUrl(
            url: urlRule,
            key: key,
            page: page,
            baseUrl: source.bookSourceUrl,
            headerMap: resolveHeaderMap(),
            deferInitialization: true
        )
        au.jsLib = source.jsLib
        au.sourceContext = sourceContext
        au.bookUrl = bookUrl
        au.sourceKey = source.bookSourceUrl
        au.presentsDeviceIdentity = source.presentsAndroidIdentity
        au.enabledCookieJar = source.enabledCookieJar ?? true
        au.ajaxEvaluator = { [weak self] url in self?.blockingAjax(url) }
        au.ajaxEvaluatorWithOptions = { [weak self] url, opts in self?.blockingAjaxWithOptions(url, opts) }
        au.ajaxAllEvaluator = { [weak self] urls in self?.blockingAjaxAll(urls) ?? [] }
        au.postEvaluator = { [weak self] url, body, headers in self?.blockingPost(url, body, headers) }
        au.loginInfoWriter = { [weak self] info in self?.persistLoginInfo(info) }
        au.chapterVariableGet = { [weak self] key in self?.sourceKeyValueStore?.get(key) ?? "" }
        au.chapterVariablePut = { [weak self] key, value in self?.sourceKeyValueStore?.put(key, value) }
        au.toastHandler = toastHandler
        au.browserOpener = browserOpener
        au.keyValueStore = sourceKeyValueStore
        au.initializeDeferred()
        return au
    }

    func makeAnalyzeRule() -> AnalyzeRule {
        let rule = AnalyzeRule()
        rule.jsLib = source.jsLib
        rule.sourceContext = sourceContext
        rule.sourceKey = source.bookSourceUrl
        rule.presentsDeviceIdentity = source.presentsAndroidIdentity
        rule.ajaxEvaluator = { [weak self] url in self?.blockingAjax(url) }
        rule.ajaxEvaluatorWithOptions = { [weak self] url, opts in self?.blockingAjaxWithOptions(url, opts) }
        rule.ajaxAllEvaluator = { [weak self] urls in self?.blockingAjaxAll(urls) ?? [] }
        rule.postEvaluator = { [weak self] url, body, headers in self?.blockingPost(url, body, headers) }
        rule.loginInfoWriter = { [weak self] info in self?.persistLoginInfo(info) }
        rule.sourceGet = { [weak self] key in self?.sourceKeyValueStore?.get(key) }
        rule.sourcePut = { [weak self] key, value in self?.sourceKeyValueStore?.put(key, value) }
        rule.toastHandler = toastHandler
        rule.browserOpener = browserOpener
        rule.refreshExploreHandler = refreshExploreHandler
        rule.searchBookHandler = searchBookHandler
        rule.keyValueStore = sourceKeyValueStore
        return rule
    }

    /// 解析请求头
    public func resolveHeaderMap() -> [String: String] {
        if let cached = resolvedHeaderCache { return cached }
        var result: [String: String] = [:]
        guard let header = source.header else {
            if let h = source.loginHeader, !h.isEmpty { result["Authorization"] = h }
            resolvedHeaderCache = result
            return result
        }
        let trimmed = header.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            let isJS = trimmed.lowercased().hasPrefix("@js:") || trimmed.lowercased().hasPrefix("<js>")
            if isJS {
                var jsBody = trimmed
                if jsBody.lowercased().hasPrefix("@js:") {
                    jsBody = String(jsBody.dropFirst(4))
                } else {
                    jsBody = jsBody
                        .replacingOccurrences(of: "<js>", with: "", options: [.caseInsensitive])
                        .replacingOccurrences(of: "</js>", with: "", options: [.caseInsensitive])
                }
                let rule = makeAnalyzeRule()
                rule.setBaseUrl(source.bookSourceUrl)
                if let evaluated = rule.evalJS(jsBody) {
                    let str = "\(evaluated)"
                    if let data = str.data(using: .utf8),
                       let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        for (k, v) in obj { result[k] = "\(v)" }
                    }
                }
            } else if let obj = source.parsedHeaderMap() as [String: String]? {
                for (k, v) in obj { result[k] = v }
            }
        }
        // 如果有 loginHeader（来源：source.putLoginHeader），默认作为 Authorization 头带上
        if let h = source.loginHeader, !h.isEmpty, result["Authorization"] == nil {
            result["Authorization"] = h
        }
        resolvedHeaderCache = result
        return result
    }

    private func blockingAjax(_ urlString: String) -> String? {
        guard let url = URL(string: urlString) else { return nil }
        let semaphore = DispatchSemaphore(value: 0)
        var resultText: String?
        var request = URLRequest(url: url)
        for (k, v) in resolveHeaderMap() { request.setValue(v, forHTTPHeaderField: k) }
        if let host = url.host {
            let cookie = AnalyzeUrl.cookieStore.getCookie(host)
            if !cookie.isEmpty { request.setValue(cookie, forHTTPHeaderField: "Cookie") }
        }
        let task = URLSession.shared.dataTask(with: request) { data, response, _ in
            if let data = data {
                if let utf8 = String(data: data, encoding: .utf8) {
                    resultText = utf8
                } else {
                    let gb = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
                    resultText = String(data: data, encoding: String.Encoding(rawValue: gb))
                }
            }
            if let http = response as? HTTPURLResponse,
               let setCookie = http.value(forHTTPHeaderField: "Set-Cookie"),
               let host = url.host, !setCookie.isEmpty {
                AnalyzeUrl.cookieStore.setCookie(host, setCookie)
            }
            semaphore.signal()
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 30)
        return resultText
    }

    /// 同步阻塞版带 options 的 HTTP 请求。options 支持：
    /// - method: "GET" | "POST" | "PUT" | ...
    /// - body: String（body 体）
    /// - headers: [String: String]
    /// - timeout: Double 秒
    func blockingAjaxWithOptions(_ urlString: String, _ options: [String: Any]) -> JSStrResponse? {
        guard let url = URL(string: urlString) else { return nil }
        let semaphore = DispatchSemaphore(value: 0)
        var resultText = ""
        var resultURL = urlString
        var request = URLRequest(url: url)
        let method = (options["method"] as? String)?.uppercased() ?? "GET"
        request.httpMethod = method
        if let body = options["body"] as? String {
            request.httpBody = body.data(using: .utf8)
            if request.value(forHTTPHeaderField: "Content-Type") == nil {
                request.setValue("application/x-www-form-urlencoded;charset=UTF-8",
                                 forHTTPHeaderField: "Content-Type")
            }
        } else if let body = options["body"], !(body is NSNull),
                  JSONSerialization.isValidJSONObject(body),
                  let data = try? JSONSerialization.data(withJSONObject: body) {
            request.httpBody = data
            request.setValue("application/json;charset=UTF-8", forHTTPHeaderField: "Content-Type")
        }
        for (k, v) in resolveHeaderMap() { request.setValue(v, forHTTPHeaderField: k) }
        if let extraHeaders = options["headers"] as? [String: Any] {
            for (k, v) in extraHeaders {
                let value = "\(v)"
                // 空的设备标识表示系统没有提供 identifierForVendor，此时不发该请求头。
                if k.caseInsensitiveCompare("X-Device-Id") == .orderedSame && value.isEmpty { continue }
                request.setValue(value, forHTTPHeaderField: k)
            }
        }
        if let host = url.host {
            let cookie = AnalyzeUrl.cookieStore.getCookie(host)
            if !cookie.isEmpty { request.setValue(cookie, forHTTPHeaderField: "Cookie") }
        }
        let rawTimeout: TimeInterval = (options["timeout"] as? Double)
            ?? (options["timeout"] as? Int).map { Double($0) }
            ?? 30
        // legado 规则通常以毫秒表示（如 10000），URLSession 使用秒。
        let normalizedTimeout = rawTimeout > 300 ? rawTimeout / 1000 : rawTimeout
        let timeout = min(max(normalizedTimeout, 1), 120)
        request.timeoutInterval = timeout

        let task = URLSession.shared.dataTask(with: request) { data, response, _ in
            if let data = data {
                if let utf8 = String(data: data, encoding: .utf8) {
                    resultText = utf8
                } else {
                    let gb = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
                    resultText = String(data: data, encoding: String.Encoding(rawValue: gb)) ?? ""
                }
            }
            if let http = response as? HTTPURLResponse {
                resultURL = http.url?.absoluteString ?? resultURL
                if let setCookie = http.value(forHTTPHeaderField: "Set-Cookie"),
                   let host = url.host, !setCookie.isEmpty {
                    AnalyzeUrl.cookieStore.setCookie(host, setCookie)
                }
            }
            semaphore.signal()
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + timeout + 5)
        return JSStrResponse(body: resultText, url: resultURL)
    }

    /// 同步并发批量请求，js.ajaxAll(urls) 用。返回每条响应的 body 字符串列表（顺序与输入一致）。
    func blockingAjaxAll(_ urls: [String]) -> [JSStrResponse] {
        urls.compactMap { blockingAjaxWithOptions($0, [:]) }
    }

    /// 同步阻塞版 POST，供 JS 里 java.post(url, body, headers) 调用
    private func blockingPost(_ urlString: String, _ body: String, _ headers: [String: String]) -> JSStrResponse? {
        guard let url = URL(string: urlString) else { return nil }
        let semaphore = DispatchSemaphore(value: 0)
        var resultText: String?
        var resultURL = urlString
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body.data(using: .utf8)
        if request.value(forHTTPHeaderField: "Content-Type") == nil {
            request.setValue("application/x-www-form-urlencoded;charset=UTF-8", forHTTPHeaderField: "Content-Type")
        }
        for (k, v) in resolveHeaderMap() { request.setValue(v, forHTTPHeaderField: k) }
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        if let host = url.host {
            let cookie = AnalyzeUrl.cookieStore.getCookie(host)
            if !cookie.isEmpty { request.setValue(cookie, forHTTPHeaderField: "Cookie") }
        }
        let task = URLSession.shared.dataTask(with: request) { data, response, _ in
            if let data = data {
                if let utf8 = String(data: data, encoding: .utf8) {
                    resultText = utf8
                } else {
                    let gb = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
                    resultText = String(data: data, encoding: String.Encoding(rawValue: gb))
                }
            }
            if let http = response as? HTTPURLResponse {
                resultURL = http.url?.absoluteString ?? resultURL
                if let setCookie = http.value(forHTTPHeaderField: "Set-Cookie"),
                   let host = url.host, !setCookie.isEmpty {
                    AnalyzeUrl.cookieStore.setCookie(host, setCookie)
                }
            }
            semaphore.signal()
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 30)
        return JSStrResponse(body: resultText ?? "", url: resultURL)
    }

    // MARK: - 登录信息持久化

    /// 把 JS 里 source.putLoginInfo() 写回应用层持久化（应用层实现 SourceJSContext）
    public func persistLoginInfo(_ info: [String: String]) {
        source.loginInfoMap = info
        loginInfoPersister?(info)
    }

    /// JS 里登录面板按钮 action 触发的回调（如 login()、user_logout()、key()）
    public func handleLoginAction(_ action: String, _ info: [String: String]) {
        source.loginInfoMap = info
        loginActionHandler?(action, info)
    }

    /// 应用层注入：把登录表单持久化到 SwiftData 等
    public var loginInfoPersister: ((_ info: [String: String]) -> Void)?
    /// 应用层注入：登录动作执行（在登录面板里跑对应 JS 函数）
    public var loginActionHandler: ((_ action: String, _ info: [String: String]) -> Void)?

    // MARK: - 搜索

    public func search(_ keyword: String, page: Int = 1, resultLimit: Int = 200) async throws -> [SearchResult] {
        guard let searchUrlRule = source.searchUrl, let rule = source.ruleSearch,
              let listRule = rule.bookList else {
            EngineLogger.log("书源缺少 searchUrl 或 ruleSearch.bookList，无法搜索", tag: source.bookSourceName, level: .warn)
            return []
        }

        let au = makeAnalyzeUrl(searchUrlRule, key: keyword, page: page)
        EngineLogger.log("搜索请求: \(au.ruleUrl)", tag: source.bookSourceName)
        await SourceRateLimiter.shared.acquire(key: source.bookSourceUrl, concurrentRate: source.concurrentRate)
        let resp = try await au.getStrResponse()
        guard let body = resp.body else {
            EngineLogger.log("搜索响应为空", tag: source.bookSourceName, level: .error)
            return []
        }
        EngineLogger.log("搜索响应 \(body.count) 字节 · 重定向 \(resp.url)", tag: source.bookSourceName)

        let analyzeRule = makeAnalyzeRule()
        analyzeRule.setContent(body, baseUrl: resp.url.isEmpty ? au.url : resp.url)

        let items = analyzeRule.getElements(listRule)
        EngineLogger.log("列表规则命中 \(items.count) 项", tag: source.bookSourceName)
        let safeLimit = max(1, resultLimit)
        let parseItems = items.prefix(safeLimit)
        if items.count > safeLimit {
            EngineLogger.log("搜索结果过多，仅解析前 \(safeLimit) 项，省略 \(items.count - safeLimit) 项", tag: source.bookSourceName, level: .warn)
        }

        return parseItems.compactMap { item -> SearchResult? in
            autoreleasepool {
                var bookUrl = analyzeRule.getString(rule.bookUrl, mContent: item, isUrl: true)
                if bookUrl.isEmpty { bookUrl = resp.url.isEmpty ? au.url : resp.url }   // 空详情链接兜底
                let name = analyzeRule.getString(rule.name, mContent: item)
                if name.isEmpty { return nil }
                return SearchResult(
                    name: name,
                    author: analyzeRule.getString(rule.author, mContent: item),
                    intro: stripHTML(analyzeRule.getString(rule.intro, mContent: item)),
                    kind: analyzeRule.getString(rule.kind, mContent: item),
                    lastChapter: analyzeRule.getString(rule.lastChapter, mContent: item),
                    bookUrl: bookUrl,
                    coverUrl: analyzeRule.getString(rule.coverUrl, mContent: item, isUrl: true),
                    wordCount: analyzeRule.getString(rule.wordCount, mContent: item)
                )
            }
        }
    }

    // MARK: - 目录

    public func getToc(
        bookUrl: String,
        maxPages: Int = 50,
        resolvedTocUrl: String? = nil
    ) async throws -> [ChapterInfo] {
        guard let rule = source.ruleToc else {
            EngineLogger.log("书源缺少 ruleToc", tag: source.bookSourceName, level: .warn)
            return []
        }
        var listRule = rule.chapterList ?? ""
        guard !listRule.isEmpty else {
            EngineLogger.log("书源缺少 ruleToc.chapterList", tag: source.bookSourceName, level: .warn)
            return []
        }
        var reverse = false
        if listRule.hasPrefix("-") { reverse = true; listRule = String(listRule.dropFirst()) }
        else if listRule.hasPrefix("+") { listRule = String(listRule.dropFirst()) }

        // 目录地址已由详情阶段解析时直接复用；否则只做轻量详情解析。
        var tocUrl = (resolvedTocUrl?.isEmpty == false) ? resolvedTocUrl! : bookUrl
        if resolvedTocUrl?.isEmpty != false,
           let tocRule = source.ruleBookInfo?.tocUrl, !tocRule.isEmpty {
            let info = try await getBookInfo(bookUrl: bookUrl, lightweight: true)
            if !info.tocUrl.isEmpty {
                tocUrl = info.tocUrl
                EngineLogger.log("详情页解析出目录地址: \(tocUrl)", tag: source.bookSourceName)
            }
        }

        if let nativeChapters = try await getSusanToc(tocUrl: tocUrl) {
            EngineLogger.log("书山原生目录解析完成，共 \(nativeChapters.count) 章", tag: source.bookSourceName)
            return nativeChapters
        }

        var chapters: [ChapterInfo] = []
        var visited: Set<String> = []
        var currentUrl: String? = tocUrl
        var pageCount = 0

        while let url = currentUrl, pageCount < maxPages, !visited.contains(url) {
            visited.insert(url)
            pageCount += 1

            let au = makeAnalyzeUrl(url, bookUrl: bookUrl)
            EngineLogger.log("目录请求: \(au.ruleUrl)", tag: source.bookSourceName)
            await SourceRateLimiter.shared.acquire(key: source.bookSourceUrl, concurrentRate: source.concurrentRate)
            let resp = try await au.getStrResponse()
            guard let body = resp.body else {
                EngineLogger.log("目录响应为空: \(url)", tag: source.bookSourceName, level: .error)
                break
            }
            let baseUrl = resp.url.isEmpty ? au.url : resp.url

            let analyzeRule = makeAnalyzeRule()
            analyzeRule.bookUrl = bookUrl
            analyzeRule.setContent(body, baseUrl: baseUrl)

            let items = analyzeRule.getElements(listRule)
            EngineLogger.log("目录第 \(pageCount) 页命中 \(items.count) 章", tag: source.bookSourceName)

            for item in items {
                // 每个章节项是 JS 返回的 JSON 对象：设为当前内容，让 chapterName/chapterUrl 按 JSON 字段取值
                analyzeRule.setContent(item)
                let name = analyzeRule.getString(rule.chapterName)
                var chapterUrl = analyzeRule.getString(rule.chapterUrl, isUrl: true)
                if chapterUrl.isEmpty { chapterUrl = baseUrl }   // 空章节链接兜底
                if !name.isEmpty { chapters.append(ChapterInfo(name: name, url: chapterUrl)) }
            }

            if let nextRule = rule.nextTocUrl, !nextRule.isEmpty {
                let next = analyzeRule.getString(nextRule, isUrl: true)
                currentUrl = (next.isEmpty || visited.contains(next)) ? nil : next
            } else {
                currentUrl = nil
            }
        }

        if !reverse { chapters.reverse() }
        // 去重（按 url，保留先出现的）
        var seen = Set<String>()
        chapters = chapters.filter { seen.insert($0.url.isEmpty ? $0.name : $0.url).inserted }
        EngineLogger.log("目录共 \(chapters.count) 章", tag: source.bookSourceName)
        return chapters
    }

    // MARK: - 详情页（ruleBookInfo）

    public func getBookInfo(bookUrl: String, lightweight: Bool = false) async throws -> BookInfo {
        if let native = try await getSusanBookInfo(bookUrl: bookUrl, lightweight: lightweight) {
            return native
        }
        guard let rule = source.ruleBookInfo else {
            return BookInfo(tocUrl: "")
        }
        let au = makeAnalyzeUrl(bookUrl, bookUrl: bookUrl)
        EngineLogger.log("详情请求: \(au.ruleUrl)", tag: source.bookSourceName)
        await SourceRateLimiter.shared.acquire(key: source.bookSourceUrl, concurrentRate: source.concurrentRate)
        let resp = try await au.getStrResponse()
        guard let body = resp.body else {
            EngineLogger.log("详情响应为空", tag: source.bookSourceName, level: .error)
            return BookInfo(tocUrl: "")
        }
        let baseUrl = resp.url.isEmpty ? au.url : resp.url
        let analyzeRule = makeAnalyzeRule()
        analyzeRule.bookUrl = bookUrl
        analyzeRule.setContent(body, baseUrl: baseUrl)

        // 对齐原版 BookInfo.analyzeBookInfo：先执行 init，再把结果设为详情解析内容。
        if let initRule = rule.initRule, !initRule.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            EngineLogger.log("执行详情页初始化规则", tag: source.bookSourceName)
            if let initialized = analyzeRule.getElement(initRule) {
                analyzeRule.setContent(initialized, baseUrl: baseUrl)
            } else {
                EngineLogger.log("详情页初始化规则返回空", tag: source.bookSourceName, level: .warn)
            }
        }

        func g(_ r: String?, isUrl: Bool = false) -> String {
            guard let r, !r.isEmpty else { return "" }
            return analyzeRule.getString(r, isUrl: isUrl)
        }

        var resolvedTocUrl = ""
        if let tocRule = rule.tocUrl, !tocRule.isEmpty {
            let lowered = tocRule.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if lowered.contains("<js>") || lowered.hasPrefix("@js:") || lowered.hasPrefix("$.") || lowered.hasPrefix("$[") {
                resolvedTocUrl = analyzeRule.getString(tocRule, isUrl: true)
            } else {
                resolvedTocUrl = analyzeRule.getRawString(tocRule)
            }
        }

        if lightweight {
            return BookInfo(tocUrl: resolvedTocUrl)
        }

        return BookInfo(
            name: g(rule.name),
            author: g(rule.author),
            intro: stripHTML(g(rule.intro)),
            coverUrl: g(rule.coverUrl, isUrl: true),
            kind: g(rule.kind),
            tocUrl: resolvedTocUrl
        )
    }

    // MARK: - 正文

    public func getContent(chapterUrl: String, maxPages: Int = 20) async throws -> String {
        guard let rule = source.ruleContent, let contentRule = rule.content else {
            EngineLogger.log("书源缺少 ruleContent.content", tag: source.bookSourceName, level: .warn)
            return ""
        }

        var pieces: [String] = []
        var visited: Set<String> = []
        var currentUrl: String? = chapterUrl
        var pageCount = 0

        while let url = currentUrl, pageCount < maxPages, !visited.contains(url) {
            visited.insert(url)
            pageCount += 1

            let au = makeAnalyzeUrl(url)
            EngineLogger.log("正文请求: \(au.ruleUrl)", tag: source.bookSourceName)
            await SourceRateLimiter.shared.acquire(key: source.bookSourceUrl, concurrentRate: source.concurrentRate)
            let resp = try await au.getStrResponse()
            guard let body = resp.body else {
                EngineLogger.log("正文响应为空: \(url)", tag: source.bookSourceName, level: .error)
                break
            }
            let baseUrl = resp.url.isEmpty ? au.url : resp.url

            let analyzeRule = makeAnalyzeRule()
            analyzeRule.chapterUrl = url
            analyzeRule.setContent(body, baseUrl: baseUrl)

            let text = analyzeRule.getString(contentRule)
            let cleanedText = stripHTML(text)
            if !cleanedText.isEmpty { pieces.append(cleanedText) }

            if let nextRule = rule.nextContentUrl, !nextRule.isEmpty {
                let next = analyzeRule.getString(nextRule, isUrl: true)
                currentUrl = (next.isEmpty || visited.contains(next)) ? nil : next
            } else {
                currentUrl = nil
            }
        }
        let result = pieces.joined(separator: "\n")
        EngineLogger.log("正文共 \(result.count) 字", tag: source.bookSourceName)
        return result
    }

    // MARK: - 登录面板动作执行

    /// 在书源 loginUrl 里查找 `function funcName(...) {...}`，用当前上下文执行，返回函数返回值的字符串。
    /// 同时支持箭头函数 `const funcName = (...) => {...}`
    public func executeLoginAction(_ action: String, infoMap: [String: String]) async throws -> String? {
        guard let loginScript = source.loginUrl, !loginScript.isEmpty else { return nil }
        persistLoginInfo(infoMap)
        if let data = try? JSONSerialization.data(withJSONObject: infoMap),
           let json = String(data: data, encoding: .utf8) {
            sourceContext?.putLoginInfo(json)
        }

        let analyzeRule = makeAnalyzeRule()
        analyzeRule.setBaseUrl(source.bookSourceUrl)

        let trimmed = action.trimmingCharacters(in: .whitespacesAndNewlines)
        let expression: String
        if trimmed == "login()" || trimmed == "login" {
            expression = "login(true)"
        } else if trimmed.contains("(") {
            expression = trimmed
        } else {
            expression = "\(trimmed)()"
        }
        let script = loginScript + "\n;" + expression
        // 书源登录函数通过全局 result 读取面板字段。
        let result = analyzeRule.evalJS(script, result: infoMap)
        if let jsError = analyzeRule.lastJSError {
            throw NSError(
                domain: "BookSourceLogin",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: jsError]
            )
        }
        return result.map { "\($0)" }
    }

    func stripHTML(_ s: String) -> String {
        guard s.contains("<") || s.contains("&") else { return s }
        var text = s
        // 先把所有常见换行标签统一为真正换行，避免正文出现原始 <br />
        text = text.replacingOccurrences(of: "(?i)<br\\s*/?\\s*>", with: "\n", options: [.regularExpression])
        text = text.replacingOccurrences(of: "(?i)</p\\s*>", with: "\n", options: [.regularExpression])
        text = text.replacingOccurrences(of: "(?i)</div\\s*>", with: "\n", options: [.regularExpression])
        text = text.replacingOccurrences(of: "(?i)<li\\b[^>]*>", with: "\n", options: [.regularExpression])
        text = text.replacingOccurrences(of: "(?i)<[^>]+>", with: "", options: [.regularExpression])
        let entities = ["&nbsp;": " ", "&#160;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&apos;": "'"]
        for (key, value) in entities { text = text.replacingOccurrences(of: key, with: value) }
        // 清除不可见字符并压缩过多空行
        text = text.replacingOccurrences(of: "\\r\\n?", with: "\n", options: [.regularExpression])
        text = text.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: [.regularExpression])
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private final class LogInfoBridge: RuleDataInterface {
    var variableMap: [String: String]
    init(infoMap: [String: String]) { self.variableMap = infoMap }
}

private final class RuntimeSourceJSContext: SourceJSContext {
    private weak var owner: BookSourceRuntime?
    private let variableKey = "__source_variable"

    init(owner: BookSourceRuntime) {
        self.owner = owner
    }

    var bookSourceName: String { owner?.source.bookSourceName ?? "" }
    var loginUi: String { owner?.source.loginUi ?? "" }
    var loginUrl: String { owner?.source.loginUrl ?? "" }

    func getVariable() -> String {
        owner?.sourceKeyValueStore?.get(variableKey) ?? ""
    }

    func setVariable(_ value: String) {
        owner?.sourceKeyValueStore?.put(variableKey, value)
    }

    func getLoginHeader() -> String? {
        owner?.source.loginHeader
    }

    func putLoginHeader(_ value: String) {
        owner?.source.loginHeader = value
    }

    func getLoginInfoMap() -> [String: String] {
        owner?.source.loginInfoMap ?? [:]
    }

    func putLoginInfo(_ json: String) {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        var info: [String: String] = [:]
        for (key, value) in obj { info[key] = "\(value)" }
        owner?.persistLoginInfo(info)
    }
}
