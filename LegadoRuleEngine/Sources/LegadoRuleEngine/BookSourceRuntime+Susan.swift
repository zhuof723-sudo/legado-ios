import Foundation

private enum SusanAdapterError: LocalizedError {
    case invalidPayload(String)
    case invalidURL(String)
    case http(Int, String)
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .invalidPayload(let value): return "书山载荷无效：\(value)"
        case .invalidURL(let value): return "书山接口地址无效：\(value)"
        case .http(let code, let text): return "书山接口 HTTP \(code)：\(text)"
        case .invalidResponse(let text): return "书山接口响应无效：\(text)"
        }
    }
}

extension BookSourceRuntime {
    /// 书山聚合的详情 init 会从 JavaScriptCore 同步重入网络层，在部分设备上触发 SIGABRT。
    /// 对 type=susan 的 detailsUrl 使用等价的原生异步请求，其他书源仍走通用规则引擎。
    func getSusanBookInfo(bookUrl: String, lightweight: Bool) async throws -> BookInfo? {
        guard let payload = susanDataPayload(bookUrl, kind: "detailsUrl", requiredType: "susan") else {
            return nil
        }

        EngineLogger.log("书山原生详情：已解码搜索载荷", tag: source.bookSourceName)
        let response = try await susanRequest(path: "/details", body: payload)
        guard let data = response["data"] as? [String: Any] else {
            throw SusanAdapterError.invalidResponse(susanString(response["message"]))
        }

        let catalog: [String: Any] = [
            "source": susanString(data["source"], fallback: susanString(payload["source"])),
            "url": susanString(data["book_url"], fallback: susanString(payload["url"])),
            "name": susanString(data["title"], fallback: susanString(payload["name"])),
            "tab": susanString(data["tab"], fallback: "novel"),
            "bookid": susanString(data["bookid"])
        ]
        let tocURL = try susanDataURL(kind: "catalogUrl", payload: catalog, type: "susan")
        EngineLogger.log("书山原生详情：目录载荷已生成", tag: source.bookSourceName)

        if lightweight {
            return BookInfo(tocUrl: tocURL)
        }
        return BookInfo(
            name: susanString(data["title"]),
            author: susanString(data["author"]),
            intro: susanString(data["desc"]),
            coverUrl: susanString(data["cover"]),
            kind: susanString(data["tags"]),
            tocUrl: tocURL
        )
    }

    /// 原生解析 type=susan 的 catalogUrl，避免目录规则里的同步 JS 网络重入。
    func getSusanToc(tocUrl: String) async throws -> [ChapterInfo]? {
        guard let catalog = susanDataPayload(tocUrl, kind: "catalogUrl", requiredType: "susan") else {
            return nil
        }

        EngineLogger.log("书山原生目录：开始请求 /catalog", tag: source.bookSourceName)
        let response = try await susanRequest(path: "/catalog", body: catalog)
        guard let rows = response["data"] as? [Any] else {
            throw SusanAdapterError.invalidResponse(susanString(response["message"]))
        }

        var chapters: [ChapterInfo] = []
        chapters.reserveCapacity(rows.count)
        var seen = Set<String>()
        for case let row as [String: Any] in rows {
            if susanBool(row["isVolume"]) { continue }
            let title = susanString(row["title"])
            guard !title.isEmpty else { continue }
            let chapterURL = try susanChapterURL(item: row, catalog: catalog)
            let identity = chapterURL.isEmpty ? title : chapterURL
            guard seen.insert(identity).inserted else { continue }
            chapters.append(ChapterInfo(name: title, url: chapterURL))
        }
        return chapters
    }

    private func susanRequest(path: String, body: [String: Any]) async throws -> [String: Any] {
        let urlString = susanServerHost() + path
        guard let url = URL(string: urlString) else { throw SusanAdapterError.invalidURL(urlString) }
        guard JSONSerialization.isValidJSONObject(body) else {
            throw SusanAdapterError.invalidPayload(path)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json;charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue(JSCommonMethods.defaultUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(susanNovelToken(), forHTTPHeaderField: "X-Novel-Token")
        let loginHeader = sourceContext?.getLoginHeader() ?? source.loginHeader
        if let loginHeader, !loginHeader.isEmpty {
            request.setValue(JSCommonMethods.base64Encode(loginHeader), forHTTPHeaderField: "X-Api-Key")
        }

        EngineLogger.log("书山原生请求：\(path) · body \(request.httpBody?.count ?? 0) 字节", tag: source.bookSourceName)
        let (responseData, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let responseText = String(data: responseData, encoding: .utf8) ?? ""
        EngineLogger.log("书山原生响应：\(path) · HTTP \(status) · \(responseData.count) 字节", tag: source.bookSourceName)
        guard (200..<300).contains(status) else {
            throw SusanAdapterError.http(status, String(responseText.prefix(300)))
        }
        guard let object = try JSONSerialization.jsonObject(with: responseData, options: [.fragmentsAllowed]) as? [String: Any] else {
            throw SusanAdapterError.invalidResponse(String(responseText.prefix(300)))
        }
        if let code = object["code"] as? NSNumber, code.intValue != 200 {
            throw SusanAdapterError.invalidResponse(susanString(object["message"], fallback: "code=\(code)"))
        }
        return object
    }

    private func susanNovelToken() -> String {
        if let header = source.header,
           let regex = try? NSRegularExpression(
               pattern: #"X-Novel-Token[\"']?\s*:\s*[\"']([^\"']+)"#,
               options: [.caseInsensitive]
           ),
           let match = regex.firstMatch(in: header, range: NSRange(header.startIndex..., in: header)),
           match.numberOfRanges > 1,
           let range = Range(match.range(at: 1), in: header) {
            return String(header[range])
        }
        return "SHUSAN_READ_2025"
    }

    private func susanServerHost() -> String {
        let variable = sourceContext?.getVariable()
            ?? sourceKeyValueStore?.get("__source_variable")
            ?? ""
        if let data = variable.data(using: .utf8),
           let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
           let host = array.first?["host"] as? String,
           host.hasPrefix("http") {
            return host.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }

        if let lib = source.jsLib,
           let regex = try? NSRegularExpression(pattern: #"https?://[A-Za-z0-9._:-]+"#),
           let match = regex.firstMatch(in: lib, range: NSRange(lib.startIndex..., in: lib)),
           let range = Range(match.range, in: lib) {
            return String(lib[range]).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        return "https://v1.vossc.com"
    }

    private func susanDataPayload(
        _ value: String,
        kind: String,
        requiredType: String
    ) -> [String: Any]? {
        let custom = CustomUrl(value)
        guard (custom.getAttr()["type"] as? String)?.lowercased() == requiredType.lowercased() else {
            return nil
        }
        let rawURL = custom.getUrl()
        let prefix = "data:\(kind);base64,"
        guard rawURL.lowercased().hasPrefix(prefix.lowercased()) else { return nil }
        let encoded = String(rawURL.dropFirst(prefix.count))
        guard let data = Data(base64Encoded: encoded, options: [.ignoreUnknownCharacters]),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object
    }

    private func susanDataURL(kind: String, payload: [String: Any], type: String) throws -> String {
        guard JSONSerialization.isValidJSONObject(payload) else {
            throw SusanAdapterError.invalidPayload(kind)
        }
        let data = try JSONSerialization.data(withJSONObject: payload)
        let encoded = data.base64EncodedString()
        return "data:\(kind);base64,\(encoded),{\"type\":\"\(type)\"}"
    }

    private func susanChapterURL(item: [String: Any], catalog: [String: Any]) throws -> String {
        let sourceName = susanString(catalog["source"])
        let catalogURL = susanString(catalog["url"])
        let bookID = susanString(catalog["bookid"])
        let itemURL = susanString(item["url"])
        let fanqieSources = Set(["番茄小说", "番茄短剧", "番茄听书", "番茄畅听"])

        var params: [String: Any] = [
            "cid": item["cid"] ?? "",
            "source": sourceName
        ]
        if fanqieSources.contains(sourceName) {
            params["book_id"] = bookID
            params["item_id"] = susanFirstMatch(#"item_id=(\d+)"#, in: itemURL) ?? NSNull()
        } else {
            params["url"] = catalogURL
        }

        if sourceName == "书旗听书",
           let itemID = susanFirstMatch(#"[?&]?item_ids=(\d+)"#, in: itemURL) {
            params["bookid"] = bookID
            params["item_ids"] = itemID
        }
        if ["企鹅看书", "QQ阅读", "起点"].contains(sourceName),
           let chapterID = susanFirstMatch(#"chapterid=(\d+)"#, in: itemURL) {
            params["bookid"] = bookID
            params["chapterid"] = chapterID
        }
        if sourceName == "晋江",
           let chapterID = susanFirstMatch(#"chapterId=(\d+)"#, in: itemURL) {
            params["novelId"] = bookID
            params["chapterId"] = chapterID
        }
        if sourceName == "半夏" {
            if let value = susanFirstMatch(#"bookid=(\d+)"#, in: itemURL) { params["bookid"] = value }
            if let value = susanFirstMatch(#"chapterid=(\d+)"#, in: itemURL) { params["chapterid"] = value }
            if let value = susanFirstMatch(#"novelId=(\d+)"#, in: itemURL) { params["novelId"] = value }
            if let value = susanFirstMatch(#"chapterId=(\d+)"#, in: itemURL) { params["chapterId"] = value }
        }
        if sourceName == "七猫" { params["qm_url"] = itemURL }
        if sourceName == "七猫短剧" { params["qm_id"] = bookID }

        return try susanDataURL(kind: "chapterUrl", payload: params, type: "qingci")
    }

    private func susanFirstMatch(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    private func susanBool(_ value: Any?) -> Bool {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.boolValue }
        if let value = value as? String { return value == "1" || value.lowercased() == "true" }
        return false
    }

    private func susanString(_ value: Any?, fallback: String = "") -> String {
        guard let value, !(value is NSNull) else { return fallback }
        if let value = value as? String { return value.isEmpty ? fallback : value }
        if let value = value as? NSNumber { return value.stringValue }
        return String(describing: value)
    }
}
