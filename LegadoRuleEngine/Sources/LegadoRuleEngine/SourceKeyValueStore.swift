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

/// UserDefaults 持久化实现。每个书源使用独立命名空间，避免 key 相互污染。
public final class UserDefaultsKeyValueStore: SourceKeyValueStore {
    private let namespace: String
    private let defaults: UserDefaults

    public init(namespace: String, defaults: UserDefaults = .standard) {
        self.namespace = namespace
        self.defaults = defaults
    }

    private func storageKey(_ key: String) -> String {
        let source = Data(namespace.utf8).base64EncodedString()
        return "legado.source.cache.\(source).\(key)"
    }

    public func get(_ key: String) -> String? {
        defaults.string(forKey: storageKey(key))
    }

    public func put(_ key: String, _ value: String) {
        defaults.set(value, forKey: storageKey(key))
    }

    public func remove(_ key: String) {
        defaults.removeObject(forKey: storageKey(key))
    }
}
