import Foundation
import LegadoRuleEngine

@Observable
@MainActor
public final class ReaderViewModel {
    public private(set) var chapters: [ChapterInfo] = []
    public private(set) var currentIndex: Int = 0
    public private(set) var currentContent: String = ""
    /// 当前章节中由书源正文内嵌的 `style: "TEXT"` 图片生成的段评入口。
    public private(set) var currentReviewMarkers: [InlineReviewMarker] = []
    public var isLoadingToc = false
    public var isLoadingContent = false
    public var errorMessage: String?

    private let source: BookSource
    private let runtime: BookSourceRuntime
    private var contentCache: [Int: ReaderChapterContent] = [:]
    private var persistentBookURL: String?
    /// 标识当前正文请求，防止快速切章时旧请求覆盖新章节。
    private var contentRequestID = UUID()
    /// 标识当前目录，防止刷新目录后旧预取任务访问失效索引。
    private var tocRequestID = UUID()
    /// 预取任务所属目录版本。
    private var prefetchGeneration = UUID()
    /// 预取的章节数量（参考 legado-E 预下载机制）
    public var prefetchCount: Int = 3
    /// 正在预取的任务
    private var prefetchTasks: Set<Int> = []

    public init(source: BookSource, persistentBookURL: String? = nil) {
        self.source = source
        self.runtime = BookSourceRuntime(source)
        self.persistentBookURL = persistentBookURL
    }

    /// 当前书源是否支持段评（即是否配置了 ruleReview.reviewUrl）
    public var reviewEnabled: Bool {
        // ruleReview 是传统配置；正文内嵌 style:"TEXT" marker 不依赖 ruleReview。
        if currentReviewMarkers.isEmpty == false { return true }
        if let ruleReview = source.ruleReview,
           let reviewUrl = ruleReview.reviewUrl,
           !reviewUrl.isEmpty {
            return true
        }
        return false
    }

    /// 执行正文内嵌段评图的 click/js 选项。
    public func executeInlineReviewAction(
        markerID: Int,
        browserOpener: @escaping (_ url: String, _ title: String?) -> Void
    ) {
        guard let marker = currentReviewMarkers.first(where: { $0.id == markerID }),
              currentIndex >= 0, currentIndex < chapters.count,
              let action = marker.action else { return }
        let chapter = chapters[currentIndex]
        runtime.executeInlineReviewAction(
            action,
            markerSource: marker.source,
            chapterUrl: chapter.url,
            browserOpener: browserOpener
        )
    }

    /// 获取某段落的评论列表
    /// - Parameters:
    ///   - paragraphIndex: 段落索引
    ///   - paragraphText: 段落文本
    /// - Returns: 评论列表
    public func fetchReviews(
        paragraphIndex: Int,
        paragraphText: String,
        markerSource: String? = nil
    ) async -> [Review] {
        guard reviewEnabled || markerSource?.isEmpty == false else { return [] }
        guard currentIndex >= 0, currentIndex < chapters.count else { return [] }

        let chapterUrl = chapters[currentIndex].url
        do {
            let rawReviews = try await runtime.getReviews(
                chapterUrl: chapterUrl,
                paragraphText: paragraphText,
                reviewURL: markerSource
            )
            // 转换原始数据为 Review 模型
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

    public func enablePersistentCache(bookURL: String) {
        persistentBookURL = bookURL
        guard !currentContent.isEmpty,
              currentIndex >= 0, currentIndex < chapters.count else { return }
        let chapterURL = chapters[currentIndex].url
        let document = ReaderChapterContent(text: currentContent, inlineReviewMarkers: currentReviewMarkers)
        Task { await ChapterContentCache.shared.saveDocument(document, bookURL: bookURL, chapterURL: chapterURL) }
    }

    public var currentChapterTitle: String? {
        guard currentIndex >= 0, currentIndex < chapters.count else { return nil }
        return chapters[currentIndex].name
    }

    public var hasNextChapter: Bool {
        currentIndex + 1 < chapters.count
    }

    public var hasPreviousChapter: Bool {
        currentIndex > 0
    }

    public func loadToc(bookUrl: String) async {
        isLoadingToc = true
        errorMessage = nil
        contentRequestID = UUID()
        isLoadingContent = false
        let requestID = UUID()
        tocRequestID = requestID
        prefetchGeneration = UUID()
        contentCache.removeAll()
        prefetchTasks.removeAll()
        currentIndex = 0
        currentContent = ""
        currentReviewMarkers = []
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

    /// 打开某一章，startIndex 一般是书架里记的"上次读到第几章"
    public func openChapter(at index: Int) async {
        guard index >= 0, index < chapters.count else { return }
        guard index != currentIndex || currentContent.isEmpty else { return }
        currentIndex = index
        contentRequestID = UUID()
        currentContent = ""
        currentReviewMarkers = []
        errorMessage = nil
        await loadCurrentContent()
    }

    public func nextChapter() async {
        guard currentIndex + 1 < chapters.count else { return }
        currentIndex += 1
        contentRequestID = UUID()
        currentContent = ""
        errorMessage = nil
        await loadCurrentContent()
    }

    public func prevChapter() async {
        guard currentIndex > 0 else { return }
        currentIndex -= 1
        contentRequestID = UUID()
        currentContent = ""
        errorMessage = nil
        await loadCurrentContent()
    }

    private func loadCurrentContent() async {
        guard currentIndex >= 0, currentIndex < chapters.count else {
            isLoadingContent = false
            errorMessage = "无法打开正文：章节参数无效"
            return
        }

        let index = currentIndex
        let chapter = chapters[index]
        let requestID = contentRequestID

        // 内存缓存
        if let cached = contentCache[index] {
            guard requestID == contentRequestID, index == currentIndex else { return }
            isLoadingContent = false
            apply(cached)
            prefetchAhead()
            return
        }
        // 磁盘缓存；兼容旧版纯文本缓存。
        if let bookURL = persistentBookURL,
           let cached = await ChapterContentCache.shared.loadDocument(bookURL: bookURL, chapterURL: chapter.url) {
            guard requestID == contentRequestID, index == currentIndex else { return }
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
                    book: source,
                    chapter: chapter
                )
            } else {
                document = try await runtime.getChapterContent(chapterUrl: chapter.url)
            }
            guard requestID == contentRequestID, index == currentIndex else { return }
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
            guard requestID == contentRequestID, index == currentIndex else { return }
            engineLog("获取正文超时", tag: "reader", level: .error)
            errorMessage = "获取正文超时，请检查网络或更换书源"
        } catch {
            guard requestID == contentRequestID, index == currentIndex else { return }
            engineLog("获取正文失败: \(error.localizedDescription)", tag: "reader", level: .error)
            errorMessage = "获取正文失败: \(error.localizedDescription)"
        }
    }

    private func apply(_ document: ReaderChapterContent) {
        currentContent = document.text
        currentReviewMarkers = document.inlineReviewMarkers
    }

    /// 预取后面的章节（参考 legado-E 预下载机制，并发预取多章）
    private func prefetchAhead() {
        let start = currentIndex + 1
        let end = min(currentIndex + prefetchCount, chapters.count - 1)
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
                            book: self.source,
                            chapter: chapter
                        )
                    } else {
                        document = try await self.runtime.getChapterContent(chapterUrl: chapter.url)
                    }
                    guard !document.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        await MainActor.run {
                            if self.prefetchGeneration == generation { self.prefetchTasks.remove(i) }
                        }
                        return
                    }
                    await MainActor.run {
                        guard self.prefetchGeneration == generation,
                              i < self.chapters.count,
                              self.chapters[i].url == chapter.url else { return }
                        self.contentCache[i] = document
                    }
                    if let bookURL = self.persistentBookURL {
                        await ChapterContentCache.shared.saveDocument(
                            document, bookURL: bookURL, chapterURL: chapter.url
                        )
                    }
                } catch {
                    // 预取失败静默处理，不影响当前阅读
                    engineLog("预取章节 \(i) 失败: \(error.localizedDescription)", tag: "reader", level: .info)
                }
                await MainActor.run {
                    if self.prefetchGeneration == generation { self.prefetchTasks.remove(i) }
                }
            }
        }
    }

    /// 开始批量缓存（参考 legado-E CacheBook.start）
    public func startCache(from startIndex: Int, to endIndex: Int) {
        guard let bookURL = persistentBookURL else { return }
        ChapterDownloadManager.shared.addDownload(
            bookURL: bookURL,
            book: source,
            chapters: chapters,
            startIndex: startIndex,
            endIndex: endIndex
        )
    }
}

extension ReaderViewModel: Identifiable, Hashable {
    public var id: ObjectIdentifier { ObjectIdentifier(self) }
    public static func == (lhs: ReaderViewModel, rhs: ReaderViewModel) -> Bool { lhs === rhs }
    public func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
}
