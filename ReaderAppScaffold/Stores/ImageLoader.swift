import Foundation
import UIKit

/// 支持自定义请求头的图片加载 + 内存缓存。
/// 系统 `AsyncImage` 不支持自定义 header，而不少书源封面图必须带对应的 Referer/User-Agent
/// 才能访问（防盗链），所以单独写了这个轻量加载器。
public actor ImageLoader {
    public static let shared = ImageLoader()

    private let cache = NSCache<NSString, UIImage>()
    private var inFlight: [String: Task<UIImage?, Never>] = [:]

    private init() {
        cache.countLimit = 500
    }

    /// 用 url+headers 的组合做缓存key（同一张图不同header理论上结果一样，但极少数站点会按header返回不同内容，保险起见带上）
    private func cacheKey(_ url: String, _ headers: [String: String]) -> NSString {
        let headerPart = headers.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "&")
        return "\(url)|\(headerPart)" as NSString
    }

    public func load(url: String, headers: [String: String] = [:]) async -> UIImage? {
        guard let requestURL = URL(string: url) else { return nil }
        let key = cacheKey(url, headers)

        if let cached = cache.object(forKey: key) {
            return cached
        }
        if let existing = inFlight[url] {
            return await existing.value
        }

        let task = Task<UIImage?, Never> {
            var request = URLRequest(url: requestURL)
            for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
            do {
                let (data, _) = try await URLSession.shared.data(for: request)
                return UIImage(data: data)
            } catch {
                return nil
            }
        }
        inFlight[url] = task
        let image = await task.value
        inFlight[url] = nil
        if let image = image {
            cache.setObject(image, forKey: key)
        }
        return image
    }

    public func clearCache() {
        cache.removeAllObjects()
    }
}
