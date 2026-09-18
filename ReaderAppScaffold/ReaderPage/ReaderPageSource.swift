import Foundation
import SwiftUI
import Observation
import LegadoRuleEngine

@MainActor
protocol ReaderPageContentSource: AnyObject {
    var bookKey: String { get }
    var bookTitle: String { get }
    var chapterCount: Int { get }
    func chapterTitle(at index: Int) -> String
    var currentChapterIndex: Int { get }
    var currentContent: String { get }
    var isLoading: Bool { get }
    var errorMessage: String? { get }
    func openChapter(at index: Int) async

    var supportsReviews: Bool { get }
    var currentMarkers: [InlineReviewMarker] { get }
    func marker(id: Int) -> InlineReviewMarker?
    func executeMarkerAction(id: Int, openBrowser: @escaping (String, String?) -> Void)
    func fetchReviews(paragraphIndex: Int, paragraphText: String, markerSource: String?) async -> [Review]
}

extension ReaderPageContentSource {
    var supportsReviews: Bool { false }
    var currentMarkers: [InlineReviewMarker] { [] }
    func marker(id: Int) -> InlineReviewMarker? { nil }
    func executeMarkerAction(id: Int, openBrowser: @escaping (String, String?) -> Void) {}
    func fetchReviews(paragraphIndex: Int, paragraphText: String, markerSource: String?) async -> [Review] { [] }
}

@MainActor
@Observable
final class ReaderPageLocalSource: ReaderPageContentSource {
    let book: LocalBook
    let chapters: [LocalChapter]
    private(set) var currentChapterIndex = 0

    init(book: LocalBook) {
        self.book = book
        var decoded = TxtParser.decode(book.chaptersData)
        if decoded.isEmpty { decoded = [LocalChapter(title: book.name, content: "")] }
        self.chapters = decoded
        if let saved = ReaderPagePositionStore.load(bookKey: "local://\(book.id)"), chapters.indices.contains(saved.chapterIndex) {
            self.currentChapterIndex = saved.chapterIndex
        }
    }

    var bookKey: String { "local://\(book.id)" }
    var bookTitle: String { book.name }
    var chapterCount: Int { chapters.count }
    func chapterTitle(at index: Int) -> String { chapters.indices.contains(index) ? chapters[index].title : book.name }
    var currentContent: String { chapters.indices.contains(currentChapterIndex) ? chapters[currentChapterIndex].content : "" }
    var isLoading: Bool { false }
    var errorMessage: String? { nil }

    func openChapter(at index: Int) async {
        currentChapterIndex = min(max(index, 0), max(chapters.count - 1, 0))
    }
}

@MainActor
@Observable
final class ReaderPageOnlineSource: Identifiable, Hashable, ReaderPageContentSource {
    let bookSource: BookSource
    private let runtime: BookSourceRuntime
    private var persistentBookURL: String?

    private(set) var chapters: [ChapterInfo] = []
    private(set) var currentChapterIndex = 0
    private(set) var currentContent = ""
    private(set) var currentMarkers: [InlineReviewMarker] = []
    var isLoadingToc = false
    var isLoadingContent = false
    var errorMessage: String?
    private var requestID = UUID()
    private var tocID = UUID()
    private var memoryCache: [Int: ReaderChapterContent] = [:]

    init(bookSource: BookSource, persistentBookURL: String? = nil) {
        self.bookSource = bookSource
        self.runtime = BookSourceRuntime(bookSource)
        self.persistentBookURL = persistentBookURL
    }

    var id: ObjectIdentifier { ObjectIdentifier(self) }
    static func == (lhs: ReaderPageOnlineSource, rhs: ReaderPageOnlineSource) -> Bool { lhs === rhs }
    func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }

    var bookKey: String { persistentBookURL ?? bookSource.bookSourceUrl }
    var bookTitle: String { bookSource.bookSourceName }
    var chapterCount: Int { chapters.count }
    func chapterTitle(at index: Int) -> String { chapters.indices.contains(index) ? chapters[index].name : bookTitle }
    var isLoading: Bool { isLoadingToc || isLoadingContent }

    var supportsReviews: Bool {
        if !currentMarkers.isEmpty { return true }
        return !(bookSource.ruleReview?.reviewUrl?.isEmpty ?? true)
    }

    func marker(id: Int) -> InlineReviewMarker? { currentMarkers.first { $0.id == id } }

    func executeMarkerAction(id: Int, openBrowser: @escaping (String, String?) -> Void) {
        guard let marker = marker(id: id), chapters.indices.contains(currentChapterIndex), let action = marker.action else { return }
        runtime.executeInlineReviewAction(
            action,
            markerSource: marker.source,
            chapterUrl: chapters[currentChapterIndex].url,
            browserOpener: openBrowser
        )
    }

    func fetchReviews(paragraphIndex: Int, paragraphText: String, markerSource: String?) async -> [Review] {
        guard supportsReviews || markerSource?.isEmpty == false,
              chapters.indices.contains(currentChapterIndex) else { return [] }
        do {
            let raw = try await runtime.getReviews(
                chapterUrl: chapters[currentChapterIndex].url,
                paragraphText: paragraphText,
                reviewURL: markerSource
            )
            return raw.map {
                Review(
                    userName: $0["userName"] ?? "匿名",
                    avatarUrl: $0["avatarUrl"],
                    content: $0["content"] ?? "",
                    postTime: $0["postTime"],
                    likeCount: Int($0["likeCount"] ?? ""),
                    replyCount: Int($0["replyCount"] ?? "")
                )
            }
        } catch {
            engineLog("获取段评失败: \(error.localizedDescription)", tag: "reader", level: .error)
            return []
        }
    }

    func loadToc(bookUrl: String) async {
        let loadID = UUID()
        tocID = loadID
        isLoadingToc = true
        isLoadingContent = false
        errorMessage = nil
        currentContent = ""
        currentMarkers = []
        chapters = []
        memoryCache.removeAll()
        currentChapterIndex = 0
        guard !bookUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "无法打开：书籍地址为空"
            isLoadingToc = false
            return
        }
        do {
            let result = try await runtime.getToc(bookUrl: bookUrl)
            guard tocID == loadID else { return }
            chapters = result
            if result.isEmpty { errorMessage = "目录为空：当前书源未返回章节" }
        } catch {
            guard tocID == loadID else { return }
            errorMessage = "获取目录失败：\(error.localizedDescription)"
        }
        if tocID == loadID { isLoadingToc = false }
    }

    func openChapter(at index: Int) async {
        guard chapters.indices.contains(index) else { return }
        guard index != currentChapterIndex || currentContent.isEmpty else { return }
        currentChapterIndex = index
        requestID = UUID()
        currentContent = ""
        currentMarkers = []
        errorMessage = nil
        await loadCurrentChapter()
    }

    private func loadCurrentChapter() async {
        guard chapters.indices.contains(currentChapterIndex) else { return }
        let chapterIndex = currentChapterIndex
        let chapter = chapters[chapterIndex]
        let loadID = requestID
        isLoadingContent = true
        defer {
            if requestID == loadID { isLoadingContent = false }
        }

        do {
            let document: ReaderChapterContent
            if let cached = memoryCache[chapterIndex], cached.inlineReviewProcessed {
                document = cached
            } else if let bookURL = persistentBookURL,
                      let cached = await ChapterContentCache.shared.loadDocument(bookURL: bookURL, chapterURL: chapter.url),
                      cached.inlineReviewProcessed {
                document = cached
                memoryCache[chapterIndex] = cached
            } else if let bookURL = persistentBookURL {
                document = try await ChapterDownloadManager.shared.downloadChapterContent(
                    bookURL: bookURL,
                    book: bookSource,
                    chapter: chapter
                )
                memoryCache[chapterIndex] = document
                await ChapterContentCache.shared.saveDocument(document, bookURL: bookURL, chapterURL: chapter.url)
            } else {
                document = try await runtime.getChapterContent(chapterUrl: chapter.url)
                memoryCache[chapterIndex] = document
            }
            guard requestID == loadID, chapterIndex == currentChapterIndex else { return }
            guard !document.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                errorMessage = "正文为空：当前章节没有返回内容"
                return
            }
            currentContent = document.text
            currentMarkers = document.inlineReviewMarkers
        } catch is TimeoutError {
            if requestID == loadID { errorMessage = "获取正文超时，请检查网络或更换书源" }
        } catch {
            if requestID == loadID { errorMessage = "获取正文失败：\(error.localizedDescription)" }
        }
    }

    func enablePersistentCache(bookURL: String) {
        persistentBookURL = bookURL
        guard chapters.indices.contains(currentChapterIndex), !currentContent.isEmpty else { return }
        let document = ReaderChapterContent(text: currentContent, inlineReviewMarkers: currentMarkers)
        Task { await ChapterContentCache.shared.saveDocument(document, bookURL: bookURL, chapterURL: chapters[currentChapterIndex].url) }
    }
}
