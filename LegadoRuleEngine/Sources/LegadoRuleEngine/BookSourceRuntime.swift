import Foundation

/// 把 `BookSource` + `AnalyzeUrl` + `AnalyzeRule` 串起来的胶水层：
/// 搜索 → 目录 → 正文 三步，并对齐 legado 原版的若干行为（目录倒序/去重/空链接兜底）。
/// 每一步都写引擎日志，方便定位"搜得到但打不开"的问题。
public struct SearchResult {
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
    public let source: BookSource

    public weak var sourceContext: SourceJSContext?
    public var toastHandler: ((_ msg: String) -> Void)?
    public var browserOpener: ((_ url: String, _ title: String?) -> Void)?
    public var refreshExploreHandler: (() -> Void)?
    public var searchBookHandler: ((_ keyword: String, _ sourceFilter: String?) -> Void)?

    public init(_ source: BookSource) {
        self.source = source
    }

    // MARK: - 构造

    private func makeAnalyzeUrl(_ urlRule: String, key: String? = nil, page: Int? = nil, bookUrl: String? = nil) -> AnalyzeUrl {
        let au = AnalyzeUrl(
            url: urlRule,
            key: key,
            page: page,
            baseUrl: source.bookSourceUrl,
            headerMap: resolveHeaderMap()
        )
        au.jsLib = source.jsLib
        au.sourceContext = sourceContext
        au.bookUrl = bookUrl
        au.ajaxEvaluator = { [weak self] url in self?.blockingAjax(url) }
        au.toastHandler = toastHandler
        au.browserOpener = browserOpener
        return au
    }

    private func makeAnalyzeRule() -> AnalyzeRule {
        let rule = AnalyzeRule()
        rule.jsLib = source.jsLib
        rule.sourceContext = sourceContext
        rule.ajaxEvaluator = { [weak self] url in self?.blockingAjax(url) }
        rule.toastHandler = toastHandler
        rule.browserOpener = browserOpener
        rule.refreshExploreHandler = refreshExploreHandler
        rule.searchBookHandler = searchBookHandler
        return rule
    }

    /// 解析请求头
    public func resolveHeaderMap() -> [String: String] {
        guard let header = source.header else { return [:] }
        let trimmed = header.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [:] }

        let isJS = trimmed.lowercased().hasPrefix("@js:") || trimmed.lowercased().hasPrefix("<js>")
        guard isJS else { return source.parsedHeaderMap() }

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
        guard let evaluated = rule.evalJS(jsBody) else { return [:] }
        let str = "\(evaluated)"
        guard let data = str.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        var result: [String: String] = [:]
        for (k, v) in obj { result[k] = "\(v)" }
        return result
    }

    private func blockingAjax(_ urlString: String) -> String? {
        guard let url = URL(string: urlString) else { return nil }
        let semaphore = DispatchSemaphore(value: 0)
        var resultText: String?
        var request = URLRequest(url: url)
        for (k, v) in resolveHeaderMap() { request.setValue(v, forHTTPHeaderField: k) }
        let task = URLSession.shared.dataTask(with: request) { data, _, _ in
            if let data = data { resultText = String(data: data, encoding: .utf8) }
            semaphore.signal()
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 30)
        return resultText
    }

    // MARK: - 搜索

    public func search(_ keyword: String, page: Int = 1) async throws -> [SearchResult] {
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

        return items.compactMap { item in
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

    // MARK: - 目录

    public func getToc(bookUrl: String, maxPages: Int = 50) async throws -> [ChapterInfo] {
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

        // 很多源的目录是 JSON 接口/独立地址，由 ruleBookInfo.tocUrl 指定：先解析详情页拿到真正目录地址
        var tocUrl = bookUrl
        if let tocRule = source.ruleBookInfo?.tocUrl, !tocRule.isEmpty {
            let info = try await getBookInfo(bookUrl: bookUrl)
            if !info.tocUrl.isEmpty {
                tocUrl = info.tocUrl
                EngineLogger.log("详情页解析出目录地址: \(tocUrl)", tag: source.bookSourceName)
            }
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
                let name = analyzeRule.getString(rule.chapterName, mContent: item)
                var chapterUrl = analyzeRule.getString(rule.chapterUrl, mContent: item, isUrl: true)
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

    public func getBookInfo(bookUrl: String) async throws -> BookInfo {
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

        func g(_ r: String?, isUrl: Bool = false) -> String {
            guard let r, !r.isEmpty else { return "" }
            return analyzeRule.getString(r, isUrl: isUrl)
        }

        return BookInfo(
            name: g(rule.name),
            author: g(rule.author),
            intro: stripHTML(g(rule.intro)),
            coverUrl: g(rule.coverUrl, isUrl: true),
            kind: g(rule.kind),
            tocUrl: analyzeRule.getRawString(rule.tocUrl)
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
            if !text.isEmpty { pieces.append(text) }

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

    // MARK: - 简单 HTML 去标签

    private func stripHTML(_ s: String) -> String {
        guard s.contains("<") else { return s }
        return s
            .replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: [.regularExpression])
            .replacingOccurrences(of: "<[^>]+>", with: "", options: [.regularExpression])
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
