import Foundation

// MARK: - 段评数据模型（参考 legado-E ReviewRule 解析结果）

/// 单条段评
public struct Review: Identifiable, Equatable, Sendable {
    public let id: String
    /// 发布者用户名
    public let userName: String
    /// 发布者头像 URL
    public let avatarUrl: String?
    /// 评论内容
    public let content: String
    /// 发布时间（原始字符串，由书源规则解析）
    public let postTime: String?
    /// 点赞数
    public let likeCount: Int?
    /// 回复数
    public let replyCount: Int?

    public init(
        id: String = UUID().uuidString,
        userName: String,
        avatarUrl: String? = nil,
        content: String,
        postTime: String? = nil,
        likeCount: Int? = nil,
        replyCount: Int? = nil
    ) {
        self.id = id
        self.userName = userName
        self.avatarUrl = avatarUrl
        self.content = content
        self.postTime = postTime
        self.likeCount = likeCount
        self.replyCount = replyCount
    }
}

/// 段评获取结果
public struct ReviewResult: Sendable {
    /// 评论列表
    public let reviews: [Review]
    /// 是否还有更多（用于分页）
    public let hasMore: Bool

    public init(reviews: [Review], hasMore: Bool = false) {
        self.reviews = reviews
        self.hasMore = hasMore
    }
}

// MARK: - 段落评论索引（用于在阅读界面中定位某段的评论）

/// 段落与评论的关联信息
public struct ParagraphReviewInfo: Sendable {
    /// 段落索引（在章节中的段落序号）
    public let paragraphIndex: Int
    /// 段落文本（用于请求评论时传给书源）
    public let paragraphText: String
    /// 评论数（用于显示在评论按钮上）
    public var reviewCount: Int

    public init(paragraphIndex: Int, paragraphText: String, reviewCount: Int = 0) {
        self.paragraphIndex = paragraphIndex
        self.paragraphText = paragraphText
        self.reviewCount = reviewCount
    }
}
