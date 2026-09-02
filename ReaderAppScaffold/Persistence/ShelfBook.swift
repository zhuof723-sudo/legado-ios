import Foundation
import SwiftData

/// 书架里的一本书：记录来自哪个书源、看到哪一章
@Model
public final class ShelfBook {
    @Attribute(.unique) public var bookUrl: String
    public var sourceUrl: String
    public var name: String
    public var author: String
    public var intro: String
    public var coverUrl: String
    public var lastChapterTitle: String
    public var lastReadChapterIndex: Int
    public var totalChapters: Int = 0
    public var lastReadChapterTitle: String?
    public var addedAt: Date
    public var lastReadAt: Date?

    public init(
        bookUrl: String, sourceUrl: String, name: String, author: String,
        intro: String = "", coverUrl: String = "", lastChapterTitle: String = ""
    ) {
        self.bookUrl = bookUrl
        self.sourceUrl = sourceUrl
        self.name = name
        self.author = author
        self.intro = intro
        self.coverUrl = coverUrl
        self.lastChapterTitle = lastChapterTitle
        self.lastReadChapterIndex = 0
        self.totalChapters = 0
        self.lastReadChapterTitle = nil
        self.addedAt = Date()
        self.lastReadAt = nil
    }
}
