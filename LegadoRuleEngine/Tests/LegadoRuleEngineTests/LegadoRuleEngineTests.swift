import XCTest
@testable import LegadoRuleEngine

final class LegadoRuleEngineTests: XCTestCase {

    func testCSSListRule() {
        let html = """
        <div class="book-list">
          <div class="item"><a class="name" href="/book/1">凡人修仙传</a><span class="author">忘语</span></div>
          <div class="item"><a class="name" href="/book/2">诡秘之主</a><span class="author">爱潜水的乌贼</span></div>
        </div>
        """
        let rule = AnalyzeRule()
        rule.setContent(html, baseUrl: "https://example.com/")

        let items = rule.getElements(".book-list .item")
        XCTAssertEqual(items.count, 2)

        let name0 = rule.getString("class.name@text", mContent: items[0])
        XCTAssertEqual(name0, "凡人修仙传")

        let url0 = rule.getString("class.name@href", mContent: items[0], isUrl: true)
        XCTAssertEqual(url0, "https://example.com/book/1")
    }

    func testIndexSelector() {
        let html = "<ul><li>a</li><li>b</li><li>c</li><li>d</li></ul>"
        let rule = AnalyzeRule()
        rule.setContent(html)

        XCTAssertEqual(rule.getStringList("tag.li[0]@text"), ["a"])
        XCTAssertEqual(rule.getStringList("tag.li[-1]@text"), ["d"])
        XCTAssertEqual(rule.getStringList("tag.li[0:1]@text"), ["a", "b"])
        // 阅读原生写法：tag.li.-1 表示倒数第1个
        XCTAssertEqual(rule.getStringList("tag.li.-1@text"), ["d"])
    }

    func testJSONPath() {
        let json = #"{"data":{"list":[{"title":"书名A"},{"title":"书名B"}]}}"#
        let rule = AnalyzeRule()
        rule.setContent(json)
        let titles = rule.getStringList("$.data.list[*].title")
        XCTAssertEqual(titles, ["书名A", "书名B"])
    }

    func testJSONPathListFlattensTerminalArray() {
        let json = #"{"data":[{"title":"A"},{"title":"B"}]}"#
        let rule = AnalyzeRule()
        rule.setContent(json)
        let items = rule.getElements("$.data")
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(rule.getString("$.title", mContent: items[0]), "A")
        XCTAssertEqual(rule.getString("$.title", mContent: items[1]), "B")
    }

    func testBookSourceRuntimeSearchResultLimit() async throws {
        let payload = #"{"data":[{"title":"A","url":"https://example.com/a"},{"title":"B","url":"https://example.com/b"},{"title":"C","url":"https://example.com/c"}]}"#
        var source = BookSource()
        source.bookSourceUrl = "https://example.com"
        source.bookSourceName = "limit-test"
        source.searchUrl = "data:application/json;base64," + Data(payload.utf8).base64EncodedString()
        source.ruleSearch = SearchRule(bookList: "$.data", name: "$.title", bookUrl: "$.url")
        let results = try await BookSourceRuntime(source).search("test", resultLimit: 2)
        XCTAssertEqual(results.map(\.name), ["A", "B"])
    }

    func testExploreKindsSupportsMultilineAndJSON() {
        var source = BookSource()
        source.bookSourceUrl = "https://example.com"
        source.exploreUrl = "玄幻::/xuanhuan?page={{page}}\n都市::/city?page={{page}}"
        XCTAssertEqual(BookSourceRuntime(source).exploreKinds().map(\.title), ["玄幻", "都市"])

        source.exploreUrl = #"[{"title":"新书","url":"/new"},{"title":"完本","url":"/done"}]"#
        XCTAssertEqual(BookSourceRuntime(source).exploreKinds().map(\.title), ["新书", "完本"])
    }

    func testExploreParsesRealBookFields() async throws {
        let payload = #"{"data":[{"title":"发现书A","author":"作者A","cover":"https://example.com/a.jpg","url":"/book/a"},{"title":"发现书B","author":"作者B","cover":"https://example.com/b.jpg","url":"/book/b"}]}"#
        var source = BookSource()
        source.bookSourceUrl = "https://example.com"
        source.bookSourceName = "explore-test"
        source.ruleExplore = ExploreRule(
            bookList: "$.data", name: "$.title", author: "$.author",
            bookUrl: "$.url", coverUrl: "$.cover"
        )
        let dataURL = "data:application/json;base64," + Data(payload.utf8).base64EncodedString()
        let kind = ExploreKindInfo(title: "热门", url: dataURL)
        let results = try await BookSourceRuntime(source).explore(kind, resultLimit: 10)
        XCTAssertEqual(results.map(\.name), ["发现书A", "发现书B"])
        XCTAssertEqual(results.first?.bookUrl, "https://example.com/book/a")
        XCTAssertEqual(results.first?.coverUrl, "https://example.com/a.jpg")
    }

    func testExploreCacheHonorsTTLAndClear() async {
        let sourceURL = "https://cache-test.example.com/\(UUID().uuidString)"
        let key = await ExploreCache.shared.cacheKey(sourceURL: sourceURL, component: "page-1")
        await ExploreCache.shared.save(["A", "B"], key: key)
        let cached = await ExploreCache.shared.load([String].self, key: key, ttl: 60)
        XCTAssertEqual(cached ?? [], ["A", "B"])
        let disabled = await ExploreCache.shared.load([String].self, key: key, ttl: 0)
        XCTAssertNil(disabled)
        await ExploreCache.shared.clear(sourceURL: sourceURL)
        let cleared = await ExploreCache.shared.load([String].self, key: key, ttl: 60)
        XCTAssertNil(cleared)
    }

    func testRegexReplaceSuffix() {
        let rule = AnalyzeRule()
        rule.setContent("<p>凡人修仙传</p>")
        let text = rule.getString("p@text##凡人##FANREN##")
        XCTAssertEqual(text, "FANREN修仙传")
    }

    func testAnalyzeUrlPageSubstitution() {
        let au = AnalyzeUrl(url: "https://example.com/list?p=<1,2,3>", page: 2)
        XCTAssertEqual(au.url, "https://example.com/list?p=2")
    }

    func testAnalyzeUrlDeferredInitializationRunsAfterJSLibInjection() {
        let au = AnalyzeUrl(url: "<js>buildUrl(key)</js>", key: "demo", deferInitialization: true)
        au.jsLib = "function buildUrl(value) { return 'https://example.com/search?q=' + value; }"
        au.initializeDeferred()
        XCTAssertEqual(au.url, "https://example.com/search?q=demo")
    }

    func testAnalyzeUrlOptionPOST() {
        let au = AnalyzeUrl(url: #"https://example.com/search, {"method":"POST","headers":{"X-Test":"1"},"body":"kw=test"}"#)
        XCTAssertEqual(au.method, .post)
        XCTAssertEqual(au.url, "https://example.com/search")
        let request = au.buildURLRequest()
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Test"), "1")
    }

    func testAnalyzeUrlAbsoluteResolve() {
        let au = AnalyzeUrl(url: "/book/1", baseUrl: "https://example.com/list")
        XCTAssertEqual(au.url, "https://example.com/book/1")
    }

    func testAnalyzeUrlPreservesExistingPercentEncoding() {
        let au = AnalyzeUrl(url: "https://example.com/search?key=我的&source=%E5%B0%8F%E8%AF%B4")
        let url = au.buildURLRequest().url?.absoluteString
        XCTAssertEqual(url, "https://example.com/search?key=%E6%88%91%E7%9A%84&source=%E5%B0%8F%E8%AF%B4")
    }

    func testTypedDataURIResponseUsesHexPayload() async throws {
        let payload = #"{"source":"番茄小说","name":"测试"}"#
        let base64 = Data(payload.utf8).base64EncodedString()
        let au = AnalyzeUrl(url: #"data:detailsUrl;base64,\#(base64),{"type":"susan"}"#)
        let response = try await au.getStrResponse()
        XCTAssertEqual(JSCommonMethods.hexDecodeToString(response.body ?? ""), payload)
    }

    func testRuleAnalyzerSplit() throws {
        // splitRule 一旦命中某个分隔符（如 "&&"），后续只按这一种分隔符切分，
        // 不会混合 "&&" 与 "||"（elementsType 会记录具体命中的是哪一个）
        let analyzer = RuleAnalyzer("a.b&&c.d&&e.f")
        let parts = try analyzer.splitRule("&&", "||")
        XCTAssertEqual(parts, ["a.b", "c.d", "e.f"])
        XCTAssertEqual(analyzer.elementsType, "&&")

        let analyzer2 = RuleAnalyzer("a.b||c.d")
        let parts2 = try analyzer2.splitRule("&&", "||")
        XCTAssertEqual(parts2, ["a.b", "c.d"])
        XCTAssertEqual(analyzer2.elementsType, "||")
    }

    // MARK: - QueryTTF：手工拼一个最小合法TTF二进制，验证字节读取/表偏移/字形解析链路

    private func be16(_ v: Int) -> [UInt8] { [UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)] }
    private func be32(_ v: Int) -> [UInt8] {
        [UInt8((v >> 24) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)]
    }

    /// 拼一个只含 head/cmap(format0)/loca/maxp/glyf 五张表的最小TTF，
    /// unicode 65('A') 映射到 glyphId 1，glyph1 是一个只有1个点的简单字形，坐标(100,200)。
    private func buildMinimalTTF() -> [UInt8] {
        var head: [UInt8] = []
        head += be16(1); head += be16(0)          // majorVersion, minorVersion
        head += be32(0); head += be32(0); head += be32(0x5F0F3CF5) // fontRevision, checkSumAdjustment, magicNumber
        head += be16(0); head += be16(1000)       // flags, unitsPerEm
        head += [UInt8](repeating: 0, count: 8)    // created
        head += [UInt8](repeating: 0, count: 8)    // modified
        head += be16(0); head += be16(0); head += be16(0); head += be16(0) // xMin/yMin/xMax/yMax
        head += be16(0); head += be16(0)          // macStyle, lowestRecPPEM
        head += be16(0)                            // fontDirectionHint
        head += be16(0)                            // indexToLocFormat = 0 (short)
        head += be16(0)                            // glyphDataFormat
        XCTAssertEqual(head.count, 54)

        var cmap: [UInt8] = []
        cmap += be16(0); cmap += be16(1)           // version, numTables
        cmap += be16(3); cmap += be16(1); cmap += be32(12) // platformID=3(windows) encodingID=1 offset=12
        var glyphIdArray = [UInt8](repeating: 0, count: 256)
        glyphIdArray[65] = 1 // 'A' -> glyphId 1
        cmap += be16(0); cmap += be16(6 + 256); cmap += be16(0) // format0: format,length,language
        cmap += glyphIdArray
        XCTAssertEqual(cmap.count, 12 + 6 + 256)

        // glyf: glyph0不存在(loca[0]==loca[1])，glyph1从offset0开始，20字节(19实际+1填充)
        var glyf: [UInt8] = []
        glyf += be16(1)                             // numberOfContours = 1
        glyf += be16(0); glyf += be16(0); glyf += be16(0); glyf += be16(0) // xMin/yMin/xMax/yMax
        glyf += be16(0)                              // endPtsOfContours[0] = 0 (只有1个点)
        glyf += be16(0)                              // instructionLength = 0
        glyf += [0x01]                                // flags[0] = 0x01 (on-curve, 1字节)
        glyf += be16(100)                             // xCoordinate[0] = 100 (Int16)
        glyf += be16(200)                             // yCoordinate[0] = 200 (Int16)
        glyf += [0x00]                                 // 1字节填充，凑偶数长度方便loca表示
        XCTAssertEqual(glyf.count, 20)

        var loca: [UInt8] = []
        loca += be16(0); loca += be16(0); loca += be16(10) // 0,0,20(=10*2) —— short格式存的是offset/2

        var maxp: [UInt8] = []
        maxp += be32(0x00010000)                      // version
        maxp += be16(2)                                // numGlyphs = 2 (含missing char)
        maxp += be16(1)                                 // maxPoints
        maxp += be16(1)                                 // maxContours（要 >= 我们glyph的numberOfContours=1）
        maxp += be16(0); maxp += be16(0)                 // maxCompositePoints, maxCompositeContours
        maxp += be16(0); maxp += be16(0); maxp += be16(0) // maxZones, maxTwilightPoints, maxStorage
        maxp += be16(0); maxp += be16(0); maxp += be16(0) // maxFunctionDefs, maxInstructionDefs, maxStackElements
        maxp += be16(0); maxp += be16(0); maxp += be16(0) // maxSizeOfInstructions, maxComponentElements, maxComponentDepth
        XCTAssertEqual(maxp.count, 32)

        let numTables = 5
        let headerSize = 12
        let dirSize = numTables * 16
        var offset = headerSize + dirSize
        let headOffset = offset; offset += head.count
        let cmapOffset = offset; offset += cmap.count
        let locaOffset = offset; offset += loca.count
        let maxpOffset = offset; offset += maxp.count
        let glyfOffset = offset; offset += glyf.count

        var file: [UInt8] = []
        file += be32(0x00010000); file += be16(numTables); file += be16(0); file += be16(0); file += be16(0)

        func tag(_ s: String) -> [UInt8] { Array(s.utf8) }
        func dirEntry(_ t: String, _ off: Int, _ len: Int) -> [UInt8] {
            tag(t) + be32(0) + be32(off) + be32(len)
        }
        file += dirEntry("head", headOffset, head.count)
        file += dirEntry("cmap", cmapOffset, cmap.count)
        file += dirEntry("loca", locaOffset, loca.count)
        file += dirEntry("maxp", maxpOffset, maxp.count)
        file += dirEntry("glyf", glyfOffset, glyf.count)

        file += head + cmap + loca + maxp + glyf
        return file
    }

    func testQueryTTFParsesMinimalFont() {
        let bytes = buildMinimalTTF()
        let font = QueryTTF(bytes)

        XCTAssertEqual(font.getGlyfIdByUnicode(65), 1) // 'A' -> glyphId 1
        let glyfString = font.getGlyfByUnicode(65)
        XCTAssertEqual(glyfString, "100,200") // 唯一一个点的坐标
        XCTAssertEqual(font.getUnicodeByGlyf("100,200"), 65) // 反查

        XCTAssertEqual(font.getGlyfIdByUnicode(66), 0) // 未映射的Unicode返回0
        XCTAssertTrue(font.isBlankUnicode(0x0020))
        XCTAssertFalse(font.isBlankUnicode(65))
    }

    // MARK: - BookSource：书源JSON解析

    func testBookSourceDecode() throws {
        let json = """
        {
          "bookSourceUrl": "https://example.com",
          "bookSourceName": "示例书源",
          "bookSourceGroup": "测试",
          "bookSourceType": 0,
          "enabled": true,
          "header": "{\\"User-Agent\\":\\"Mozilla/5.0\\"}",
          "searchUrl": "https://example.com/search?wd={{key}}",
          "ruleSearch": {
            "bookList": ".book-list .item",
            "name": "class.name@text",
            "author": "class.author@text",
            "bookUrl": "class.name@href"
          },
          "ruleBookInfo": {
            "init": "class.info",
            "name": "class.name@text",
            "tocUrl": "class.toc-link@href"
          },
          "ruleToc": {
            "chapterList": ".chapter-list li",
            "chapterName": "a@text",
            "chapterUrl": "a@href"
          },
          "ruleContent": {
            "content": "#content@html"
          }
        }
        """
        let sources = try BookSourceImporter.parse(json)
        XCTAssertEqual(sources.count, 1)
        let source = sources[0]

        XCTAssertEqual(source.bookSourceUrl, "https://example.com")
        XCTAssertEqual(source.bookSourceType, .text)
        XCTAssertEqual(source.parsedHeaderMap()["User-Agent"], "Mozilla/5.0")
        XCTAssertEqual(source.ruleSearch?.bookList, ".book-list .item")
        XCTAssertEqual(source.ruleBookInfo?.initRule, "class.info") // JSON "init" 映射到 initRule
        XCTAssertEqual(source.ruleToc?.chapterName, "a@text")
        XCTAssertEqual(source.ruleContent?.content, "#content@html")
        XCTAssertEqual(source.getDisplayNameGroup(), "示例书源 (测试)")
    }

    func testBookSourceArrayDecode() throws {
        let json = """
        [
          {"bookSourceUrl":"https://a.com","bookSourceName":"A"},
          {"bookSourceUrl":"https://b.com","bookSourceName":"B","bookSourceType":1}
        ]
        """
        let sources = try BookSourceImporter.parse(json)
        XCTAssertEqual(sources.count, 2)
        XCTAssertEqual(sources[1].bookSourceType, .audio)
    }

    // MARK: - SourceRateLimiter

    func testRateLimiterThrottlesWithinWindow() async {
        let limiter = SourceRateLimiter()
        let key = "test-source"
        let start = Date()

        // "2/200" = 200ms内最多2个请求，第3个应该被卡住等窗口腾出空位
        await limiter.acquire(key: key, concurrentRate: "2/200")
        await limiter.acquire(key: key, concurrentRate: "2/200")
        await limiter.acquire(key: key, concurrentRate: "2/200")

        let elapsed = Date().timeIntervalSince(start)
        XCTAssertGreaterThan(elapsed, 0.15) // 第3个至少应该等了接近200ms（留点余量防抖动）
    }

    func testRateLimiterNoRuleIsNoOp() async {
        let limiter = SourceRateLimiter()
        let start = Date()
        for _ in 0..<5 {
            await limiter.acquire(key: "k", concurrentRate: nil)
        }
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.1) // 没配置限流规则应该几乎瞬间完成
    }

    // MARK: - JS桥接扩展：base64/hex/加密/jsLib注入/source绑定

    func testJSBridgeBase64AndHex() {
        let rule = AnalyzeRule()
        let encoded = rule.evalJS(#"java.base64Encode("hello")"#) as? String
        XCTAssertEqual(encoded, "aGVsbG8=")
        let decoded = rule.evalJS(#"java.base64Decode("aGVsbG8=")"#) as? String
        XCTAssertEqual(decoded, "hello")
        let hex = rule.evalJS(#"java.hexDecodeToString("68656c6c6f")"#) as? String
        XCTAssertEqual(hex, "hello")
    }

    func testJSBridgeSymmetricCryptoAESRoundTrip() {
        let rule = AnalyzeRule()
        let script = #"""
        var c = java.createSymmetricCrypto("AES/CBC/PKCS5Padding", "0123456789abcdef", "abcdef0123456789");
        var enc = c.encryptBase64("hello world");
        var c2 = java.createSymmetricCrypto("AES/CBC/PKCS5Padding", "0123456789abcdef", "abcdef0123456789");
        c2.decryptStr(enc);
        """#
        let result = rule.evalJS(script) as? String
        XCTAssertEqual(result, "hello world")
    }

    func testJSLibInjectionMakesHelperFunctionAvailable() {
        let rule = AnalyzeRule()
        rule.jsLib = "function myHelper(x) { return x + '_suffix'; }"
        let result = rule.evalJS("myHelper('abc')") as? String
        XCTAssertEqual(result, "abc_suffix")
    }

    func testSourceContextBinding() {
        final class MockSourceContext: SourceJSContext {
            var stored = ""
            func getVariable() -> String { stored }
            func setVariable(_ value: String) { stored = value }
            func getLoginHeader() -> String? { "token-abc" }
            func getLoginInfoMap() -> [String: String] { ["user": "tom"] }
        }
        let mock = MockSourceContext()
        let rule = AnalyzeRule()
        rule.sourceContext = mock

        _ = rule.evalJS(#"source.setVariable("hi")"#)
        XCTAssertEqual(mock.stored, "hi")

        let readBack = rule.evalJS("source.getVariable()") as? String
        XCTAssertEqual(readBack, "hi")

        let loginHeader = rule.evalJS("source.getLoginHeader()") as? String
        XCTAssertEqual(loginHeader, "token-abc")
    }
}
