import Foundation
import Combine
import LegadoRuleEngine

/// 书源运行时兼容层。
///
/// 视图层（搜索/发现/详情/目录/正文/段评/登录）全部继续调用 `BookSourceRuntime`
/// 的旧签名；本类在 app target 内声明同名类，遮蔽 `LegadoRuleEngine` 包里的旧实现
/// （Swift 名字解析：本地模块声明优先于 import 的包）。
///
/// 路由策略：
/// - 搜索 / 发现 / 详情 / 目录 / 正文 → 新版书源引擎（Modules/Core：多模式规则
///   引擎 @css/@xpath/@json/@js/正则、jsLib+headless WebView、CookieStore、限流、
///   TOC/详情/章节缓存），即兼容性的主要来源。
/// - 段评获取 / 段评点击脚本 / 登录面板动作 → 旧包实现兜底（新引擎暂无 ruleReview
///   解析路径；段评点击依赖旧 AnalyzeRule.evalJS 行为）。
/// - 登录态 / 源变量 → 初始化时把旧 UserDefaults 存储 seed 进新引擎的
///   LoginManager / BookSourceRuntimeStateStore，保证升级后不用重新登录。
public final class BookSourceRuntime {

    /// 视图持有的是旧模型；转换出的新模型作为解析用快照。
    public var source: BookSource {
        didSet { bsSource = Self.convert(source); legacy.source = source }
    }
    private(set) var bsSource: BSBookSource

    /// 旧包 runtime：只用于段评/登录动作等尚未迁移的能力，以及视图的 handler 透传。
    private let legacy: LegadoRuleEngine.BookSourceRuntime
    private let fetcher = BookSourceFetcher.shared

    public init(_ source: BookSource) {
        self.source = source
        self.bsSource = Self.convert(source)
        self.legacy = LegadoRuleEngine.BookSourceRuntime(source)
        seedLegacyState(into: source)
    }

    // MARK: - handler 透传（视图直接赋值，行为对齐旧实现）

    public var sourceContext: SourceJSContext? {
        get { legacy.sourceContext }
        set { legacy.sourceContext = newValue }
    }
    public var toastHandler: ((_ msg: String) -> Void)? {
        get { legacy.toastHandler }
        set { legacy.toastHandler = newValue }
    }
    public var browserOpener: ((_ url: String, _ title: String?) -> Void)? {
        get { legacy.browserOpener }
        set { legacy.browserOpener = newValue }
    }
    public var refreshExploreHandler: (() -> Void)? {
        get { legacy.refreshExploreHandler }
        set { legacy.refreshExploreHandler = newValue }
    }
    public var searchBookHandler: ((_ keyword: String, _ sourceFilter: String?) -> Void)? {
        get { legacy.searchBookHandler }
        set { legacy.searchBookHandler = newValue }
    }
    public var sourceKeyValueStore: SourceKeyValueStore? {
        get { legacy.sourceKeyValueStore }
        set { legacy.sourceKeyValueStore = newValue }
    }
    public var loginInfoPersister: ((_ info: [String: String]) -> Void)? {
        get { legacy.loginInfoPersister }
        set { legacy.loginInfoPersister = newValue }
    }
    public var loginActionHandler: ((_ action: String, _ info: [String: String]) -> Void)? {
        get { legacy.loginActionHandler }
        set { legacy.loginActionHandler = newValue }
    }

    public func resolveHeaderMap() -> [String: String] { legacy.resolveHeaderMap() }
    public func persistLoginInfo(_ info: [String: String]) {
        legacy.persistLoginInfo(info)
        LoginManager.shared.storeLoginInfo(sourceUrl: source.bookSourceUrl, info: info)
    }
    public func handleLoginAction(_ action: String, _ info: [String: String]) {
        legacy.handleLoginAction(action, info)
    }

    // MARK: - 搜索

    public func search(_ keyword: String, page: Int = 1, resultLimit: Int = 200) async throws -> [SearchResult] {
        let books = try await fetcher.search(
            query: keyword,
            in: refreshedBSSource(),
            page: max(1, page),
            failureMode: .emptyResult
        )
        return books.prefix(resultLimit).map {
            SearchResult(
                name: $0.name, author: $0.author, intro: $0.intro, kind: $0.kind,
                lastChapter: $0.lastChapter, bookUrl: $0.bookUrl, coverUrl: $0.coverUrl,
                wordCount: $0.wordCount
            )
        }
    }

    // MARK: - 发现

    public func exploreKinds() -> [ExploreKindInfo] { legacy.exploreKinds() }

    public func exploreKindsCached(
        cacheTTL: TimeInterval = 900,
        forceRefresh: Bool = false
    ) async -> [ExploreKindInfo] {
        await legacy.exploreKindsCached(cacheTTL: cacheTTL, forceRefresh: forceRefresh)
    }

    public func clearExploreCache() async { await legacy.clearExploreCache() }

    public func explore(
        _ kind: ExploreKindInfo,
        page: Int = 1,
        resultLimit: Int = 20,
        cacheTTL: TimeInterval = 900,
        forceRefresh: Bool = false
    ) async throws -> [SearchResult] {
        // 发现分类的解析交给新引擎（URL 模板 + @js: 求值 + ruleExplore）。
        let item = ModernParserBridge.DiscoverItem(title: kind.title, url: kind.url)
        let bs = refreshedBSSource()
        let books: [BSOnlineBook]
        do {
            books = try await fetcher.discoverBooks(from: item, page: max(1, page), in: bs)
        } catch {
            // 数据类错误交给新引擎结果；其它异常保留旧语义抛出。
            throw error
        }
        return books.prefix(resultLimit).map {
            SearchResult(
                name: $0.name, author: $0.author, intro: $0.intro, kind: $0.kind,
                lastChapter: $0.lastChapter, bookUrl: $0.bookUrl, coverUrl: $0.coverUrl,
                wordCount: $0.wordCount
            )
        }
    }

    // MARK: - 详情

    public func getBookInfo(bookUrl: String, lightweight: Bool = false) async throws -> BookInfo {
        let bs = refreshedBSSource()
        let package = try await fetcher.fetchBookInfoPackage(url: bookUrl, source: bs)
        let book = package.onlineBook
        return BookInfo(
            name: book.name, author: book.author, intro: book.intro,
            coverUrl: book.coverUrl, kind: book.kind, tocUrl: book.tocUrl
        )
    }

    // MARK: - 目录

    public func getToc(
        bookUrl: String,
        maxPages: Int = 50,
        resolvedTocUrl: String? = nil
    ) async throws -> [ChapterInfo] {
        let bs = refreshedBSSource()
        var tocUrl = (resolvedTocUrl?.isEmpty == false) ? resolvedTocUrl! : bookUrl
        if resolvedTocUrl?.isEmpty != false, !bs.ruleBookInfo.tocUrl.isEmpty {
            // 详情页解析出目录地址时复用（对齐 legado analyzeBookInfo 的 tocUrl 步骤）。
            if let package = try? await fetcher.fetchBookInfoPackage(url: bookUrl, source: bs),
               !package.onlineBook.tocUrl.isEmpty {
                tocUrl = package.onlineBook.tocUrl
            }
        }
        let chapters = try await fetcher.fetchTOC(tocUrl: tocUrl, source: bs)
        return chapters.map { ChapterInfo(name: $0.title, url: $0.url) }
    }

    // MARK: - 正文

    public func getChapterContent(chapterUrl: String, maxPages: Int = 20) async throws -> ReaderChapterContent {
        let html = try await fetchChapterHTML(chapterUrl: chapterUrl)
        // 复用旧包的正文格式化：<comment>/TEXT 图片 → InlineReviewMarker token，
        // 阅读器侧的段评标记契约不变。
        return ReaderContentFormatter.format(html, baseURL: chapterUrl)
    }

    public func getContent(chapterUrl: String, maxPages: Int = 20) async throws -> String {
        try await fetchChapterHTML(chapterUrl: chapterUrl)
    }

    private func fetchChapterHTML(chapterUrl: String) async throws -> String {
        let bs = refreshedBSSource()
        let ref = BSOnlineChapterRef(index: 0, title: "", url: chapterUrl)
        let bookId = Self.transientBookID(for: chapterUrl)
        let package = try await fetcher.fetchChapterPackage(
            ref: ref, bookId: bookId, source: bs, chapterReferer: nil
        )
        _ = package
        // 优先取规范化 HTML（保留 <comment> 段评标记，供旧格式化器转 InlineReviewMarker）；
        // 落盘缺失时退回纯文本正文。
        if let html = fetcher.loadNormalizedChapterHTMLSync(
            bookId: bookId, chapterIndex: 0,
            expectedSourceURL: chapterUrl, expectedTOCTitle: nil
        ), !html.isEmpty {
            return html
        }
        return package.content
    }

    // MARK: - 段评 / 登录动作（旧实现兜底）

    public typealias RawReview = LegadoRuleEngine.BookSourceRuntime.RawReview

    public func getReviews(
        chapterUrl: String,
        paragraphText: String,
        page: Int = 1,
        reviewURL overrideURL: String? = nil
    ) async throws -> [RawReview] {
        try await legacy.getReviews(
            chapterUrl: chapterUrl, paragraphText: paragraphText,
            page: page, reviewURL: overrideURL
        )
    }

    public func executeInlineReviewAction(
        _ action: String,
        markerSource: String,
        chapterUrl: String,
        browserOpener: @escaping (_ url: String, _ title: String?) -> Void,
        toastHandler: ((_ message: String) -> Void)? = nil
    ) {
        legacy.executeInlineReviewAction(
            action, markerSource: markerSource, chapterUrl: chapterUrl,
            browserOpener: browserOpener, toastHandler: toastHandler
        )
    }

    public func executeLoginAction(_ action: String, infoMap: [String: String]) async throws -> String? {
        try await legacy.executeLoginAction(action, infoMap: infoMap)
    }

    // MARK: - 模型转换 / 状态 seed

    /// 视图可能在 runtime 创建后继续改 `source`（登录头、开关），
    /// 每次取数前同步一次，保证新引擎看到的是最新书源。
    private func refreshedBSSource() -> BSBookSource {
        bsSource = Self.convert(source)
        return bsSource
    }

    static func convert(_ src: BookSource) -> BSBookSource {
        // 两侧都是 tolerant Codable：JSON 往返即可无损迁移全部规则字段。
        guard let data = try? JSONEncoder().encode(src),
              let bs = try? JSONDecoder().decode(BSBookSource.self, from: data)
        else {
            return BSBookSource(bookSourceUrl: src.bookSourceUrl, bookSourceName: src.bookSourceName)
        }
        var out = bs
        out.id = deterministicID(for: src.bookSourceUrl)
        return out
    }

    /// 同一 URL 恒定映射到同一 UUID：TOC/详情缓存以 sourceId 为键，
    /// 避免每次 convert 生成新 UUID 导致缓存永不命中。
    static func deterministicID(for url: String) -> UUID {
        let digest = SHA256Hash.hex(Data(url.utf8))
        // 取前 32 个 hex 字符构造 UUID
        let chars = Array(digest.prefix(32))
        let groups = stride(from: 0, to: 32, by: 4).map { i in
            String(chars[(i)..<(i + 4)])
        }
        let s = [groups[0], groups[1], groups[2], groups[3], groups[4]].joined(separator: "-")
        return UUID(uuidString: s) ?? UUID()
    }

    /// 正文抓取需要一个 bookId 作为缓存分区键；按 URL 派生稳定值。
    static func transientBookID(for chapterUrl: String) -> UUID { deterministicID(for: "chapter|" + chapterUrl) }

    /// 把旧存储的登录态/源变量一次性 seed 给新引擎，保证升级后行为连续。
    private func seedLegacyState(into src: BookSource) {
        let url = src.bookSourceUrl
        guard !url.isEmpty else { return }
        if LoginManager.shared.getLoginInfo(sourceUrl: url) == nil, !src.loginInfoMap.isEmpty {
            LoginManager.shared.storeLoginInfo(sourceUrl: url, info: src.loginInfoMap)
        }
        if LoginManager.shared.getLoginHeader(sourceUrl: url) == nil,
           let header = src.loginHeader, !header.isEmpty {
            LoginManager.shared.storeLoginHeader(sourceUrl: url, raw: header)
        }
        if BookSourceRuntimeStateStore.shared.sourceVariableJSON(for: url) == nil,
           let variable = legacy.sourceKeyValueStore?.get("__source_variable"),
           !variable.isEmpty {
            BookSourceRuntimeStateStore.shared.setSourceVariableJSON(variable, for: url)
        }
    }
}

// MARK: - 轻量 SHA-256（避免在 app target 依赖 CryptoKit 头文件细节）

enum SHA256Hash {
    static func hex(_ data: Data) -> String {
        // FIPS 180-4 纯实现；只为派生稳定 UUID，不涉安全边界。
        var h: [UInt32] = [
            0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
            0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
        ]
        let k: [UInt32] = [
            0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
            0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
            0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
            0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
            0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
            0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
            0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
            0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
        ]
        var msg = [UInt8](data)
        let bitLen = UInt64(msg.count) * 8
        msg.append(0x80)
        while msg.count % 64 != 56 { msg.append(0) }
        for i in stride(from: 56, through: 0, by: -8) { msg.append(UInt8((bitLen >> UInt64(i)) & 0xff)) }

        func rotr(_ x: UInt32, _ n: UInt32) -> UInt32 { (x >> n) | (x << (32 - n)) }

        for chunk in stride(from: 0, to: msg.count, by: 64).map({ Array(msg[$0..<$0 + 64]) }) {
            var w = [UInt32](repeating: 0, count: 64)
            for i in 0..<16 {
                w[i] = (UInt32(chunk[i * 4]) << 24) | (UInt32(chunk[i * 4 + 1]) << 16)
                     | (UInt32(chunk[i * 4 + 2]) << 8) | UInt32(chunk[i * 4 + 3])
            }
            for i in 16..<64 {
                let s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3)
                let s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10)
                w[i] = w[i - 16] &+ s0 &+ w[i - 7] &+ s1
            }
            var a = h[0], b = h[1], c = h[2], d = h[3], e = h[4], f = h[5], g = h[6], hh = h[7]
            for i in 0..<64 {
                let S1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)
                let ch = (e & f) ^ (~e & g)
                let t1 = hh &+ S1 &+ ch &+ k[i] &+ w[i]
                let S0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)
                let maj = (a & b) ^ (a & c) ^ (b & c)
                let t2 = S0 &+ maj
                hh = g; g = f; f = e; e = d &+ t1; d = c; c = b; b = a; a = t1 &+ t2
            }
            h[0] = h[0] &+ a; h[1] = h[1] &+ b; h[2] = h[2] &+ c; h[3] = h[3] &+ d
            h[4] = h[4] &+ e; h[5] = h[5] &+ f; h[6] = h[6] &+ g; h[7] = h[7] &+ hh
        }
        return h.map { String(format: "%08x", $0) }.joined()
    }
}
