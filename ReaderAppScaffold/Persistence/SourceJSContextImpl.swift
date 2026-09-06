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

    private var keyValueStore: SourceKeyValueStore? {
        guard let record = record else { return nil }
        return UserDefaultsKeyValueStore(namespace: record.bookSourceUrl)
    }

    public var bookSourceName: String { record?.bookSourceName ?? "" }
    public var loginUi: String { record?.decodeSource()?.loginUi ?? "" }
    public var loginUrl: String { record?.decodeSource()?.loginUrl ?? "" }

    public func getVariable() -> String {
        keyValueStore?.get("__source_variable") ?? ""
    }

    public func setVariable(_ value: String) {
        keyValueStore?.put("__source_variable", value)
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