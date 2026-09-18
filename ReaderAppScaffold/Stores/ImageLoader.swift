import Foundation
import UIKit
import CryptoKit

/// 支持自定义请求头的封面加载器。
/// 内存缓存用于当前会话，Application Support 磁盘缓存不设有效期，不会被系统按普通 Cache 清理。
public actor ImageLoader {
    public static let shared = ImageLoader()

    private let memoryCache = NSCache<NSString, UIImage>()
    private var inFlight: [String: Task<UIImage?, Never>] = [:]
    private let diskDirectory: URL

    public var directoryURL: URL { diskDirectory }

    private init() {
        memoryCache.countLimit = 500
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        diskDirectory = support.appendingPathComponent("PermanentBookCovers", isDirectory: true)
        try? FileManager.default.createDirectory(at: diskDirectory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var directory = diskDirectory
        try? directory.setResourceValues(values)
    }

    public func load(url: String, headers: [String: String] = [:]) async -> UIImage? {
        guard let requestURL = URL(string: url) else { return nil }
        let key = cacheKey(url, headers)
        let memoryKey = key as NSString

        if let cached = memoryCache.object(forKey: memoryKey) { return cached }
        if let diskImage = loadFromDisk(key: key) {
            memoryCache.setObject(diskImage, forKey: memoryKey)
            return diskImage
        }
        if let existing = inFlight[key] { return await existing.value }

        let destination = fileURL(for: key)
        let task = Task<UIImage?, Never> {
            var request = URLRequest(url: requestURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
            for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { return nil }
                guard let image = UIImage(data: data) else { return nil }
                try? data.write(to: destination, options: .atomic)
                return image
            } catch {
                return nil
            }
        }
        inFlight[key] = task
        let image = await task.value
        inFlight[key] = nil
        if let image { memoryCache.setObject(image, forKey: memoryKey) }
        return image
    }

    public func clearMemoryCache() {
        memoryCache.removeAllObjects()
    }

    /// 仅在用户明确要求清除封面时调用；正常运行永不自动删除磁盘封面。
    public func clearPersistentCache() {
        memoryCache.removeAllObjects()
        try? FileManager.default.removeItem(at: diskDirectory)
        try? FileManager.default.createDirectory(at: diskDirectory, withIntermediateDirectories: true)
    }

    private func loadFromDisk(key: String) -> UIImage? {
        guard let data = try? Data(contentsOf: fileURL(for: key)),
              let image = UIImage(data: data) else { return nil }
        return image
    }

    private func fileURL(for key: String) -> URL {
        diskDirectory.appendingPathComponent(key).appendingPathExtension("cover")
    }

    private func cacheKey(_ urlString: String, _ headers: [String: String]) -> String {
        var canonicalURL = urlString
        if var components = URLComponents(string: urlString) {
            components.query = nil
            components.fragment = nil
            canonicalURL = components.string ?? urlString
        }
        let headerPart = headers.sorted { $0.key < $1.key }
            .map { "\($0.key.lowercased())=\($0.value)" }
            .joined(separator: "&")
        let digest = SHA256.hash(data: Data((canonicalURL + "|" + headerPart).utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
