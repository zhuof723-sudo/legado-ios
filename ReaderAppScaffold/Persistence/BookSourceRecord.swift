import Foundation
import SwiftData
import LegadoRuleEngine

/// 持久化的书源记录：数据库里存原始JSON（导入时怎么来的就怎么存，方便以后重新解析/导出/分享），
/// 解析出来的 `BookSource` 在读取时按需 decode，不重复存一遍字段。
@Model
public final class BookSourceRecord {
    @Attribute(.unique) public var bookSourceUrl: String
    public var bookSourceName: String
    public var bookSourceGroup: String?
    public var rawJSON: String
    public var enabled: Bool
    public var customOrder: Int
    public var importedAt: Date

    public init(source: BookSource, rawJSON: String, customOrder: Int = 0) {
        self.bookSourceUrl = source.bookSourceUrl
        self.bookSourceName = source.bookSourceName
        self.bookSourceGroup = source.bookSourceGroup
        self.rawJSON = rawJSON
        self.enabled = source.enabled
        self.customOrder = customOrder
        self.importedAt = Date()
    }

    /// 按需重新解析出完整的 BookSource（含所有规则字段），SwiftData 里只存了摘要字段用于列表展示
    public func decodeSource() -> BookSource? {
        try? BookSourceImporter.parse(rawJSON).first
    }
}
