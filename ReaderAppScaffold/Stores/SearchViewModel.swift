import Foundation
import LegadoRuleEngine

public struct TaggedSearchResult: Identifiable {
    public var id: String { bookUrl + "|" + sourceUrl }
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
                        let r = try await runtime.search(kw, page: page)
                        return (sourceUrl, sourceName, .success(r))
                    } catch {
                        return (sourceUrl, sourceName, .failure(error))
                    }
                }
            }
            for await (sourceUrl, sourceName, result) in group {
                switch result {
                case .success(let list):
                    pageResultCount += list.count
                    let tagged = list.map {
                        TaggedSearchResult(
                            sourceUrl: sourceUrl, sourceName: sourceName,
                            name: $0.name, author: $0.author, intro: $0.intro,
                            lastChapter: $0.lastChapter, bookUrl: $0.bookUrl,
                            coverUrl: $0.coverUrl, wordCount: $0.wordCount
                        )
                    }
                    results.append(contentsOf: tagged)
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
