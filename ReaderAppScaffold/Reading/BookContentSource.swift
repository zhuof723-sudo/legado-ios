import Foundation
import SwiftUI
import Observation
import LegadoRuleEngine

// MARK: - 内容源协议

/// 阅读器的内容供给层。本地 TXT/EPUB 与在线书源统一成同一组接口，
/// 阅读会话（ReadingSession）只跟这个协议对话。
@MainActor
protocol BookContentSource: AnyObject {
    /// 书籍唯一键：书签 / 阅读位置的命名空间。
    var bookKey: String { get }
    var bookTitle: String { get }

    var chapterCount: Int { get }
    func chapterTitle(at index: Int) -> String

    var currentChapterIndex: Int { get }
    var currentContent: String { get }
    var isLoading: Bool { get }
    var errorMessage: String? { get }

    func openChapter(_ index: Int) async

    // MARK: 段评能力（本地源默认无）

    var supportsReviews: Bool { get }
    var currentMarkers: [InlineReviewMarker] { get }
    func marker(id: Int) -> InlineReviewMarker?
    func executeMarkerAction(id: Int, openBrowser: @escaping (String, String?) -> Void)
    func fetchReviews(paragraphIndex: Int, paragraphText: String, markerSource: String?) async -> [Review]
}

extension BookContentSource {
    var supportsReviews: Bool { false }
    var currentMarkers: [InlineReviewMarker] { [] }
    func marker(id: Int) -> InlineReviewMarker? { nil }
    func executeMarkerAction(id: Int, openBrowser: @escaping (String, String?) -> Void) {}
    func fetchReviews(paragraphIndex: Int, paragraphText: String, markerSource: String?) async -> [Review] { [] }
}

// MARK: - 本地源（TXT / EPUB）

/// 本地书籍：章节在导入时已解析好（TxtParser / EpubParser → [LocalChapter]），
/// 阅读时零网络、零等待。
@MainActor
@Observable
final class LocalChapterSource: BookContentSource {
    let book: LocalBook
    let chapters: [LocalChapter]
    private(set) var currentChapterIndex: Int = 0

    init(book: LocalBook) {
        self.book = book
        var decoded = TxtParser.decode(book.chaptersData)
        if decoded.isEmpty {
            decoded = [LocalChapter(title: book.name, content: "")]
        }
        self.chapters = decoded
    }

    var bookKey: String { "local://\(book.id)" }
    var bookTitle: String { book.name }

    var chapterCount: Int { chapters.count }
    func chapterTitle(at index: Int) -> String {
        chapters.indices.contains(index) ? chapters[index].title : book.name
    }

    var currentContent: String {
        chapters.indices.contains(currentChapterIndex) ? chapters[currentChapterIndex].content : ""
    }

    var isLoading: Bool { false }
    var errorMessage: String? { nil }

    func openChapter(_ index: Int) async {
        currentChapterIndex = min(max(index, 0), max(chapters.count - 1, 0))
    }

    /// 阅读位置恢复：直接落在保存的章节。
    func restoreChapter(_ index: Int) {
        guard chapters.indices.contains(index) else { return }
        currentChapterIndex = index
    }
}

// MARK: - 在线源（书源规则引擎）

/// 在线书籍：目录/正文经书源规则引擎抓取，带内存缓存、磁盘缓存、
/// 向后并发预取与段评标记处理。请求用 ID  fencing，快速切章时
/// 旧请求不会覆盖新章节。
@MainActor
@Observable
final class OnlineChapterSource: Identifiable, Hashable {
    let bookSource: BookSource
    private let runtime: BookSourceRuntime
    private var persistentBookURL: String?

    private(set) var chapters: [ChapterInfo] = []
    private(set) var currentChapterIndex: Int = 0
    private(set) var currentContent: String = ""
    /// 当前章节中由书源正文内嵌的 `style: "TEXT"` 图片生成的段评入口。
    private(set) var currentMarkers: [InlineReviewMarker] = []
    var isLoadingToc = false
    var isLoadingContent = false
    var errorMessage: String?

    var isLoading: Bool { isLoadingToc || isLoadingContent }

    /// 向后预取的章节数量。
    var prefetchCount: Int = 3

    private var contentCache: [Int: ReaderChapterContent] = [:]
    /// 标识当前正文请求，防止快速切章时旧请求覆盖新章节。
    private var contentRequestID = UUID()
    /// 标识当前目录，防止刷新目录后旧预取任务访问失效索引。
    private var tocRequestID = UUID()
    /// 预取任务所属目录版本。
    private var prefetchGeneration = UUID()
    private var prefetchTasks: Set<Int> = []

    init(bookSource: BookSource, persistentBookURL: String? = nil) {
        self.bookSource = bookSource
        self.runtime = BookSourceRuntime(bookSource)
        self.persistentBookURL = persistentBookURL
    }

    // MARK: Identifiable / Hashable（按实例身份）

    var id: ObjectIdentifier { ObjectIdentifier(self) }
    static func == (lhs: OnlineChapterSource, rhs: OnlineChapterSource) -> Bool { lhs === rhs }
    func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }

    // MARK: BookContentSource

    var bookKey: String { persistentBookURL ?? "" }
    var bookTitle: String { bookSource.bookName }

    var chapterCount: Int { chapters.count }
    func chapterTitle(at index: Int) -> String {
        chapters.indices.contains(index) ? chapters[index].name : bookSource.bookName
    }

    var currentChapterTitle: String? {
        chapters.indices.contains(currentChapterIndex) ? chapters[currentChapterIndex].name : nil
    }

    // MARK: 段评

    /// 当前书源是否支持段评（ruleReview.reviewUrl 或正文内嵌段评图）。
    var supportsReviews: Bool {
        if !currentMarkers.isEmpty { return true }
        if let ruleReview = bookSource.ruleReview,
           let reviewUrl = ruleReview.reviewUrl,
           !reviewUrl.isEmpty {
            return true
        }
        return false
    }

    func marker(id: Int) -> InlineReviewMarker? {
        currentMarkers.first { $0.id == id }
    }

    /// 执行正文内嵌段评图的 click/js 选项。
    func executeMarkerAction(id: Int, openBrowser: @escaping (String, String?) -> Void) {
        guard let marker = marker(id: id),
              chapters.indices.contains(currentChapterIndex),
              let action = marker.action else { return }
        let chapter = chapters[currentChapterIndex]
        runtime.executeInlineReviewAction(
            action,
            markerSource: marker.source,
            chapterUrl: chapter.url,
            browserOpener: openBrowser
        )
    }

    /// 获取某段落的评论列表。
    func fetchReviews(paragraphIndex: Int, paragraphText: String, markerSource: String?) async -> [Review] {
        guard supportsReviews || markerSource?.isEmpty == false else { return [] }
        guard chapters.indices.contains(currentChapterIndex) else { return [] }

        let chapterUrl = chapters[currentChapterIndex].url
        do {
            let rawReviews = try await runtime.getReviews(
                chapterUrl: chapterUrl,
                paragraphText: paragraphText,
                reviewURL: markerSource
            )
            return rawReviews.map { raw in
                Review(
                    userName: raw["userName"] ?? "匿名",
                    avatarUrl: raw["avatarUrl"],
                    content: raw["content"] ?? "",
                    postTime: raw["postTime"],
                    likeCount: Int(raw["likeCount"] ?? ""),
                    replyCount: Int(raw["replyCount"] ?? "")
                )
            }
        } catch {
            engineLog("获取段评失败: \(error.localizedDescription)", tag: "reader", level: .error)
            return []
        }
    }

    // MARK: 目录

    func loadToc(bookUrl: String) async {
        isLoadingToc = true
        errorMessage = nil
        contentRequestID = UUID()
        isLoadingContent = false
        let requestID = UUID()
        tocRequestID = requestID
        prefetchGeneration = UUID()
        contentCache.removeAll()
        prefetchTasks.removeAll()
        currentChapterIndex = 0
        currentContent = ""
        currentMarkers = []
        chapters = []
        defer {
            if requestID == tocRequestID { isLoadingToc = false }
        }
        guard !bookUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "无法打开：书籍地址为空"
            return
        }
        do {
            let loaded = try await runtime.getToc(bookUrl: bookUrl)
            guard requestID == tocRequestID else { return }
            guard !loaded.isEmpty else {
                errorMessage = "目录为空：当前书源未返回章节，请更换书源或测试配置"
                return
            }
            chapters = loaded
        } catch {
            guard requestID == tocRequestID else { return }
            engineLog("获取目录失败: \(error.localizedDescription)", tag: "reader", level: .error)
            errorMessage = "获取目录失败：\(error.localizedDescription)"
        }
    }

    // MARK: 章节导航

    func openChapter(_ index: Int) async {
        guard index >= 0, index < chapters.count else { return }
        guard index != currentChapterIndex || currentContent.isEmpty else { return }
        currentChapterIndex = index
        contentRequestID = UUID()
        currentContent = ""
        currentMarkers = []
        errorMessage = nil
        await loadCurrentContent()
    }

    func nextChapter() async {
        guard currentChapterIndex + 1 < chapters.count else { return }
        currentChapterIndex += 1
        contentRequestID = UUID()
        currentContent = ""
        currentMarkers = []
        errorMessage = nil
        await loadCurrentContent()
    }

    func prevChapter() async {
        guard currentChapterIndex > 0 else { return }
        currentChapterIndex -= 1
        contentRequestID = UUID()
        currentContent = ""
        currentMarkers = []
        errorMessage = nil
        await loadCurrentContent()
    }

    private func loadCurrentContent() async {
        guard chapters.indices.contains(currentChapterIndex) else {
            isLoadingContent = false
            errorMessage = "无法打开正文：章节参数无效"
            return
        }

        let index = currentChapterIndex
        let chapter = chapters[index]
        let requestID = contentRequestID

        // 内存缓存
        if let cached = contentCache[index], cacheIsUsable(cached) {
            guard requestID == contentRequestID, index == currentChapterIndex else { return }
            isLoadingContent = false
            apply(cached)
            prefetchAhead()
            return
        }
        // 磁盘缓存（旧缓存没有段评处理标记，不能再直接显示；重新请求正文）
        if let bookURL = persistentBookURL,
           let cached = await ChapterContentCache.shared.loadDocument(bookURL: bookURL, chapterURL: chapter.url),
           cacheIsUsable(cached) {
            guard requestID == contentRequestID, index == currentChapterIndex else { return }
            isLoadingContent = false
            contentCache[index] = cached
            apply(cached)
            prefetchAhead()
            return
        }

        isLoadingContent = true
        errorMessage = nil
        defer {
            if requestID == contentRequestID { isLoadingContent = false }
        }
        do {
            // 使用下载管理器（带超时控制），正文和段评图元数据一起缓存。
            let document: ReaderChapterContent
            if let bookURL = persistentBookURL {
                document = try await ChapterDownloadManager.shared.downloadChapterContent(
                    bookURL: bookURL,
                    book: bookSource,
                    chapter: chapter
                )
            } else {
                document = try await runtime.getChapterContent(chapterUrl: chapter.url)
            }
            guard requestID == contentRequestID, index == currentChapterIndex else { return }
            guard !document.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                errorMessage = "正文为空：当前章节没有返回内容"
                return
            }
            contentCache[index] = document
            apply(document)
            if let bookURL = persistentBookURL {
                await ChapterContentCache.shared.saveDocument(document, bookURL: bookURL, chapterURL: chapter.url)
            }
            prefetchAhead()
        } catch is TimeoutError {
            guard requestID == contentRequestID, index == currentChapterIndex else { return }
            engineLog("获取正文超时", tag: "reader", level: .error)
            errorMessage = "获取正文超时，请检查网络或更换书源"
        } catch {
            guard requestID == contentRequestID, index == currentChapterIndex else { return }
            engineLog("获取正文失败: \(error.localizedDescription)", tag: "reader", level: .error)
            errorMessage = "获取正文失败: \(error.localizedDescription)"
        }
    }

    private func apply(_ document: ReaderChapterContent) {
        currentContent = document.text
        currentMarkers = document.inlineReviewMarkers
    }

    private func cacheIsUsable(_ document: ReaderChapterContent) -> Bool {
        // 所有在线正文都要经过书源的段评处理；旧缓存必须失效。
        document.formatVersion >= ReaderChapterContent.currentFormatVersion && document.inlineReviewProcessed
    }

    // MARK: 预取与批量缓存

    /// 预取后面的章节（并发预取多章）。
    private func prefetchAhead() {
        let start = currentChapterIndex + 1
        let end = min(currentChapterIndex + prefetchCount, chapters.count - 1)
        guard start <= end else { return }

        let generation = prefetchGeneration
        for i in start...end {
            // 跳过已缓存或正在预取的
            guard contentCache[i] == nil, !prefetchTasks.contains(i) else { continue }
            prefetchTasks.insert(i)
            let chapter = chapters[i]

            Task { [weak self] in
                guard let self = self else { return }

                do {
                    let document: ReaderChapterContent
                    if let bookURL = self.persistentBookURL {
                        document = try await ChapterDownloadManager.shared.downloadChapterContent(
                            bookURL: bookURL,
                            book: self.bookSource,
                            chapter: chapter
                        )
                    } else {
                        document = try await self.runtime.getChapterContent(chapterUrl: chapter.url)
                    }
                    guard !document.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        if self.prefetchGeneration == generation { self.prefetchTasks.remove(i) }
                        return
                    }
                    guard self.prefetchGeneration == generation,
                          i < self.chapters.count,
                          self.chapters[i].url == chapter.url else { return }
                    self.contentCache[i] = document
                    if let bookURL = self.persistentBookURL {
                        await ChapterContentCache.shared.saveDocument(
                            document, bookURL: bookURL, chapterURL: chapter.url
                        )
                    }
                } catch {
                    // 预取失败静默处理，不影响当前阅读
                    engineLog("预取章节 \(i) 失败: \(error.localizedDescription)", tag: "reader", level: .info)
                }
                if self.prefetchGeneration == generation { self.prefetchTasks.remove(i) }
            }
        }
    }

    /// 开始批量缓存（整本下载入口）。
    func startCache(from startIndex: Int, to endIndex: Int) {
        guard let bookURL = persistentBookURL else { return }
        ChapterDownloadManager.shared.addDownload(
            bookURL: bookURL,
            book: bookSource,
            chapters: chapters,
            startIndex: startIndex,
            endIndex: endIndex
        )
    }

    /// 持久化缓存开关：详情页“加入书架”后调用，把当前正文落盘。
    func enablePersistentCache(bookURL: String) {
        persistentBookURL = bookURL
        guard !currentContent.isEmpty,
              chapters.indices.contains(currentChapterIndex) else { return }
        let chapterURL = chapters[currentChapterIndex].url
        let document = ReaderChapterContent(text: currentContent, inlineReviewMarkers: currentMarkers)
        Task { await ChapterContentCache.shared.saveDocument(document, bookURL: bookURL, chapterURL: chapterURL) }
    }
}
