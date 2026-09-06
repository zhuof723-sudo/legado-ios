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
    /// 登录面板里用户填的字段（邮箱/密码/自定义字段等）
    public var loginInfoJSON: String?
    /// 登录后保存的鉴权串（apiKey/bearer 等）
    public var loginHeader: String?

    public init(source: BookSource, rawJSON: String, customOrder: Int = 0) {
        self.bookSourceUrl = source.bookSourceUrl
        self.bookSourceName = source.bookSourceName
        self.bookSourceGroup = source.bookSourceGroup
        self.rawJSON = rawJSON
        self.enabled = source.enabled
        self.customOrder = customOrder
        self.importedAt = Date()
        self.loginHeader = source.loginHeader
        if !source.loginInfoMap.isEmpty,
           let data = try? JSONSerialization.data(withJSONObject: source.loginInfoMap),
           let s = String(data: data, encoding: .utf8) {
            self.loginInfoJSON = s
        }
    }

    /// 按需重新解析出完整的 BookSource（含所有规则字段），SwiftData 里只存了摘要字段用于列表展示
    public func decodeSource() -> BookSource? {
        guard var src = try? BookSourceImporter.parse(rawJSON).first else { return nil }
        if let json = loginInfoJSON,
           let data = json.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
            src.loginInfoMap = obj
        }
        src.loginHeader = loginHeader
        return src
    }

    /// 把 JS 里 source.putLoginInfo(json) 写回字段
    public func writeLoginInfo(_ info: [String: String]) {
        if info.isEmpty {
            loginInfoJSON = nil
        } else if let data = try? JSONSerialization.data(withJSONObject: info),
                  let s = String(data: data, encoding: .utf8) {
            loginInfoJSON = s
        }
    }

    /// 把 JS 里 source.putLoginHeader(value) 写回字段
    public func writeLoginHeader(_ value: String?) {
        loginHeader = value
    }
}
