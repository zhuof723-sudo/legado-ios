import Foundation
import LegadoRuleEngine

/// 让 BookSourceRecord 作为 source 对象的实现。
/// 把登录态、登录表单持久化代理给 SwiftData 模型。
public final class SourceJSContextImpl: SourceJSContext {
    public weak var record: BookSourceRecord?
    public var onPutLoginInfo: (([String: String]) -> Void)?
    public var onPutLoginHeader: ((String?) -> Void)?

    public init(record: BookSourceRecord? = nil) {
        self.record = record
    }

    public func getVariable() -> String {
        // 书源级别的持久变量（聚合书源配置等）
        // 暂用 UserDefaults 暂存
        guard let record = record else { return "" }
        let key = "srcVar." + record.bookSourceUrl
        return UserDefaults.standard.string(forKey: key) ?? ""
    }

    public func setVariable(_ value: String) {
        guard let record = record else { return }
        let key = "srcVar." + record.bookSourceUrl
        UserDefaults.standard.set(value, forKey: key)
    }

    public func getLoginHeader() -> String? {
        record?.loginHeader
    }

    public func putLoginHeader(_ value: String) {
        record?.writeLoginHeader(value)
        onPutLoginHeader?(value)
    }

    public func getLoginInfoMap() -> [String: String] {
        record?.decodeSource()?.loginInfoMap ?? [:]
    }

    public func putLoginInfo(_ json: String) {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            record?.writeLoginInfo([:])
            onPutLoginInfo?([:])
            return
        }
        record?.writeLoginInfo(obj)
        onPutLoginInfo?(obj)
    }
}