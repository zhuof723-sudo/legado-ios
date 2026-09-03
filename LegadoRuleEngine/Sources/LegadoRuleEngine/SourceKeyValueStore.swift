import Foundation

/// 书源级键值存储。对应 legado 的 cache.get/put、java.get/put。
/// 引擎提供协议，应用层实现持久化（UserDefaults / 文件 / SwiftData）。
public protocol SourceKeyValueStore: AnyObject {
    func get(_ key: String) -> String?
    func put(_ key: String, _ value: String)
    func remove(_ key: String)
}

public extension SourceKeyValueStore {
    func get(_ key: String) -> String? { nil }
    func put(_ key: String, _ value: String) {}
    func remove(_ key: String) {}
}

/// 进程内默认实现（不持久化，重启后清空；用于测试/无持久化场景）
public final class InMemoryKeyValueStore: SourceKeyValueStore {
    private var storage: [String: String] = [:]
    private let lock = NSLock()
    public init() {}
    public func get(_ key: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return storage[key]
    }
    public func put(_ key: String, _ value: String) {
        lock.lock(); defer { lock.unlock() }
        storage[key] = value
    }
    public func remove(_ key: String) {
        lock.lock(); defer { lock.unlock() }
        storage.removeValue(forKey: key)
    }
}
