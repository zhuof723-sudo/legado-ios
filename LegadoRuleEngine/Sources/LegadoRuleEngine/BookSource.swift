import Foundation

/// 对应 legado: data/entities/BookSource.kt + data/entities/rule/*.kt
/// 书源 JSON 的数据模型。书源是用户从网上导入的 JSON（单个对象或对象数组），
/// 描述一个小说站点怎么搜索/怎么找目录/怎么取正文——本文件只是"把 JSON 解析成结构体"，
/// 具体规则字符串怎么执行交给 `AnalyzeRule` / `AnalyzeUrl`。
///
/// 字段名和 legado 原版 JSON key 完全一致（驼峰命名），可以直接导入现成的书源文件。

// MARK: - 书源类型

public enum BookSourceType: Int, Codable, Equatable {
    case text = 0
    case audio = 1
    case image = 2
    case file = 3
    case video = 4
}

// MARK: - 搜索结果 / 发现结果 通用字段（对应 BookListRule 接口）

public struct SearchRule: Codable, Equatable {
    /// 校验关键字（书源校验工具用，正常抓取用不到）
    public var checkKeyWord: String?
    public var bookList: String?
    public var name: String?
    public var author: String?
    public var intro: String?
    public var kind: String?
    public var lastChapter: String?
    public var updateTime: String?
    public var bookUrl: String?
    public var coverUrl: String?
    public var wordCount: String?

    public init(
        checkKeyWord: String? = nil, bookList: String? = nil, name: String? = nil,
        author: String? = nil, intro: String? = nil, kind: String? = nil,
        lastChapter: String? = nil, updateTime: String? = nil, bookUrl: String? = nil,
        coverUrl: String? = nil, wordCount: String? = nil
    ) {
        self.checkKeyWord = checkKeyWord; self.bookList = bookList; self.name = name
        self.author = author; self.intro = intro; self.kind = kind
        self.lastChapter = lastChapter; self.updateTime = updateTime; self.bookUrl = bookUrl
        self.coverUrl = coverUrl; self.wordCount = wordCount
    }
}

public struct ExploreRule: Codable, Equatable {
    public var bookList: String?
    public var name: String?
    public var author: String?
    public var intro: String?
    public var kind: String?
    public var lastChapter: String?
    public var updateTime: String?
    public var bookUrl: String?
    public var coverUrl: String?
    public var wordCount: String?

    public init(
        bookList: String? = nil, name: String? = nil, author: String? = nil,
        intro: String? = nil, kind: String? = nil, lastChapter: String? = nil,
        updateTime: String? = nil, bookUrl: String? = nil, coverUrl: String? = nil,
        wordCount: String? = nil
    ) {
        self.bookList = bookList; self.name = name; self.author = author
        self.intro = intro; self.kind = kind; self.lastChapter = lastChapter
        self.updateTime = updateTime; self.bookUrl = bookUrl; self.coverUrl = coverUrl
        self.wordCount = wordCount
    }
}

// MARK: - 详情页规则

public struct BookInfoRule: Codable, Equatable {
    public var initRule: String?  // JSON key 是 "init"，Swift里 init是关键字，用 CodingKeys 映射
    public var name: String?
    public var author: String?
    public var intro: String?
    public var kind: String?
    public var lastChapter: String?
    public var updateTime: String?
    public var coverUrl: String?
    public var tocUrl: String?
    public var wordCount: String?
    public var canReName: String?
    public var downloadUrls: String?

    enum CodingKeys: String, CodingKey {
        case initRule = "init"
        case name, author, intro, kind, lastChapter, updateTime
        case coverUrl, tocUrl, wordCount, canReName, downloadUrls
    }

    public init(
        initRule: String? = nil, name: String? = nil, author: String? = nil,
        intro: String? = nil, kind: String? = nil, lastChapter: String? = nil,
        updateTime: String? = nil, coverUrl: String? = nil, tocUrl: String? = nil,
        wordCount: String? = nil, canReName: String? = nil, downloadUrls: String? = nil
    ) {
        self.initRule = initRule; self.name = name; self.author = author
        self.intro = intro; self.kind = kind; self.lastChapter = lastChapter
        self.updateTime = updateTime; self.coverUrl = coverUrl; self.tocUrl = tocUrl
        self.wordCount = wordCount; self.canReName = canReName; self.downloadUrls = downloadUrls
    }
}

// MARK: - 目录页规则

public struct TocRule: Codable, Equatable {
    public var preUpdateJs: String?
    public var chapterList: String?
    public var chapterName: String?
    public var chapterUrl: String?
    public var formatJs: String?
    public var wordCount: String?
    public var isVolume: String?
    public var isVip: String?
    public var isPay: String?
    public var updateTime: String?
    public var nextTocUrl: String?

    public init(
        preUpdateJs: String? = nil, chapterList: String? = nil, chapterName: String? = nil,
        chapterUrl: String? = nil, formatJs: String? = nil, wordCount: String? = nil,
        isVolume: String? = nil,
        isVip: String? = nil, isPay: String? = nil, updateTime: String? = nil,
        nextTocUrl: String? = nil
    ) {
        self.preUpdateJs = preUpdateJs; self.chapterList = chapterList; self.chapterName = chapterName
        self.chapterUrl = chapterUrl; self.formatJs = formatJs; self.wordCount = wordCount
        self.isVolume = isVolume; self.isVip = isVip; self.isPay = isPay; self.updateTime = updateTime
        self.nextTocUrl = nextTocUrl
    }
}

// MARK: - 正文页规则

public struct ContentRule: Codable, Equatable {
    public var content: String?
    /// 副文规则，拼接在正文后面或用于获取歌词等
    public var subContent: String?
    /// 有些网站标题只能从正文页取
    public var title: String?
    public var nextContentUrl: String?
    public var webJs: String?
    public var sourceRegex: String?
    public var replaceRegex: String?
    /// 默认大小居中，FULL最大宽度
    public var imageStyle: String?
    /// 图片bytes二次解密js，返回解密后的bytes
    public var imageDecode: String?
    /// 购买操作：js 或包含 {{js}} 的url
    public var payAction: String?
    public var callBackJs: String?

    public init(
        content: String? = nil, subContent: String? = nil, title: String? = nil,
        nextContentUrl: String? = nil, webJs: String? = nil, sourceRegex: String? = nil,
        replaceRegex: String? = nil, imageStyle: String? = nil, imageDecode: String? = nil,
        payAction: String? = nil, callBackJs: String? = nil
    ) {
        self.content = content; self.subContent = subContent; self.title = title
        self.nextContentUrl = nextContentUrl; self.webJs = webJs; self.sourceRegex = sourceRegex
        self.replaceRegex = replaceRegex; self.imageStyle = imageStyle; self.imageDecode = imageDecode
        self.payAction = payAction; self.callBackJs = callBackJs
    }
}

// MARK: - 段评规则

public struct ReviewRule: Codable, Equatable {
    public var reviewUrl: String?
    public var avatarRule: String?
    public var contentRule: String?
    public var postTimeRule: String?
    public var reviewQuoteUrl: String?
    public var voteUpUrl: String?
    public var voteDownUrl: String?
    public var postReviewUrl: String?
    public var postQuoteUrl: String?
    public var deleteUrl: String?

    public init(
        reviewUrl: String? = nil, avatarRule: String? = nil, contentRule: String? = nil,
        postTimeRule: String? = nil, reviewQuoteUrl: String? = nil, voteUpUrl: String? = nil,
        voteDownUrl: String? = nil, postReviewUrl: String? = nil, postQuoteUrl: String? = nil,
        deleteUrl: String? = nil
    ) {
        self.reviewUrl = reviewUrl; self.avatarRule = avatarRule; self.contentRule = contentRule
        self.postTimeRule = postTimeRule; self.reviewQuoteUrl = reviewQuoteUrl
        self.voteUpUrl = voteUpUrl; self.voteDownUrl = voteDownUrl
        self.postReviewUrl = postReviewUrl; self.postQuoteUrl = postQuoteUrl
        self.deleteUrl = deleteUrl
    }
}

// MARK: - 书源

public struct BookSource: Codable, Equatable {
    /// 地址，包括 http/https —— 书源的唯一标识
    public var bookSourceUrl: String = ""
    public var bookSourceName: String = ""
    public var bookSourceGroup: String?
    public var bookSourceType: BookSourceType = .text
    /// 详情页url正则，用来判断一个url是不是"详情页"
    public var bookUrlPattern: String?
    public var customOrder: Int = 0
    public var enabled: Bool = true
    public var enabledExplore: Bool = true
    public var jsLib: String?
    public var enabledCookieJar: Bool? = true
    /// 并发率，形如 "1/1000"（1000ms内最多1个请求）
    public var concurrentRate: String?
    /// 请求头，JSON对象字符串，如 {"User-Agent":"..."}
    public var header: String?
    public var loginUrl: String?
    public var loginUi: String?
    public var loginCheckJs: String?
    /// 用户在登录面板里填好的表单值，比如 {"邮箱":"x@y.com","密码":"..."}
    public var loginInfoMap: [String: String] = [:]
    /// 登录后存下来的鉴权字符串（apiKey/bearer/token等），之后每条请求会拼到 header 里
    public var loginHeader: String?
    /// 封面解密js
    public var coverDecodeJs: String?
    public var bookSourceComment: String?
    public var variableComment: String?
    public var lastUpdateTime: Int64 = 0
    public var respondTime: Int64 = 180_000
    public var weight: Int = 0
    public var exploreUrl: String?
    public var exploreScreen: String?
    public var ruleExplore: ExploreRule?
    public var searchUrl: String?
    public var ruleSearch: SearchRule?
    public var ruleBookInfo: BookInfoRule?
    public var ruleToc: TocRule?
    public var ruleContent: ContentRule?
    public var ruleReview: ReviewRule?
    public var eventListener: Bool = false
    public var customButton: Bool = false

    public init() {}

    enum CodingKeys: String, CodingKey {
        case bookSourceUrl, bookSourceName, bookSourceGroup, bookSourceType
        case bookUrlPattern, customOrder, enabled, enabledExplore, jsLib
        case enabledCookieJar, concurrentRate, header, loginUrl, loginUi
        case loginCheckJs, coverDecodeJs, bookSourceComment, variableComment
        case lastUpdateTime, respondTime, weight, exploreUrl, exploreScreen
        case searchUrl, eventListener, customButton
        case ruleExplore, ruleSearch, ruleBookInfo, ruleToc, ruleContent, ruleReview
    }

    // 自定义解码：极少数书源文件里 ruleXxx 字段是"整个规则被再编码成一段JSON字符串"而不是JSON对象，
    // 这里两种形式都能吃（对应 Kotlin 里几个 rule 类各自注册的 jsonDeserializer）
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        bookSourceUrl = Self.decode(c, .bookSourceUrl, "")
        bookSourceName = Self.decode(c, .bookSourceName, "")
        bookSourceGroup = Self.decodeOpt(c, .bookSourceGroup)
        bookSourceType = Self.decode(c, .bookSourceType, .text)
        bookUrlPattern = Self.decodeOpt(c, .bookUrlPattern)
        customOrder = Self.decode(c, .customOrder, 0)
        enabled = Self.decode(c, .enabled, true)
        enabledExplore = Self.decode(c, .enabledExplore, true)
        jsLib = Self.decodeOpt(c, .jsLib)
        enabledCookieJar = Self.decodeOpt(c, .enabledCookieJar)
        concurrentRate = Self.decodeOpt(c, .concurrentRate)
        header = Self.decodeHeader(c, .header)
        loginUrl = Self.decodeOpt(c, .loginUrl)
        loginUi = Self.decodeOpt(c, .loginUi)
        loginCheckJs = Self.decodeOpt(c, .loginCheckJs)
        coverDecodeJs = Self.decodeOpt(c, .coverDecodeJs)
        bookSourceComment = Self.decodeOpt(c, .bookSourceComment)
        variableComment = Self.decodeOpt(c, .variableComment)
        lastUpdateTime = Self.decode(c, .lastUpdateTime, 0)
        respondTime = Self.decode(c, .respondTime, 180_000)
        weight = Self.decode(c, .weight, 0)
        exploreUrl = Self.decodeOpt(c, .exploreUrl)
        exploreScreen = Self.decodeOpt(c, .exploreScreen)
        searchUrl = Self.decodeOpt(c, .searchUrl)
        eventListener = Self.decode(c, .eventListener, false)
        customButton = Self.decode(c, .customButton, false)

        ruleExplore = Self.decodeFlexible(ExploreRule.self, c, .ruleExplore)
        ruleSearch = Self.decodeFlexible(SearchRule.self, c, .ruleSearch)
        ruleBookInfo = Self.decodeFlexible(BookInfoRule.self, c, .ruleBookInfo)
        ruleToc = Self.decodeFlexible(TocRule.self, c, .ruleToc)
        ruleContent = Self.decodeFlexible(ContentRule.self, c, .ruleContent)
        ruleReview = Self.decodeFlexible(ReviewRule.self, c, .ruleReview)
    }

    /// 宽容解码：单字段类型不符就回退默认值，避免一条书源因某个字段类型不对导致整包导入失败
    private static func decode<T: Decodable>(
        _ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys, _ fallback: T
    ) -> T {
        ((try? container.decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
    }

    private static func decodeOpt<T: Decodable>(
        _ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys
    ) -> T? {
        (try? container.decodeIfPresent(T.self, forKey: key)) ?? nil
    }

    /// header 既可能是 JSON 字符串，也可能被某些导出工具序列化成对象，两种都吃
    private static func decodeHeader(
        _ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys
    ) -> String? {
        if let s = (try? container.decodeIfPresent(String.self, forKey: key)) ?? nil {
            return s
        }
        if let obj = (try? container.decodeIfPresent([String: String].self, forKey: key)) ?? nil,
           let data = try? JSONSerialization.data(withJSONObject: obj),
           let s = String(data: data, encoding: .utf8) {
            return s
        }
        return nil
    }

    private static func decodeFlexible<T: Decodable>(
        _ type: T.Type,
        _ container: KeyedDecodingContainer<CodingKeys>,
        _ key: CodingKeys
    ) -> T? {
        if let obj = try? container.decodeIfPresent(T.self, forKey: key) {
            return obj
        }
        if let s = try? container.decodeIfPresent(String.self, forKey: key),
           !s.isEmpty, let data = s.data(using: .utf8) {
            return try? JSONDecoder().decode(T.self, from: data)
        }
        return nil
    }

    // MARK: - 惰性创建（对应 Kotlin 的 getSearchRule() 等）

    public mutating func getSearchRule() -> SearchRule {
        if let r = ruleSearch { return r }
        let r = SearchRule(); ruleSearch = r; return r
    }
    public mutating func getExploreRule() -> ExploreRule {
        if let r = ruleExplore { return r }
        let r = ExploreRule(); ruleExplore = r; return r
    }
    public mutating func getBookInfoRule() -> BookInfoRule {
        if let r = ruleBookInfo { return r }
        let r = BookInfoRule(); ruleBookInfo = r; return r
    }
    public mutating func getTocRule() -> TocRule {
        if let r = ruleToc { return r }
        let r = TocRule(); ruleToc = r; return r
    }
    public mutating func getContentRule() -> ContentRule {
        if let r = ruleContent { return r }
        let r = ContentRule(); ruleContent = r; return r
    }

    public func getTag() -> String { bookSourceName }
    public func getKey() -> String { bookSourceUrl }

    /// 请求头字符串（JSON对象格式）解析成字典，直接喂给 AnalyzeUrl(headerMap:)
    public func parsedHeaderMap() -> [String: String] {
        guard let header = header, let data = header.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        var result: [String: String] = [:]
        for (k, v) in obj { result[k] = "\(v)" }
        return result
    }

    public func getDisplayNameGroup() -> String {
        guard let group = bookSourceGroup, !group.trimmingCharacters(in: .whitespaces).isEmpty else {
            return bookSourceName
        }
        return "\(bookSourceName) (\(group))"
    }
}

// MARK: - 批量导入

public enum BookSourceImporter {
    /// 把单个 BookSource 重新编码成 JSON 字符串。用于把临时状态写回 rawJSON
    public static func encode(_ source: BookSource) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(source)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    /// 导入书源JSON：支持单个对象或对象数组（legado 导出文件两种格式都有可能遇到）
    public static func parse(_ data: Data) throws -> [BookSource] {
        let decoder = JSONDecoder()
        if let list = try? decoder.decode([BookSource].self, from: data) {
            return list
        }
        let single = try decoder.decode(BookSource.self, from: data)
        return [single]
    }

    public static func parse(_ jsonString: String) throws -> [BookSource] {
        guard let data = jsonString.data(using: .utf8) else {
            throw NSError(domain: "BookSourceImporter", code: -1, userInfo: [NSLocalizedDescriptionKey: "字符串无法转成utf8"])
        }
        return try parse(data)
    }
}
