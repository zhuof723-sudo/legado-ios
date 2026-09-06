import Foundation

/// 对应 legado: model/analyzeRule/CustomUrl.kt
/// 处理 "url,{attr json}" 格式的自定义地址（阅读书源里常见的封面/音频/播放相关自定义url）。
public final class CustomUrl {

    private var mUrl: String
    private var attribute: [String: Any] = [:]

    public init(_ url: String) {
        let ns = url as NSString
        let full = NSRange(location: 0, length: ns.length)
        if let m = AnalyzeUrl.paramPatternShared.firstMatch(in: url, range: full) {
            let attr = ns.substring(from: m.range.location + m.range.length)
            if let data = attr.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                attribute = obj
            }
            mUrl = ns.substring(to: m.range.location)
        } else {
            mUrl = url
        }
    }

    @discardableResult
    public func putAttribute(_ key: String, _ value: Any?) -> CustomUrl {
        if let value = value {
            attribute[key] = value
        } else {
            attribute.removeValue(forKey: key)
        }
        return self
    }

    public func getUrl() -> String { mUrl }

    public func getAttr() -> [String: Any] { attribute }

    public var description: String {
        guard !attribute.isEmpty else { return mUrl }
        if JSONSerialization.isValidJSONObject(attribute),
           let data = try? JSONSerialization.data(withJSONObject: attribute, options: [.sortedKeys]),
           let json = String(data: data, encoding: .utf8) {
            return mUrl + "," + json
        }
        return mUrl
    }
}
