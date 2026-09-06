import SwiftUI

/// 纯引用类型的小缓存盒子：给 SwiftUI View 里"渲染期间需要缓存点数据，但又不想触发
/// @State刷新"的场景用（只mutate内部字典，不重新赋值@State本身，SwiftUI不会感知到这次mutate）。
public final class HeaderCacheBox {
    public var storage: [String: [String: String]] = [:]
    public init() {}
}

/// 用法类似 `AsyncImage`，多了个 `headers` 参数：
/// ```swift
/// CoverImageView(url: result.coverUrl, headers: source.parsedHeaderMap())
///     .frame(width: 60, height: 84)
/// ```
public struct CoverImageView: View {
    let url: String
    let headers: [String: String]

    @State private var image: UIImage?
    @State private var failed = false

    public init(url: String, headers: [String: String] = [:]) {
        self.url = url
        self.headers = headers
    }

    public var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle()
                    .fill(.quaternary)
                    .overlay {
                        Image(systemName: failed ? "photo.badge.exclamationmark" : "book.closed")
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .task(id: url) {
            guard !url.isEmpty, image == nil else { return }
            failed = false
            let loaded = await ImageLoader.shared.load(url: url, headers: headers)
            if let loaded {
                image = loaded
            } else {
                failed = true
            }
        }
    }
}
