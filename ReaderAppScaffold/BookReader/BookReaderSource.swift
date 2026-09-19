import Foundation
import SwiftUI
import Observation
import LegadoRuleEngine

@MainActor
protocol BookReaderContentSource: AnyObject {
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
    var markers: [InlineReviewMarker] { get }
    func marker(id: Int) -> InlineReviewMarker?
    func executeMarkerAction(id: Int, openBrowser: @escaping (String, String?) -> Void)
    func fetchReviews(paragraphIndex: Int, paragraphText: String, markerSource: String?) async -> [Review]
}

extension BookReaderContentSource {
    var supportsReviews: Bool { false }
    var markers: [InlineReviewMarker] { [] }
    func marker(id: Int) -> InlineReviewMarker? { nil }
    func executeMarkerAction(id: Int, openBrowser: @escaping (String, String?) -> Void) {}
    func fetchReviews(paragraphIndex: Int, paragraphText: String, markerSource: String?) async -> [Review] { [] }
}

@MainActor
@Observable
final class BookReaderLocalSource: BookReaderContentSource {
    let book: LocalBook
    let chapters: [BookReaderChapter]
    private(set) var currentChapterIndex = 0

    init(book: LocalBook) {
        self.book = book
        var decoded = BookReaderFileParser.decode(book.chaptersData)
        if decoded.isEmpty { decoded = [BookReaderChapter(title: book.name, content: "")] }
        chapters = decoded
        if let saved = BookReaderPositionStore.load(key: "book-local://\(book.id)"), chapters.indices.contains(saved.chapterIndex) {
            currentChapterIndex = saved.chapterIndex
        }
    }

    var bookKey: String { "book-local://\(book.id)" }
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
final class BookReaderOnlineSource: Identifiable, Hashable, BookReaderContentSource {
    let bookSource: BookSource
    private let runtime: BookSourceRuntime
    private var persistentBookURL: String?

    private(set) var chapters: [ChapterInfo] = []
    private(set) var currentChapterIndex = 0
    private(set) var currentContent = ""
    private(set) var markers: [InlineReviewMarker] = []
    var isLoadingToc = false
    var isLoadingContent = false
    var errorMessage: String?
    private var requestID = UUID()
    private var tocID = UUID()
    private var cache: [Int: ReaderChapterContent] = [:]
    private var markersByID: [Int: InlineReviewMarker] = [:]

    init(bookSource: BookSource, persistentBookURL: String? = nil) {
        self.bookSource = bookSource
        runtime = BookSourceRuntime(bookSource)
        self.persistentBookURL = persistentBookURL
    }

    var id: ObjectIdentifier { ObjectIdentifier(self) }
    static func == (lhs: BookReaderOnlineSource, rhs: BookReaderOnlineSource) -> Bool { lhs === rhs }
    func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }

    var bookKey: String { persistentBookURL ?? bookSource.bookSourceUrl }
    var bookTitle: String { bookSource.bookSourceName }
    var chapterCount: Int { chapters.count }
    func chapterTitle(at index: Int) -> String { chapters.indices.contains(index) ? chapters[index].name : bookTitle }
    var isLoading: Bool { isLoadingToc || isLoadingContent }

    var supportsReviews: Bool {
        !markers.isEmpty || !(bookSource.ruleReview?.reviewUrl?.isEmpty ?? true)
    }

    func marker(id: Int) -> InlineReviewMarker? { markersByID[id] }

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
        let id = UUID()
        tocID = id
        isLoadingToc = true
        isLoadingContent = false
        errorMessage = nil
        currentContent = ""
        markers = []
        chapters = []
        cache.removeAll()
        currentChapterIndex = 0
        guard !bookUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "无法打开：书籍地址为空"
            isLoadingToc = false
            return
        }
        do {
            let result = try await runtime.getToc(bookUrl: bookUrl)
            guard tocID == id else { return }
            chapters = result
            if result.isEmpty { errorMessage = "目录为空：当前书源未返回章节" }
        } catch {
            guard tocID == id else { return }
            errorMessage = "获取目录失败：\(error.localizedDescription)"
        }
        if tocID == id { isLoadingToc = false }
    }

    func openChapter(at index: Int) async {
        guard chapters.indices.contains(index) else { return }
        guard index != currentChapterIndex || currentContent.isEmpty else { return }
        currentChapterIndex = index
        requestID = UUID()
        currentContent = ""
        markers = []
        markersByID = [:]
        errorMessage = nil
        await loadChapter()
    }

    private func loadChapter() async {
        guard chapters.indices.contains(currentChapterIndex) else { return }
        let index = currentChapterIndex
        let chapter = chapters[index]
        let id = requestID
        isLoadingContent = true
        defer {
            if requestID == id { isLoadingContent = false }
        }

        do {
            let document: ReaderChapterContent
            if let cached = cache[index], cached.inlineReviewProcessed {
                document = cached
            } else if let bookURL = persistentBookURL,
                      let cached = await ChapterContentCache.shared.loadDocument(bookURL: bookURL, chapterURL: chapter.url),
                      cached.inlineReviewProcessed {
                document = cached
                cache[index] = cached
            } else if let bookURL = persistentBookURL {
                document = try await ChapterDownloadManager.shared.downloadChapterContent(
                    bookURL: bookURL,
                    book: bookSource,
                    chapter: chapter
                )
                cache[index] = document
                await ChapterContentCache.shared.saveDocument(document, bookURL: bookURL, chapterURL: chapter.url)
            } else {
                document = try await runtime.getChapterContent(chapterUrl: chapter.url)
                cache[index] = document
            }
            guard requestID == id, currentChapterIndex == index else { return }
            guard !document.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                errorMessage = "正文为空：当前章节没有返回内容"
                return
            }
            currentContent = ReadingTextNormalizer.normalizePlainText(document.text)
            markers = document.inlineReviewMarkers
            markersByID = Dictionary(uniqueKeysWithValues: markers.map { ($0.id, $0) })
        } catch is TimeoutError {
            if requestID == id { errorMessage = "获取正文超时，请检查网络或更换书源" }
        } catch {
            if requestID == id { errorMessage = "获取正文失败：\(error.localizedDescription)" }
        }
    }

    func enablePersistentCache(bookURL: String) {
        persistentBookURL = bookURL
        guard chapters.indices.contains(currentChapterIndex), !currentContent.isEmpty else { return }
        let document = ReaderChapterContent(text: currentContent, inlineReviewMarkers: markers)
        Task { await ChapterContentCache.shared.saveDocument(document, bookURL: bookURL, chapterURL: chapters[currentChapterIndex].url) }
    }
}
