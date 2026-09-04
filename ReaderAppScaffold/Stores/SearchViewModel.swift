import Foundation
import LegadoRuleEngine

public struct TaggedSearchResult: Identifiable {
    /// 同一书源可能返回重复 bookUrl；把书名/作者纳入标识，配合 ViewModel 去重，避免 SwiftUI 重复 ID 崩溃。
    public var id: String { sourceUrl + "|" + bookUrl + "|" + name + "|" + author }
    public let sourceUrl: String
    public let sourceName: String
    public let name: String
    public let author: String
    public let intro: String
    public let lastChapter: String
    public let bookUrl: String
    public let coverUrl: String
    public let wordCount: String
}

@Observable
@MainActor
public final class SearchViewModel {
    public var keyword: String = ""
    public var results: [TaggedSearchResult] = []
    public var isSearching = false
    public var isLoadingMore = false
    public var errorMessages: [String] = []
    public private(set) var omittedResultCount = 0
    /// 防止聚合源一次返回数千条导致 SwiftUI 同时创建大量封面视图和内存峰值。
    private let maxResultsPerSource = 120
    private let maxTotalResults = 600
    /// 翻到最后一页时置 true，"加载更多"按钮据此禁用（简化处理：任何一个源没结果了就整体停，
    /// 不逐源精细跟踪谁还有下一页，书源多的时候这样已经够用）
    public private(set) var reachedEnd = false

    private let sources: [BookSourceRecord]
    private var currentPage = 1

    public init(sources: [BookSourceRecord]) {
        self.sources = sources
    }

    /// 并发向所有启用的书源发起搜索，谁先回来先显示谁的结果
    public func search() async {
        let kw = keyword.trimmingCharacters(in: .whitespaces)
        guard !kw.isEmpty else { return }
        currentPage = 1
        reachedEnd = false
        results = []
        errorMessages = []
        omittedResultCount = 0
        isSearching = true
        defer { isSearching = false }
        await performSearch(keyword: kw, page: currentPage)
    }

    /// 加载下一页，结果追加到现有列表后面
    public func loadMore() async {
        let kw = keyword.trimmingCharacters(in: .whitespaces)
        guard !kw.isEmpty, !isSearching, !isLoadingMore, !reachedEnd else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        currentPage += 1
        await performSearch(keyword: kw, page: currentPage)
    }

    private func performSearch(keyword kw: String, page: Int) async {
        var pageResultCount = 0

        await withTaskGroup(of: (String, String, Result<[SearchResult], Error>).self) { group in
            for record in sources {
                guard let source = record.decodeSource() else { continue }
                let sourceUrl = record.bookSourceUrl
                let sourceName = record.bookSourceName
                group.addTask {
                    let runtime = BookSourceRuntime(source)
                    do {
                        let r = try await runtime.search(kw, page: page, resultLimit: maxResultsPerSource)
                        return (sourceUrl, sourceName, .success(r))
                    } catch {
                        return (sourceUrl, sourceName, .failure(error))
                    }
                }
            }
            for await (sourceUrl, sourceName, result) in group {
                switch result {
                case .success(let list):
                    let candidates = list.prefix(maxResultsPerSource).map {
                        TaggedSearchResult(
                            sourceUrl: sourceUrl, sourceName: sourceName,
                            name: $0.name, author: $0.author, intro: $0.intro,
                            lastChapter: $0.lastChapter, bookUrl: $0.bookUrl,
                            coverUrl: $0.coverUrl, wordCount: $0.wordCount
                        )
                    }
                    var knownIDs = Set(results.map(\.id))
                    var unique: [TaggedSearchResult] = []
                    for item in candidates where knownIDs.insert(item.id).inserted {
                        unique.append(item)
                    }
                    let capacity = max(0, maxTotalResults - results.count)
                    let accepted = Array(unique.prefix(capacity))
                    results.append(contentsOf: accepted)
                    pageResultCount += accepted.count
                    omittedResultCount += max(0, list.count - accepted.count)
                    if results.count >= maxTotalResults { reachedEnd = true }
                case .failure(let error):
                    engineLog("搜索失败: \(error.localizedDescription)", tag: sourceName, level: .error)
                    errorMessages.append("\(sourceName): \(error.localizedDescription)")
                }
            }
        }

        if pageResultCount == 0 {
            reachedEnd = true
        }
    }
}
