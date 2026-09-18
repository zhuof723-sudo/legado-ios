import Foundation
import SwiftUI
import LegadoRuleEngine

// MARK: - 阅读进度持久化

/// 阅读位置：章节 + 字符偏移（页码依赖排版参数，字符偏移才是稳定的）。
/// 存 UserDefaults，避免 SwiftData 模型迁移。
struct ReadingPosition: Codable {
    let chapterIndex: Int
    let charOffset: Int
}

enum ReadingProgressStore {
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

// MARK: - 阅读视图模型

/// 统一阅读视图模型：本地 TXT/EPUB 与在线书源共用一个阅读页。
///
/// 职责只有四件：
/// 1. 章节导航（本地：直接切；在线：委托给 ReaderViewModel 的书源管线）
/// 2. 分页编排（单飞任务 + 分页缓存 + 跳页意图落位）
/// 3. 阅读位置（字符偏移持久化，排版参数变化也能回到同一处文字）
/// 4. 段评能力转发（仅在线）
@MainActor
@Observable
final class BookReaderViewModel: Identifiable {
    let id = UUID()

    enum BookSourceKind {
        case local(book: LocalBook)
        case online(viewModel: ReaderViewModel, bookUrl: String, bookName: String)
    }

    let source: BookSourceKind
    let bookKey: String

    // MARK: 本地章节（在线路径由 ReaderViewModel 持有）

    private let localChapters: [LocalChapter]
    private(set) var localIndex: Int = 0

    // MARK: 分页状态

    private(set) var pages: [ReaderPage] = []
    /// pages 属于哪个章节（跨章切换时旧页立即失效，切字号时旧页保留上屏）
    private(set) var pagesChapterIndex: Int = -1
    private(set) var paginatedKey: String = ""

    // MARK: 跳页意图

    /// 书签跳页：新章分页完成后落到指定页。
    private(set) var pendingJumpToPage: Int?
    /// 向前切章：新章分页完成后落到末页。
    private(set) var pendingJumpToLastPage = false
    /// 首次分页完成后恢复阅读位置（全书一次）。
    private var restoredPosition = false
    private var savedPosition: ReadingPosition?

    // MARK: - 初始化

    init(source: BookSourceKind) {
        self.source = source
        switch source {
        case .local(let book):
            self.bookKey = "local://\(book.id)"
            var chapters = TxtParser.decode(book.chaptersData)
            if chapters.isEmpty {
                chapters = [LocalChapter(title: book.name, content: "")]
            }
            self.localChapters = chapters
            // 阅读位置恢复：先回到保存的章节，页码在第一次分页后按字符偏移落位。
            let saved = ReadingProgressStore.load(bookKey: self.bookKey)
            self.savedPosition = saved
            if let saved, chapters.indices.contains(saved.chapterIndex) {
                self.localIndex = saved.chapterIndex
            }
        case .online(_, let bookUrl, _):
            self.bookKey = bookUrl
            self.localChapters = []
            self.savedPosition = ReadingProgressStore.load(bookKey: self.bookKey)
        }
    }

    // MARK: - 章节信息（统一视图，直接读到底层状态以参与 @Observable 追踪）

    var bookTitle: String {
        switch source {
        case .local(let book): return book.name
        case .online(_, _, let bookName): return bookName
        }
    }

    var chapterCount: Int {
        switch source {
        case .local: return localChapters.count
        case .online(let vm, _, _): return vm.chapters.count
        }
    }

    func chapterTitle(at index: Int) -> String {
        switch source {
        case .local:
            guard localChapters.indices.contains(index) else { return bookTitle }
            return localChapters[index].title
        case .online(let vm, _, _):
            guard vm.chapters.indices.contains(index) else { return bookTitle }
            return vm.chapters[index].name
        }
    }

    var currentChapterIndex: Int {
        switch source {
        case .local: return localIndex
        case .online(let vm, _, _): return vm.currentIndex
        }
    }

    var currentChapterTitle: String { chapterTitle(at: currentChapterIndex) }

    var currentContent: String {
        switch source {
        case .local:
            guard localChapters.indices.contains(localIndex) else { return "" }
            return localChapters[localIndex].content
        case .online(let vm, _, _): return vm.currentContent
        }
    }

    var isLoading: Bool {
        switch source {
        case .local: return false
        case .online(let vm, _, _): return vm.isLoadingContent || vm.isLoadingToc
        }
    }

    var errorMessage: String? {
        switch source {
        case .local: return nil
        case .online(let vm, _, _): return vm.errorMessage
        }
    }

    var hasNextChapter: Bool { currentChapterIndex + 1 < chapterCount }
    var hasPreviousChapter: Bool { currentChapterIndex > 0 }

    /// 全书进度：章序号 + 页内占比 / 总章数。
    var bookProgress: Double {
        guard chapterCount > 1 else { return 0 }
        let inChapter = pages.isEmpty ? 0 : min(max(Double(pageIndex + 1) / Double(pages.count), 0), 1)
        return (Double(currentChapterIndex) + inChapter) / Double(chapterCount)
    }

    var pageIndex: Int = 0

    // MARK: - 段评能力（仅在线）

    var supportsReviews: Bool {
        switch source {
        case .local: return false
        case .online(let vm, _, _): return vm.reviewEnabled
        }
    }

    private var currentMarkers: [InlineReviewMarker] {
        switch source {
        case .local: return []
        case .online(let vm, _, _): return vm.currentReviewMarkers
        }
    }

    func executeMarkerAction(id: Int, openBrowser: @escaping (String, String?) -> Void) {
        guard case .online(let vm, _, _) = source else { return }
        vm.executeInlineReviewAction(markerID: id, browserOpener: openBrowser)
    }

    func marker(id: Int) -> InlineReviewMarker? {
        currentMarkers.first { $0.id == id }
    }

    func fetchReviews(paragraphIndex: Int, paragraphText: String, markerSource: String?) async throws -> [Review] {
        guard case .online(let vm, _, _) = source else { return [] }
        return await vm.fetchReviews(
            paragraphIndex: paragraphIndex,
            paragraphText: paragraphText,
            markerSource: markerSource
        )
    }

    // MARK: - 章节导航

    func openChapter(_ index: Int) async {
        let target = min(max(index, 0), max(chapterCount - 1, 0))
        guard target != currentChapterIndex || currentContent.isEmpty else { return }
        switch source {
        case .local:
            localIndex = target
        case .online(let vm, _, _):
            await vm.openChapter(at: target)
        }
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

    /// 分页缓存键。内容指纹 + 排版签名 + 章节号。由调用方（阅读页）在 body 里求值，
    /// 只读纯值，不触碰 @Observable 状态（避免 body 重复求值风暴）。
    static func paginationKey(
        contentFingerprint: String,
        markerKey: String,
        chapterIndex: Int,
        typography: ReaderTypography
    ) -> String {
        [
            "c\(contentFingerprint)",
            typography.signature,
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
    func ensurePaginated(key: String, typography: ReaderTypography, badgeColor: UIColor) async {
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
        let document = ReaderDocumentBuilder.build(
            title: currentChapterTitle,
            content: content,
            markers: currentMarkers,
            legacyLinks: supportsReviews,
            font: typography.font,
            badgeColor: badgeColor
        )
        let capturedChapter = currentChapterIndex

        let result: [ReaderPage]
        if let cached = ReaderPageCache.shared.pages(for: key) {
            result = cached
        } else {
            result = await Task.detached(priority: .userInitiated) {
                let paginated = ReaderPaginator.paginate(
                    document: document,
                    typography: typography,
                    buildKey: key
                )
                if !paginated.isEmpty {
                    ReaderPageCache.shared.store(paginated, for: key)
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
    static func page(containing offset: Int, in pages: [ReaderPage]) -> Int {
        for (index, page) in pages.enumerated() {
            if offset >= page.chapterRange.location,
               offset < NSMaxRange(page.chapterRange) {
                return index
            }
        }
        return pages.isEmpty ? 0 : pages.count - 1
    }

    // MARK: - 进度保存

    /// 当前页首字符在整章中的偏移（ReadingPosition.charOffset）。
    var currentCharOffset: Int {
        guard pages.indices.contains(pageIndex) else { return 0 }
        return pages[pageIndex].chapterRange.location
    }

    func saveProgress() {
        ReadingProgressStore.save(
            ReadingPosition(chapterIndex: currentChapterIndex, charOffset: currentCharOffset),
            bookKey: bookKey
        )
    }
}
