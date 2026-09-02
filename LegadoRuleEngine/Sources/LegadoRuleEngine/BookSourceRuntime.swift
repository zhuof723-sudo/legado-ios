import Foundation

/// 不对应 legado 里的某一个单独文件，是把 `BookSource` + `AnalyzeUrl` + `AnalyzeRule`
/// 串起来的一层胶水代码（legado 里这部分逻辑分散在 WebBook.kt / BookChapterList.kt 等
/// 多个协程任务类里，和 UI/数据库耦合较深，没有直接照抄的价值，这里按同样的规则驱动
/// 思路重新写了一版最小可用实现）。
///
/// 定位：能直接跑通"搜索 -> 详情/目录 -> 正文"三步，可以当参考实现，
/// 生产使用建议按需补：分页抓取更多搜索结果（用 AnalyzeUrl 的 page 参数）、
/// 目录去重/本地缓存、错误重试、详情页(ruleBookInfo)解析（这里只做了搜索页/目录页/正文页，
/// 详情页同理可以照抄 getToc 的写法加一个 getBookInfo）。
/// 并发限流已接入：每次请求前都会按 `source.concurrentRate`（形如 "1/1000"）过一遍
/// `SourceRateLimiter.shared`，同一书源不会无节制地并发/高频打请求。
/// jsLib/source变量存储/cookie/常用java.*方法（base64、hex、时间格式化、对称加解密等）
/// 都会自动注入进每次规则JS执行——书源不需要额外配置。
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

public struct ChapterInfo {
    public let name: String
    public let url: String
}

public final class BookSourceRuntime {
    public let source: BookSource

    /// 书源级别的持久变量+登录信息，不注入的话 `this.source.getVariable()` 等调用只会拿到空值
    public weak var sourceContext: SourceJSContext?
    public var toastHandler: ((_ msg: String) -> Void)?
    public var browserOpener: ((_ url: String, _ title: String?) -> Void)?
    public var refreshExploreHandler: (() -> Void)?
    public var searchBookHandler: ((_ keyword: String, _ sourceFilter: String?) -> Void)?

    public init(_ source: BookSource) {
        self.source = source
    }

    private func makeAnalyzeUrl(_ urlRule: String, key: String? = nil, page: Int? = nil) -> AnalyzeUrl {
        let au = AnalyzeUrl(
            url: urlRule,
            key: key,
            page: page,
            baseUrl: source.bookSourceUrl,
            headerMap: resolveHeaderMap()
        )
        au.jsLib = source.jsLib
        au.sourceContext = sourceContext
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

    /// 解析请求头：`header` 字段除了直接是JSON对象字符串，也可能是 `@js:`/`<js>` 动态脚本
    /// （常见于需要算签名/UA伪装的书源），这种情况下要真正跑一遍JS才能拿到最终的header字典
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

    /// 同步阻塞版ajax，供 java.ajax()/java.ajaxAll() 在JS里调用（JS执行天然是同步的，
    /// 这里用信号量把异步网络请求包成同步调用，legado原版Kotlin实现也是靠runBlocking做同样的事）
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

    /// 搜索。只抓第一页，需要翻页的话给 page 传 1、2、3... （书源url规则里一般用 `<1,2,3>` 或 `{{page}}` 分页）
    public func search(_ keyword: String, page: Int = 1) async throws -> [SearchResult] {
        guard let searchUrlRule = source.searchUrl, let rule = source.ruleSearch,
              let listRule = rule.bookList else { return [] }

        let au = makeAnalyzeUrl(searchUrlRule, key: keyword, page: page)
        await SourceRateLimiter.shared.acquire(key: source.bookSourceUrl, concurrentRate: source.concurrentRate)
        let resp = try await au.getStrResponse()

        let analyzeRule = makeAnalyzeRule()
        analyzeRule.setContent(resp.body ?? "", baseUrl: au.url)

        let items = analyzeRule.getElements(listRule)
        return items.map { item in
            SearchResult(
                name: analyzeRule.getString(rule.name, mContent: item),
                author: analyzeRule.getString(rule.author, mContent: item),
                intro: analyzeRule.getString(rule.intro, mContent: item),
                kind: analyzeRule.getString(rule.kind, mContent: item),
                lastChapter: analyzeRule.getString(rule.lastChapter, mContent: item),
                bookUrl: analyzeRule.getString(rule.bookUrl, mContent: item, isUrl: true),
                coverUrl: analyzeRule.getString(rule.coverUrl, mContent: item, isUrl: true),
                wordCount: analyzeRule.getString(rule.wordCount, mContent: item)
            )
        }
    }

    /// 目录。会顺着 nextTocUrl 自动翻页，maxPages 防止规则写错导致死循环
    public func getToc(bookUrl: String, maxPages: Int = 50) async throws -> [ChapterInfo] {
        guard let rule = source.ruleToc, let listRule = rule.chapterList else { return [] }

        var chapters: [ChapterInfo] = []
        var visited: Set<String> = []
        var currentUrl: String? = bookUrl
        var pageCount = 0

        while let url = currentUrl, pageCount < maxPages, !visited.contains(url) {
            visited.insert(url)
            pageCount += 1

            let au = makeAnalyzeUrl(url)
            await SourceRateLimiter.shared.acquire(key: source.bookSourceUrl, concurrentRate: source.concurrentRate)
            let resp = try await au.getStrResponse()

            let analyzeRule = makeAnalyzeRule()
            analyzeRule.setContent(resp.body ?? "", baseUrl: au.url)

            let items = analyzeRule.getElements(listRule)
            for item in items {
                let name = analyzeRule.getString(rule.chapterName, mContent: item)
                let chapterUrl = analyzeRule.getString(rule.chapterUrl, mContent: item, isUrl: true)
                if !name.isEmpty { chapters.append(ChapterInfo(name: name, url: chapterUrl)) }
            }

            if let nextRule = rule.nextTocUrl, !nextRule.isEmpty {
                let next = analyzeRule.getString(nextRule, isUrl: true)
                currentUrl = (next.isEmpty || visited.contains(next)) ? nil : next
            } else {
                currentUrl = nil
            }
        }
        return chapters
    }

    /// 正文。会顺着 nextContentUrl 自动拼接分页正文（有些站点单章内容也是分页的）
    public func getContent(chapterUrl: String, maxPages: Int = 20) async throws -> String {
        guard let rule = source.ruleContent, let contentRule = rule.content else { return "" }

        var pieces: [String] = []
        var visited: Set<String> = []
        var currentUrl: String? = chapterUrl
        var pageCount = 0

        while let url = currentUrl, pageCount < maxPages, !visited.contains(url) {
            visited.insert(url)
            pageCount += 1

            let au = makeAnalyzeUrl(url)
            await SourceRateLimiter.shared.acquire(key: source.bookSourceUrl, concurrentRate: source.concurrentRate)
            let resp = try await au.getStrResponse()

            let analyzeRule = makeAnalyzeRule()
            analyzeRule.setContent(resp.body ?? "", baseUrl: au.url)

            let text = analyzeRule.getString(contentRule)
            if !text.isEmpty { pieces.append(text) }

            if let nextRule = rule.nextContentUrl, !nextRule.isEmpty {
                let next = analyzeRule.getString(nextRule, isUrl: true)
                currentUrl = (next.isEmpty || visited.contains(next)) ? nil : next
            } else {
                currentUrl = nil
            }
        }
        return pieces.joined(separator: "\n")
    }
}
