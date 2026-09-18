import Foundation

/// Wrapper that adapts a BSBookSource (value-type struct) to conform to
/// BSRuleDataInterface (class-only protocol required by ModernRuleEngine,
/// BSAnalyzeUrl, and JSCoreEngine).
///
/// BSBookSource cannot directly conform to BSRuleDataInterface because it is
/// a struct while the protocol requires AnyObject (for weak references in
/// BSAnalyzeUrl and the engine's variable chain). This class bridges the gap.
final class BSBookSourceRuleData: BSRuleDataInterface {

    let source: BSBookSource

    lazy var variableMap: [String: String] = [:]

    init(source: BSBookSource) {
        self.source = source
    }

    func putBigVariable(key: String, value: String?) {
        if let value {
            variableMap[key] = value
        } else {
            variableMap.removeValue(forKey: key)
        }
    }

    func getBigVariable(key: String) -> String? {
        nil
    }
}
