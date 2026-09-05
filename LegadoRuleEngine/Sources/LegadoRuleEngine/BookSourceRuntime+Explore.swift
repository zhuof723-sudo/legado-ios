import Foundation

extension BookSourceRuntime {
    /// 解析书源 exploreUrl 为发现分类。兼容 JSON 数组、`标题::URL` 多行和 @js/<js> 返回值。
    public func exploreKinds() -> [ExploreKindInfo] {
        guard let raw = source.exploreUrl?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return [] }

        // 先在 JavaScriptCore 外解析一次请求头；发现脚本内的 java.ajax 直接复用，避免同步重入 JS。
        if raw.lowercased().hasPrefix("@js:") || raw.lowercased().hasPrefix("<js>") {
            _ = resolveHeaderMap()
        }

        let evaluated: Any
        if raw.lowercased().hasPrefix("@js:") {
            let rule = makeAnalyzeRule()
            rule.setBaseUrl(source.bookSourceUrl)
            evaluated = rule.evalJS(String(raw.dropFirst(4))) ?? ""
        } else if raw.lowercased().hasPrefix("<js>"), raw.lowercased().hasSuffix("</js>") {
            let start = raw.index(raw.startIndex, offsetBy: 4)
            let end = raw.index(raw.endIndex, offsetBy: -5)
            let rule = makeAnalyzeRule()
            rule.setBaseUrl(source.bookSourceUrl)
            evaluated = rule.evalJS(String(raw[start..<end])) ?? ""
        } else {
            evaluated = raw
        }

        if let array = evaluated as? [Any] {
            return parseExploreKindArray(array)
        }
        let text = String(describing: evaluated).trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = text.data(using: .utf8),
           let array = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) as? [Any] {
            return parseExploreKindArray(array)
        }

        let regex = try? NSRegularExpression(pattern: "(?:&&|\\r?\\n)+")
        let range = NSRange(text.startIndex..., in: text)
        let normalized = regex?.stringByReplacingMatches(in: text, range: range, withTemplate: "\n") ?? text
        return normalized.split(separator: "\n").compactMap { line in
            let value = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return nil }
            let parts = value.components(separatedBy: "::")
            let title = parts.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !title.isEmpty else { return nil }
            let url = parts.count > 1 ? parts.dropFirst().joined(separator: "::").trimmingCharacters(in: .whitespacesAndNewlines) : ""
            return ExploreKindInfo(title: title, url: url)
        }
    }

    public func exploreKindsCached(
        cacheTTL: TimeInterval = 900,
        forceRefresh: Bool = false
    ) async -> [ExploreKindInfo] {
        let component = "kinds|\(source.exploreUrl ?? "")|\(sourceContext?.getVariable() ?? "")|\(source.loginHeader ?? "")"
        let key = await ExploreCache.shared.cacheKey(sourceURL: source.bookSourceUrl, component: component)
        if !forceRefresh,
           let cached = await ExploreCache.shared.load([ExploreKindInfo].self, key: key, ttl: cacheTTL) {
            EngineLogger.log("发现分类命中缓存，共 \(cached.count) 项", tag: source.bookSourceName)
            return cached
        }
        let values = exploreKinds()
        if cacheTTL > 0, !values.isEmpty { await ExploreCache.shared.save(values, key: key) }
        return values
    }

    public func clearExploreCache() async {
        await ExploreCache.shared.clear(sourceURL: source.bookSourceUrl)
    }

    /// 获取某个发现分类的真实书籍列表，解析字段完全来自 ruleExplore。
    public func explore(
        _ kind: ExploreKindInfo,
        page: Int = 1,
        resultLimit: Int = 20,
        cacheTTL: TimeInterval = 900,
        forceRefresh: Bool = false
    ) async throws -> [SearchResult] {
        guard !kind.url.isEmpty else { return [] }
        let component = "books|\(kind.id)|\(page)|\(resultLimit)|\(sourceContext?.getVariable() ?? "")|\(source.loginHeader ?? "")"
        let cacheKey = await ExploreCache.shared.cacheKey(sourceURL: source.bookSourceUrl, component: component)
        if !forceRefresh,
           let cached = await ExploreCache.shared.load([SearchResult].self, key: cacheKey, ttl: cacheTTL) {
            EngineLogger.log("发现分类[\(kind.title)]命中缓存，共 \(cached.count) 项", tag: source.bookSourceName)
            return cached
        }
        let exploreRule = source.ruleExplore
        let searchRule = source.ruleSearch
        let useSearchRule = exploreRule?.bookList?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
        let listRule = useSearchRule ? searchRule?.bookList : exploreRule?.bookList
        guard var listRule, !listRule.isEmpty else {
            EngineLogger.log("发现规则缺少 bookList", tag: source.bookSourceName, level: .warn)
            return []
        }

        var reverse = false
        if listRule.hasPrefix("-") { reverse = true; listRule.removeFirst() }
        else if listRule.hasPrefix("+") { listRule.removeFirst() }

        let analyzeURL = makeAnalyzeUrl(kind.url, page: page)
        EngineLogger.log("发现请求[\(kind.title)]: \(analyzeURL.ruleUrl)", tag: source.bookSourceName)
        await SourceRateLimiter.shared.acquire(key: source.bookSourceUrl, concurrentRate: source.concurrentRate)
        let response = try await analyzeURL.getStrResponse()
        guard let body = response.body else { return [] }
        let baseURL = response.url.isEmpty ? analyzeURL.url : response.url

        let analyzer = makeAnalyzeRule()
        analyzer.setContent(body, baseUrl: baseURL)
        let items = analyzer.getElements(listRule)
        let safeLimit = max(1, resultLimit)
        EngineLogger.log("发现分类[\(kind.title)]命中 \(items.count) 项，解析前 \(min(items.count, safeLimit)) 项", tag: source.bookSourceName)

        let nameRule = useSearchRule ? searchRule?.name : exploreRule?.name
        let authorRule = useSearchRule ? searchRule?.author : exploreRule?.author
        let introRule = useSearchRule ? searchRule?.intro : exploreRule?.intro
        let kindRule = useSearchRule ? searchRule?.kind : exploreRule?.kind
        let lastChapterRule = useSearchRule ? searchRule?.lastChapter : exploreRule?.lastChapter
        let bookURLRule = useSearchRule ? searchRule?.bookUrl : exploreRule?.bookUrl
        let coverRule = useSearchRule ? searchRule?.coverUrl : exploreRule?.coverUrl
        let wordCountRule = useSearchRule ? searchRule?.wordCount : exploreRule?.wordCount

        var result: [SearchResult] = []
        result.reserveCapacity(min(items.count, safeLimit))
        var seen = Set<String>()
        for item in items.prefix(safeLimit) {
            let parsed: SearchResult? = autoreleasepool {
                let name = analyzer.getString(nameRule, mContent: item)
                guard !name.isEmpty else { return nil }
                var bookURL = analyzer.getString(bookURLRule, mContent: item, isUrl: true)
                if bookURL.isEmpty { bookURL = baseURL }
                return SearchResult(
                    name: name,
                    author: analyzer.getString(authorRule, mContent: item),
                    intro: stripHTML(analyzer.getString(introRule, mContent: item)),
                    kind: analyzer.getString(kindRule, mContent: item),
                    lastChapter: analyzer.getString(lastChapterRule, mContent: item),
                    bookUrl: bookURL,
                    coverUrl: analyzer.getString(coverRule, mContent: item, isUrl: true),
                    wordCount: analyzer.getString(wordCountRule, mContent: item)
                )
            }
            if let parsed {
                let identity = parsed.bookUrl + "|" + parsed.name
                if seen.insert(identity).inserted { result.append(parsed) }
            }
        }
        if reverse { result.reverse() }
        if cacheTTL > 0, !result.isEmpty { await ExploreCache.shared.save(result, key: cacheKey) }
        return result
    }

    private func parseExploreKindArray(_ values: [Any]) -> [ExploreKindInfo] {
        values.compactMap { value in
            guard let object = value as? [String: Any] else { return nil }
            let title = exploreString(object["title"])
            guard !title.isEmpty else { return nil }
            return ExploreKindInfo(
                title: title,
                url: exploreString(object["url"]),
                type: exploreString(object["type"], fallback: "url")
            )
        }
    }

    private func exploreString(_ value: Any?, fallback: String = "") -> String {
        guard let value, !(value is NSNull) else { return fallback }
        if let value = value as? String { return value }
        if let value = value as? NSNumber { return value.stringValue }
        return String(describing: value)
    }
}
