import Foundation
import SwiftUI
import Observation
import LegadoRuleEngine

struct ReaderPagePosition: Codable {
    let chapterIndex: Int
    let characterOffset: Int
}

enum ReaderPagePositionStore {
    private static func key(_ bookKey: String) -> String { "reader.page.position.\(bookKey)" }

    static func load(bookKey: String) -> ReaderPagePosition? {
        guard let data = UserDefaults.standard.data(forKey: key(bookKey)) else { return nil }
        return try? JSONDecoder().decode(ReaderPagePosition.self, from: data)
    }

    static func save(_ position: ReaderPagePosition, bookKey: String) {
        guard let data = try? JSONEncoder().encode(position) else { return }
        UserDefaults.standard.set(data, forKey: key(bookKey))
    }
}

@MainActor
@Observable
final class ReaderPageSession: Identifiable {
    enum Source {
        case local(ReaderPageLocalSource)
        case online(ReaderPageOnlineSource, bookUrl: String, bookName: String)
    }

    let id = UUID()
    let source: Source
    let bookKey: String
    private var savedPosition: ReaderPagePosition?
    private var didRestore = false

    private(set) var pages: [ReaderBookPage] = []
    private(set) var pagesChapterIndex = -1
    private(set) var paginatedKey = ""
    private(set) var pendingPage: Int?
    private(set) var pendingLastPage = false
    var pageIndex = 0

    init(source: Source) {
        self.source = source
        switch source {
        case .local(let source):
            bookKey = source.bookKey
        case .online(_, let bookUrl, _):
            bookKey = bookUrl
        }
        savedPosition = ReaderPagePositionStore.load(bookKey: bookKey)
    }

    private var contentSource: any ReaderPageContentSource {
        switch source {
        case .local(let local): return local
        case .online(let online, _, _): return online
        }
    }

    var bookTitle: String {
        switch source {
        case .local(let local): return local.bookTitle
        case .online(_, _, let name): return name
        }
    }

    var chapterCount: Int { contentSource.chapterCount }
    func chapterTitle(at index: Int) -> String { contentSource.chapterTitle(at: index) }
    var currentChapterIndex: Int { contentSource.currentChapterIndex }
    var currentChapterTitle: String { contentSource.chapterTitle(at: currentChapterIndex) }
    var currentContent: String { contentSource.currentContent }
    var isLoading: Bool { contentSource.isLoading }
    var errorMessage: String? { contentSource.errorMessage }
    var hasNextChapter: Bool { currentChapterIndex + 1 < chapterCount }
    var hasPreviousChapter: Bool { currentChapterIndex > 0 }
    var supportsReviews: Bool { contentSource.supportsReviews }
    var markers: [InlineReviewMarker] { contentSource.currentMarkers }
    func marker(id: Int) -> InlineReviewMarker? { contentSource.marker(id: id) }

    var progress: Double {
        guard chapterCount > 1 else { return 0 }
        let chapterProgress = pages.isEmpty ? 0 : Double(pageIndex + 1) / Double(pages.count)
        return min(max((Double(currentChapterIndex) + chapterProgress) / Double(chapterCount), 0), 1)
    }

    func executeMarkerAction(id: Int, openBrowser: @escaping (String, String?) -> Void) {
        contentSource.executeMarkerAction(id: id, openBrowser: openBrowser)
    }

    func fetchReviews(paragraphIndex: Int, paragraphText: String, markerSource: String?) async throws -> [Review] {
        await contentSource.fetchReviews(paragraphIndex: paragraphIndex, paragraphText: paragraphText, markerSource: markerSource)
    }

    func openChapter(_ index: Int) async {
        await contentSource.openChapter(at: index)
        if pendingPage == nil, !pendingLastPage { pageIndex = 0 }
    }

    @discardableResult
    func nextPage(allowNextChapter: Bool) async -> Bool {
        if pageIndex + 1 < pages.count {
            pageIndex += 1
            return true
        }
        guard allowNextChapter, hasNextChapter else { return false }
        pageIndex = 0
        pendingPage = nil
        pendingLastPage = false
        await openChapter(currentChapterIndex + 1)
        return true
    }

    func previousPage() async {
        if pageIndex > 0 {
            pageIndex -= 1
        } else if hasPreviousChapter {
            pendingPage = nil
            pendingLastPage = true
            await openChapter(currentChapterIndex - 1)
        }
    }

    func jump(to bookmark: BookBookmark) async {
        if bookmark.chapterIndex == currentChapterIndex {
            pageIndex = min(max(bookmark.pageIndex, 0), max(pages.count - 1, 0))
            return
        }
        pendingPage = bookmark.pageIndex
        await openChapter(bookmark.chapterIndex)
    }

    static func key(content: String, markers: [InlineReviewMarker], chapter: Int, layout: ReaderPageLayout) -> String {
        let markerKey = markers.map { "\($0.id):\($0.paragraphIndex):\($0.count)" }.joined(separator: ",")
        return "\(ReaderPageDocumentBuilder.fingerprint(content))|\(layout.signature)|\(markerKey)|\(chapter)"
    }

    func ensurePages(key: String, layout: ReaderPageLayout) async {
        guard key != paginatedKey else { return }
        let content = currentContent
        guard !content.isEmpty else {
            pages = []
            pagesChapterIndex = currentChapterIndex
            paginatedKey = key
            return
        }

        let document = ReaderPageDocumentBuilder.make(
            title: currentChapterTitle,
            text: content,
            markers: markers,
            reviewsEnabled: supportsReviews,
            font: layout.font,
            markerColor: .systemGray
        )
        let chapter = currentChapterIndex
        let result: [ReaderBookPage]
        if let cached = ReaderPageCache.shared.get(key) {
            result = cached
        } else {
            result = await Task.detached(priority: .userInitiated) {
                let pages = ReaderPagePagination.paginate(document: document, layout: layout, key: key)
                if !pages.isEmpty { ReaderPageCache.shared.put(pages, key: key) }
                return pages
            }.value
        }

        guard !Task.isCancelled, chapter == currentChapterIndex, content == currentContent else { return }
        pages = result
        pagesChapterIndex = chapter
        if let target = pendingPage {
            pageIndex = min(max(target, 0), max(result.count - 1, 0))
            pendingPage = nil
        } else if pendingLastPage {
            pageIndex = max(result.count - 1, 0)
            pendingLastPage = false
        } else if !didRestore {
            didRestore = true
            if let savedPosition, savedPosition.chapterIndex == chapter, !result.isEmpty {
                pageIndex = result.firstIndex { savedPosition.characterOffset < NSMaxRange($0.sourceRange) } ?? result.count - 1
            } else if pageIndex >= result.count {
                pageIndex = 0
            }
        } else if pageIndex >= result.count {
            pageIndex = 0
        }
        paginatedKey = key
    }

    func savePosition() {
        let offset = pages.indices.contains(pageIndex) ? pages[pageIndex].sourceRange.location : 0
        ReaderPagePositionStore.save(
            ReaderPagePosition(chapterIndex: currentChapterIndex, characterOffset: offset),
            bookKey: bookKey
        )
    }
}
