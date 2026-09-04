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
        guard let record = record else { return "" }
        if let cacheVal = UserDefaults.standard.string(forKey: "srcVar." + record.bookSourceUrl),
           !cacheVal.isEmpty { return cacheVal }
        // 常规聚合源的第一个配置以JSON数组形式存入loginInfoJSON，如 [{host:…}]
        if let json = record.loginInfoJSON, !json.isEmpty {
            // 若是可序列化变量数组，返回它
            if json.trimmingCharacters(in: .whitespaces).hasPrefix("[") { return json }
        }
        return ""
    }

    public func setVariable(_ value: String) {
        guard let record = record else { return }
        // 非首个请求也可能写入bookId映射等，这里仅提供默认变量槽
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