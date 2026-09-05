import Foundation

actor ExploreCache {
    static let shared = ExploreCache()

    private struct Envelope<Value: Codable>: Codable {
        let savedAt: Date
        let value: Value
    }

    private let directory: URL

    private init() {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        directory = base.appendingPathComponent("LegadoExplore", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func load<Value: Codable>(_ type: Value.Type, key: String, ttl: TimeInterval) -> Value? {
        guard ttl > 0 else { return nil }
        let file = fileURL(for: key)
        guard let data = try? Data(contentsOf: file) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let envelope = try? decoder.decode(Envelope<Value>.self, from: data),
              Date().timeIntervalSince(envelope.savedAt) <= ttl else {
            try? FileManager.default.removeItem(at: file)
            return nil
        }
        return envelope.value
    }

    func save<Value: Codable>(_ value: Value, key: String) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(Envelope(savedAt: Date(), value: value)) else { return }
        try? data.write(to: fileURL(for: key), options: .atomic)
    }

    func clear(sourceURL: String) {
        let prefix = stableHash(sourceURL) + "-"
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.lastPathComponent.hasPrefix(prefix) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    func cacheKey(sourceURL: String, component: String) -> String {
        stableHash(sourceURL) + "-" + stableHash(component)
    }

    private func fileURL(for key: String) -> URL {
        directory.appendingPathComponent(key).appendingPathExtension("json")
    }

    private func stableHash(_ text: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(format: "%016llx", hash)
    }
}
