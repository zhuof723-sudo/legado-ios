import Foundation

/// 对应 legado: model/analyzeRule/RuleData.kt
/// RuleDataInterface 的一个通用默认实现，凡是需要承载 @put/@get 变量、
/// 又不想为每个场景单独建类型时可以直接用它（比如临时的规则调试场景）。
public final class RuleData: RuleDataInterface {
    public var variableMap: [String: String] = [:]

    public init() {}

    public func getVariableJSON() -> String? {
        guard !variableMap.isEmpty else { return nil }
        guard let data = try? JSONSerialization.data(withJSONObject: variableMap, options: [.sortedKeys]) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}
