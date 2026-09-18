import Foundation
import SwiftUI
import Observation
import LegadoRuleEngine

// MARK: - 阅读位置持久化

/// 阅读位置：章节 + 字符偏移（页码依赖排版参数，字符偏移才稳定）。
/// 存 UserDefaults，避免 SwiftData 模型迁移。
struct ReadingPosition: Codable {
    let chapterIndex: Int
    let charOffset: Int
}

enum PositionStore {
    private static func key(for bookKey: String) -> String { "reader.position.\(bookKey)" }

    static func load(bookKey: String) -> ReadingPosition? {
        guard let data = UserDefaults.standard.data(forKey: key(for: bookKey)),
              let position = try? JSONDecoder().decode(ReadingPosition.self, from: data) else { return nil }
        return position
    }

    static func save(_ position: ReadingPosition, bookKey: String) {
        guard let data = try? JSONEncoder().encode(position) else { return }
        UserDefaults.standard.set(data, forKey: key(for: bookKey))
    }

    static func clear(bookKey: String) {
        UserDefaults.standard.removeObject(forKey: key(for: bookKey))
    }
}

// MARK: - 阅读会话

/// 阅读会话：一次打开一本书的全部状态与编排。
///
/// 职责：
/// 1. 章节导航（经 BookContentSource，本地/在线同一条路径）
/// 2. 分页编排（单飞任务 + 分页缓存 + 跳页意图落位）
/// 3. 阅读位置（字符偏移持久化，排版参数变化也能回到同一处文字）
@MainActor
@Observable
final class ReadingSession: Identifiable {
    let id = UUID()

    enum Source {
        case local(LocalChapterSource)
        case online(OnlineChapterSource, bookUrl: String, bookName: String)
    }

    let source: Source
    let bookKey: String

    // MARK: 分页状态

    private(set) var pages: [BookPage] = []
    /// pages 属于哪个章节（跨章切换时旧页立即失效；切排版参数时旧页保留上屏）
    private(set) var pagesChapterIndex: Int = -1
    private(set) var paginatedKey: String = ""

    // MARK: 跳页意图

    private(set) var pendingJumpToPage: Int?
    private(set) var pendingJumpToLastPage = false
    private var restoredPosition = false
    private var savedPosition: ReadingPosition?

    var pageIndex: Int = 0

    // MARK: - 初始化

    init(source: Source) {
        self.source = source
        switch source {
        case .local(let local):
            self.bookKey = local.bookKey
            // 阅读位置恢复：先回到保存的章节，页码在第一次分页后按字符偏移落位。
            let saved = PositionStore.load(bookKey: local.bookKey)
            self.savedPosition = saved
            if let saved {
                local.restoreChapter(saved.chapterIndex)
            }
        case .online(_, let bookUrl, _):
            self.bookKey = bookUrl
            self.savedPosition = PositionStore.load(bookKey: bookUrl)
        }
    }

    /// 协议视图：会话内的统一内容源句柄。
    private var contentSource: any BookContentSource {
        switch source {
        case .local(let local): return local
        case .online(let online, _, _): return online
        }
    }

    // MARK: - 章节信息（转发到内容源，读取即参与 @Observable 追踪）

    var bookTitle: String {
        switch source {
        case .local(let local): return local.bookTitle
        case .online(_, _, let bookName): return bookName
        }
    }

    var chapterCount: Int { contentSource.chapterCount }
    func chapterTitle(at index: Int) -> String { contentSource.chapterTitle(at: index) }
    var currentChapterIndex: Int { contentSource.currentChapterIndex }
    var currentChapterTitle: String { contentSource.chapterTitle(at: contentSource.currentChapterIndex) }
    var currentContent: String { contentSource.currentContent }
    var isLoading: Bool { contentSource.isLoading }
    var errorMessage: String? { contentSource.errorMessage }

    var hasNextChapter: Bool { currentChapterIndex + 1 < chapterCount }
    var hasPreviousChapter: Bool { currentChapterIndex > 0 }

    /// 全书进度：章序号 + 页内占比 / 总章数。
    var bookProgress: Double {
        guard chapterCount > 1 else { return 0 }
        let inChapter = pages.isEmpty ? 0 : min(max(Double(pageIndex + 1) / Double(pages.count), 0), 1)
        return (Double(currentChapterIndex) + inChapter) / Double(chapterCount)
    }

    // MARK: - 段评能力（仅在线源）

    var supportsReviews: Bool { contentSource.supportsReviews }
    var currentMarkers: [InlineReviewMarker] { contentSource.currentMarkers }
    func marker(id: Int) -> InlineReviewMarker? { contentSource.marker(id: id) }

    func executeMarkerAction(id: Int, openBrowser: @escaping (String, String?) -> Void) {
        contentSource.executeMarkerAction(id: id, openBrowser: openBrowser)
    }

    func fetchReviews(paragraphIndex: Int, paragraphText: String, markerSource: String?) async throws -> [Review] {
        await contentSource.fetchReviews(
            paragraphIndex: paragraphIndex,
            paragraphText: paragraphText,
            markerSource: markerSource
        )
    }

    // MARK: - 章节导航

    func openChapter(_ index: Int) async {
        await contentSource.openChapter(at: index)
        if !pendingJumpToLastPage, pendingJumpToPage == nil {
            pageIndex = 0
        }
    }

    @discardableResult
    func advancePage(allowNextChapter: Bool) async -> Bool {
        if pageIndex + 1 < pages.count {
            pageIndex += 1
            return true
        }
        guard allowNextChapter, hasNextChapter else { return false }
        pendingJumpToLastPage = false
        pendingJumpToPage = nil
        pageIndex = 0
        await openChapter(currentChapterIndex + 1)
        return true
    }

    func goPreviousPage() async {
        if pageIndex > 0 {
            pageIndex -= 1
        } else if hasPreviousChapter {
            pendingJumpToLastPage = true
            pendingJumpToPage = nil
            await openChapter(currentChapterIndex - 1)
        } else {
            pendingJumpToLastPage = false
        }
    }

    func jumpToBookmark(_ bookmark: BookBookmark) async {
        guard bookmark.chapterIndex != currentChapterIndex else {
            pageIndex = min(max(bookmark.pageIndex, 0), max(pages.count - 1, 0))
            return
        }
        pendingJumpToPage = bookmark.pageIndex
        await openChapter(bookmark.chapterIndex)
    }

    // MARK: - 分页编排

    /// 分页缓存键：内容指纹 + 排版签名 + 段评标记 + 章节号。
    static func paginationKey(
        contentFingerprint: String,
        markerKey: String,
        chapterIndex: Int,
        layout: LayoutParams
    ) -> String {
        [
            "c\(contentFingerprint)",
            layout.signature,
            "mk\(markerKey)",
            "ch\(chapterIndex)"
        ].joined(separator: "|")
    }

    /// 当前段评标记键：标记集合的低成本指纹。
    var currentMarkerKey: String {
        currentMarkers
            .map { "\($0.id):\($0.paragraphIndex):\($0.count)" }
            .joined(separator: ",")
    }

    /// 确保 pages 对应给定分页键。由阅读页的 .task(id:) 驱动：
    /// 内容/排版/尺寸任一变，任务自动取消重跑；命中缓存直接返回。
    func ensurePaginated(key: String, layout: LayoutParams, badgeColor: UIColor) async {
        guard key != paginatedKey else { return }

        let content = currentContent
        guard !content.isEmpty else {
            // 在线正文加载期间内容短暂为空：保留跳页意图，
            // 等内容到达后的那次分页再落位（上一章末页 / 书签页）。
            pages = []
            pagesChapterIndex = currentChapterIndex
            paginatedKey = key
            return
        }

        // 文档构建（段落切分 + 段评角标）走主线程：纯字符串操作，毫秒级。
        let document = ChapterDocumentBuilder.build(
            title: currentChapterTitle,
            content: content,
            markers: currentMarkers,
            legacyLinks: supportsReviews,
            font: layout.font,
            badgeColor: badgeColor
        )
        let capturedChapter = currentChapterIndex

        let result: [BookPage]
        if let cached = PageCache.shared.pages(for: key) {
            result = cached
        } else {
            result = await Task.detached(priority: .userInitiated) {
                let paginated = PaginationEngine.paginate(
                    document: document,
                    layout: layout,
                    buildKey: key
                )
                if !paginated.isEmpty {
                    PageCache.shared.store(paginated, for: key)
                }
                return paginated
            }.value
        }

        // 任务已被新一轮取代（Aa 滑杆拖动 / 快速切章），丢弃本次结果。
        guard !Task.isCancelled else { return }
        guard capturedChapter == currentChapterIndex else { return }
        guard content == currentContent else { return }

        pages = result
        pagesChapterIndex = capturedChapter

        if let jump = pendingJumpToPage {
            pageIndex = min(max(jump, 0), max(result.count - 1, 0))
            pendingJumpToPage = nil
        } else if pendingJumpToLastPage {
            pageIndex = max(0, result.count - 1)
            pendingJumpToLastPage = false
        } else if !restoredPosition {
            restoredPosition = true
            if let saved = savedPosition, saved.chapterIndex == capturedChapter, !result.isEmpty {
                pageIndex = Self.page(containing: saved.charOffset, in: result)
            } else if pageIndex >= result.count {
                pageIndex = 0
            }
        } else if pageIndex >= result.count {
            pageIndex = 0
        }
        paginatedKey = key
    }

    /// 按字符偏移找回页码：找到第一个覆盖该偏移的页。
    static func page(containing offset: Int, in pages: [BookPage]) -> Int {
        for (index, page) in pages.enumerated() {
            if offset >= page.chapterRange.location,
               offset < NSMaxRange(page.chapterRange) {
                return index
            }
        }
        return pages.isEmpty ? 0 : pages.count - 1
    }

    // MARK: - 进度保存

    /// 当前页首字符在整章中的偏移。
    var currentCharOffset: Int {
        guard pages.indices.contains(pageIndex) else { return 0 }
        return pages[pageIndex].chapterRange.location
    }

    func saveProgress() {
        PositionStore.save(
            ReadingPosition(chapterIndex: currentChapterIndex, charOffset: currentCharOffset),
            bookKey: bookKey
        )
    }
}
