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
    /// 匹配度分数，用于排序：精确匹配 > 作者匹配 > 包含匹配
    public var matchScore: Int = 0
}

@Observable
@MainActor
public final class SearchViewModel {
    public var keyword: String = ""
    public var results: [TaggedSearchResult] = []
    public var isSearching = false
    public var isLoadingMore = false
    public var isPaused = false
    public var errorMessages: [String] = []
    public private(set) var omittedResultCount = 0
    /// 防止聚合源一次返回数千条导致 SwiftUI 同时创建大量封面视图和内存峰值。
    private let maxResultsPerSource = 120
    private let maxTotalResults = 600
    /// 并发搜索的书源数量（参考 legado-E AppConfig.threadCount）
    private let concurrentSearchLimit = 8
    /// 单个书源搜索超时（参考 legado-E 30秒）
    private let searchTimeout: TimeInterval = 30
    /// 翻到最后一页时置 true，"加载更多"按钮据此禁用
    public private(set) var reachedEnd = false

    private let sources: [BookSourceRecord]
    private var currentPage = 1
    private var searchTask: Task<Void, Never>?
    private let pauseController = PauseController()

    public init(sources: [BookSourceRecord]) {
        self.sources = sources
    }

    /// 并发向所有启用的书源发起搜索，谁先回来先显示谁的结果
    public func search() async {
        let kw = keyword.trimmingCharacters(in: .whitespaces)
        guard !kw.isEmpty else { return }
        // 取消之前的搜索
        cancel()
        currentPage = 1
        reachedEnd = false
        results = []
        errorMessages = []
        omittedResultCount = 0
        isSearching = true
        isPaused = false
        pauseController.resume()
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

    /// 暂停搜索（参考 legado-E SearchModel.pause）
    public func pause() {
        isPaused = true
        pauseController.pause()
    }

    /// 恢复搜索（参考 legado-E SearchModel.resume）
    public func resume() {
        isPaused = false
        pauseController.resume()
    }

    /// 取消搜索（参考 legado-E SearchModel.cancelSearch）
    public func cancel() {
        searchTask?.cancel()
        searchTask = nil
        pauseController.resume() // 恢复暂停状态，避免后续任务卡住
    }

    private func performSearch(keyword kw: String, page: Int) async {
        var pageResultCount = 0
        let knownIDs = ThreadSafeSet<String>()
        results.forEach { knownIDs.insert($0.id) }

        await withLimitedConcurrency(items: sources, limit: concurrentSearchLimit) { record in
            // 检查暂停
            await self.pauseController.waitIfPaused()
            // 检查取消
            if Task.isCancelled { return }

            guard let source = record.decodeSource() else { return }
            let sourceUrl = record.bookSourceUrl
            let sourceName = record.bookSourceName
            let runtime = BookSourceRuntime(source)

            do {
                // 超时控制（参考 legado-E withTimeout(30000L)）
                let r = try await withTimeout(self.searchTimeout) {
                    try await runtime.search(kw, page: page, resultLimit: self.maxResultsPerSource)
                }
                if Task.isCancelled { return }

                let candidates = r.prefix(self.maxResultsPerSource).map {
                    TaggedSearchResult(
                        sourceUrl: sourceUrl, sourceName: sourceName,
                        name: $0.name, author: $0.author, intro: $0.intro,
                        lastChapter: $0.lastChapter, bookUrl: $0.bookUrl,
                        coverUrl: $0.coverUrl, wordCount: $0.wordCount
                    )
                }

                // 计算匹配度分数（参考 legado-E mergeItems 排序逻辑）
                var scoredCandidates: [TaggedSearchResult] = []
                for item in candidates {
                    var scored = item
                    var score = 0
                    if scored.name == kw || scored.author == kw {
                        score = 100 // 精确匹配
                    } else if scored.name.contains(kw) || scored.author.contains(kw) {
                        score = 50 // 包含匹配
                    }
                    scored.matchScore = score
                    scoredCandidates.append(scored)
                }

                // 去重并追加
                var unique: [TaggedSearchResult] = []
                for item in scoredCandidates {
                    if knownIDs.insert(item.id) {
                        unique.append(item)
                    }
                }

                await MainActor.run {
                    let capacity = max(0, self.maxTotalResults - self.results.count)
                    let accepted = Array(unique.prefix(capacity))
                    self.results.append(contentsOf: accepted)
                    // 按匹配度排序（精确匹配在前）
                    self.results.sort { $0.matchScore > $1.matchScore }
                    pageResultCount += accepted.count
                    self.omittedResultCount += max(0, r.count - accepted.count)
                    if self.results.count >= self.maxTotalResults {
                        self.reachedEnd = true
                    }
                }
            } catch is TimeoutError {
                engineLog("搜索超时（\(Int(self.searchTimeout))秒）", tag: sourceName, level: .error)
                await MainActor.run {
                    self.errorMessages.append("\(sourceName): 搜索超时")
                }
            } catch {
                if Task.isCancelled { return }
                engineLog("搜索失败: \(error.localizedDescription)", tag: sourceName, level: .error)
                await MainActor.run {
                    self.errorMessages.append("\(sourceName): \(error.localizedDescription)")
                }
            }
        }

        if pageResultCount == 0 {
            reachedEnd = true
        }
    }
}
