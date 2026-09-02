import Foundation

/// 极简 JSONPath 引擎。
///
/// legado 原版用的是 Java 的 Jayway JsonPath 库（功能齐全，支持过滤表达式 ?(@.x>1) 等），
/// Swift 生态没有直接对应、维护良好的移植版，这里手写了书源规则里最常用的语法子集：
///   $.a.b.c        属性访问
///   $[0]           数组下标（支持负数）
///   $[0,2,4]       多个下标
///   $[1:3]         切片（左闭右开，支持省略端与负数）
///   $.list[*].name / $[*]   通配符
///   $..title       递归下钻（收集所有层级同名字段，或配合 [*]/无key 收集所有值）
///
/// 不支持: 过滤表达式 ?(@.price<10)、脚本表达式、函数（length()等）。
/// 书源规则里如果用到这些，需要单独处理或改用 @js: 规则用 JavaScriptCore 跑一段 JS 来做等价逻辑。
public enum MiniJSONPath {

    public struct JSONPathError: Error, CustomStringConvertible {
        public let message: String
        public var description: String { message }
    }

    /// 对 root（JSONSerialization 解析出的 Any：[String:Any]/[Any]/NSNumber/String/NSNull）执行查询
    public static func query(_ root: Any, _ path: String) throws -> [Any] {
        let tokens = try tokenize(path)
        var current: [Any] = [root]
        for token in tokens {
            current = apply(token, to: current)
        }
        return current
    }

    private enum Token {
        case key(String)
        case index(Int)
        case indices([Int])
        case slice(Int?, Int?)
        case wildcard
        case recursive(String?) // ..key 或 ..* / ..[*]
    }

    private static func tokenize(_ path: String) throws -> [Token] {
        var p = path.trimmingCharacters(in: .whitespaces)
        if p.hasPrefix("$") { p.removeFirst() }
        let chars = Array(p)
        var tokens: [Token] = []
        var i = 0
        while i < chars.count {
            if chars[i] == "." {
                if i + 1 < chars.count, chars[i + 1] == "." {
                    i += 2
                    var key = ""
                    while i < chars.count, chars[i] != ".", chars[i] != "[" {
                        key.append(chars[i]); i += 1
                    }
                    if key == "*" || key.isEmpty {
                        tokens.append(.recursive(nil))
                    } else {
                        tokens.append(.recursive(key))
                    }
                    continue
                } else {
                    i += 1
                    var key = ""
                    while i < chars.count, chars[i] != ".", chars[i] != "[" {
                        key.append(chars[i]); i += 1
                    }
                    if key == "*" {
                        tokens.append(.wildcard)
                    } else if !key.isEmpty {
                        tokens.append(.key(key))
                    }
                    continue
                }
            } else if chars[i] == "[" {
                i += 1
                var inner = ""
                while i < chars.count, chars[i] != "]" {
                    inner.append(chars[i]); i += 1
                }
                i += 1 // 跳过 ]
                let t = inner.trimmingCharacters(in: .whitespaces)
                if t == "*" {
                    tokens.append(.wildcard)
                } else if t.hasPrefix("'") || t.hasPrefix("\"") {
                    let key = t.trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
                    tokens.append(.key(key))
                } else if t.contains(":") {
                    let parts = t.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
                    let start = parts.indices.contains(0) ? Int(parts[0].trimmingCharacters(in: .whitespaces)) : nil
                    let end = parts.count > 1 ? Int(parts[1].trimmingCharacters(in: .whitespaces)) : nil
                    tokens.append(.slice(start, end))
                } else if t.contains(",") {
                    let idxs = t.split(separator: ",")
                        .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                    tokens.append(.indices(idxs))
                } else if let idx = Int(t) {
                    tokens.append(.index(idx))
                } else if !t.isEmpty {
                    throw JSONPathError(message: "不支持的JSONPath片段: [\(t)]（过滤/脚本表达式暂不支持）")
                }
                continue
            } else {
                i += 1 // 跳过多余字符（如根开头的空白）
            }
        }
        return tokens
    }

    private static func apply(_ token: Token, to nodes: [Any]) -> [Any] {
        var result: [Any] = []
        for node in nodes {
            switch token {
            case .key(let k):
                if let dict = node as? [String: Any], let v = dict[k] {
                    result.append(v)
                }
            case .index(let idx):
                if let arr = node as? [Any] {
                    let real = idx < 0 ? arr.count + idx : idx
                    if real >= 0, real < arr.count { result.append(arr[real]) }
                }
            case .indices(let idxs):
                if let arr = node as? [Any] {
                    for idx in idxs {
                        let real = idx < 0 ? arr.count + idx : idx
                        if real >= 0, real < arr.count { result.append(arr[real]) }
                    }
                }
            case .slice(let start, let end):
                if let arr = node as? [Any] {
                    var s = start ?? 0
                    var e = end ?? arr.count
                    if s < 0 { s += arr.count }
                    if e < 0 { e += arr.count }
                    s = max(0, min(s, arr.count))
                    e = max(0, min(e, arr.count))
                    if s < e { result.append(contentsOf: arr[s..<e]) }
                }
            case .wildcard:
                if let arr = node as? [Any] {
                    result.append(contentsOf: arr)
                } else if let dict = node as? [String: Any] {
                    result.append(contentsOf: dict.values)
                }
            case .recursive(let key):
                result.append(contentsOf: recursiveCollect(node, key: key))
            }
        }
        return result
    }

    private static func recursiveCollect(_ node: Any, key: String?) -> [Any] {
        var result: [Any] = []
        if let dict = node as? [String: Any] {
            if let key = key {
                if let v = dict[key] { result.append(v) }
            } else {
                result.append(contentsOf: dict.values)
            }
            for v in dict.values {
                result.append(contentsOf: recursiveCollect(v, key: key))
            }
        } else if let arr = node as? [Any] {
            if key == nil { result.append(contentsOf: arr) }
            for v in arr {
                result.append(contentsOf: recursiveCollect(v, key: key))
            }
        }
        return result
    }
}
