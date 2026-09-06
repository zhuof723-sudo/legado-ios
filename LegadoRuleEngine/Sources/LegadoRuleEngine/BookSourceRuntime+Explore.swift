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

        if isSusanExploreSource,
           let native = normalizeSusanExplore(body: body, resultLimit: resultLimit) {
            EngineLogger.log("书山原生发现[\(kind.title)]解析 \(native.count) 本", tag: source.bookSourceName)
            if cacheTTL > 0, !native.isEmpty { await ExploreCache.shared.save(native, key: cacheKey) }
            return native
        }

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

    private var isSusanExploreSource: Bool {
        source.bookSourceUrl == "书山聚合" || source.bookSourceName.contains("书山聚合")
    }

    private func normalizeSusanExplore(body: String, resultLimit: Int) -> [SearchResult]? {
        guard let data = body.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            return nil
        }
        let rows = findSusanBookRows(object)
        guard !rows.isEmpty else { return nil }

        var results: [SearchResult] = []
        var seen = Set<String>()
        for row in rows.prefix(max(1, resultLimit)) {
            let name = firstExploreString(row, keys: ["book_name", "bookName", "original_book_name", "title"])
            guard !name.isEmpty else { continue }
            let bookID = firstExploreString(row, keys: ["book_id", "bookId", "series_id", "bookIdStr"])
            let originalURL = firstExploreString(row, keys: ["book_url", "bookUrl", "url"])
            var sourceName = firstExploreString(row, keys: ["source", "sourceName"], fallback: "番茄小说")
            var detailURL = originalURL
            if bookID.count == 19, bookID.allSatisfy({ $0.isNumber }) {
                let api = "https://api5-normal-sinfonlineb.fqnovel.com/reading/bookapi/multi-detail/v/?aid=1967&iid=1&version_code=999&book_id=\(bookID)"
                detailURL = JSCommonMethods.base64Encode(api)
                sourceName = "番茄小说"
            } else if !originalURL.isEmpty {
                detailURL = JSCommonMethods.base64Encode(originalURL)
            }
            guard !detailURL.isEmpty else { continue }

            let cover = firstExploreString(row, keys: ["thumb_url", "audio_thumb_uri", "thumbUri", "cover", "cover_url"])
            let intro = firstExploreString(row, keys: ["abstract", "desc", "description"])
            let payload: [String: Any] = [
                "source": sourceName,
                "url": detailURL,
                "cover": cover,
                "desc": intro,
                "name": name
            ]
            guard JSONSerialization.isValidJSONObject(payload),
                  let payloadData = try? JSONSerialization.data(withJSONObject: payload) else { continue }
            let encoded = payloadData.base64EncodedString()
            let bookURL = "data:detailsUrl;base64,\(encoded),{\"type\":\"susan\"}"
            let identity = bookURL + "|" + name
            guard seen.insert(identity).inserted else { continue }

            results.append(SearchResult(
                name: name,
                author: firstExploreString(row, keys: ["author", "author_name", "authorName"]),
                intro: stripHTML(intro),
                kind: firstExploreString(row, keys: ["tags", "category", "genre"]),
                lastChapter: firstExploreString(row, keys: ["lastChapterTitle", "last_chapter_title", "latestChapterTitle"]),
                bookUrl: bookURL,
                coverUrl: cover,
                wordCount: firstExploreString(row, keys: ["word_number", "WordsCount", "wordCount"])
            ))
        }
        return results
    }

    private func findSusanBookRows(_ value: Any, depth: Int = 0) -> [[String: Any]] {
        guard depth < 10 else { return [] }
        if let array = value as? [Any] {
            let dictionaries = array.compactMap { $0 as? [String: Any] }
            if !dictionaries.isEmpty, dictionaries.contains(where: { looksLikeSusanBook($0) }) {
                return dictionaries.filter { looksLikeSusanBook($0) }
            }
            for child in array {
                let found = findSusanBookRows(child, depth: depth + 1)
                if !found.isEmpty { return found }
            }
        }
        if let dictionary = value as? [String: Any] {
            let preferredKeys = ["book_list", "book_info", "publication_list", "book_data", "records", "data_list", "list", "result", "data"]
            for key in preferredKeys {
                if let child = dictionary[key] {
                    let found = findSusanBookRows(child, depth: depth + 1)
                    if !found.isEmpty { return found }
                }
            }
            for child in dictionary.values {
                let found = findSusanBookRows(child, depth: depth + 1)
                if !found.isEmpty { return found }
            }
        }
        return []
    }

    private func looksLikeSusanBook(_ object: [String: Any]) -> Bool {
        let name = firstExploreString(object, keys: ["book_name", "bookName", "original_book_name", "title"])
        let id = firstExploreString(object, keys: ["book_id", "bookId", "series_id", "book_url", "url"])
        return !name.isEmpty && !id.isEmpty
    }

    private func firstExploreString(
        _ object: [String: Any],
        keys: [String],
        fallback: String = ""
    ) -> String {
        for key in keys {
            let value = exploreString(object[key])
            if !value.isEmpty { return value }
        }
        return fallback
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
