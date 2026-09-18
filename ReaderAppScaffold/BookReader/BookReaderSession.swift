import Foundation
import SwiftUI
import Observation
import LegadoRuleEngine

struct BookReaderPosition: Codable {
    let chapterIndex: Int
    let characterOffset: Int
}

enum BookReaderPositionStore {
    private static func storageKey(_ value: String) -> String { "book-reader.position.\(value)" }
    static func load(key: String) -> BookReaderPosition? {
        guard let data = UserDefaults.standard.data(forKey: storageKey(key)) else { return nil }
        return try? JSONDecoder().decode(BookReaderPosition.self, from: data)
    }
    static func save(_ value: BookReaderPosition, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: storageKey(key))
    }
}

@MainActor
@Observable
final class BookReaderSession: Identifiable {
    enum Source {
        case local(BookReaderLocalSource)
        case online(BookReaderOnlineSource, bookUrl: String, bookName: String)
    }

    let id = UUID()
    let source: Source
    let bookKey: String
    private var saved: BookReaderPosition?
    private var restored = false

    private(set) var document: BookReaderDocument?
    private(set) var pages: [BookReaderPage] = []
    private(set) var chapterForPages = -1
    private(set) var paginationKey = ""
    private(set) var requestedPage: Int?
    private(set) var requestedLastPage = false
    var pageIndex = 0

    init(source: Source) {
        self.source = source
        switch source {
        case .local(let local): bookKey = local.bookKey
        case .online(_, let url, _): bookKey = url
        }
        saved = BookReaderPositionStore.load(key: bookKey)
    }

    private var contentSource: any BookReaderContentSource {
        switch source {
        case .local(let source): return source
        case .online(let source, _, _): return source
        }
    }

    var bookTitle: String {
        switch source {
        case .local(let source): return source.bookTitle
        case .online(_, _, let name): return name
        }
    }
    var chapterCount: Int { contentSource.chapterCount }
    func chapterTitle(at index: Int) -> String { contentSource.chapterTitle(at: index) }
    var chapterIndex: Int { contentSource.currentChapterIndex }
    var chapterTitle: String { contentSource.chapterTitle(at: chapterIndex) }
    var content: String { contentSource.currentContent }
    var loading: Bool { contentSource.isLoading }
    var error: String? { contentSource.errorMessage }
    var hasNext: Bool { chapterIndex + 1 < chapterCount }
    var hasPrevious: Bool { chapterIndex > 0 }
    var reviewsEnabled: Bool { contentSource.supportsReviews }
    var markers: [InlineReviewMarker] { contentSource.markers }
    func marker(id: Int) -> InlineReviewMarker? { contentSource.marker(id: id) }

    var progress: Double {
        guard chapterCount > 1 else { return 0 }
        let chapterProgress = pages.isEmpty ? 0 : Double(pageIndex + 1) / Double(pages.count)
        return min(max((Double(chapterIndex) + chapterProgress) / Double(chapterCount), 0), 1)
    }

    func executeMarkerAction(id: Int, openBrowser: @escaping (String, String?) -> Void) {
        contentSource.executeMarkerAction(id: id, openBrowser: openBrowser)
    }

    func fetchReviews(paragraphIndex: Int, paragraphText: String, markerSource: String?) async throws -> [Review] {
        await contentSource.fetchReviews(paragraphIndex: paragraphIndex, paragraphText: paragraphText, markerSource: markerSource)
    }

    func openChapter(_ index: Int) async {
        await contentSource.openChapter(at: index)
        if requestedPage == nil, !requestedLastPage { pageIndex = 0 }
    }

    @discardableResult
    func nextPage(allowNextChapter: Bool) async -> Bool {
        if pageIndex + 1 < pages.count {
            pageIndex += 1
            return true
        }
        guard allowNextChapter, hasNext else { return false }
        requestedPage = nil
        requestedLastPage = false
        pageIndex = 0
        await openChapter(chapterIndex + 1)
        return true
    }

    func previousPage() async {
        if pageIndex > 0 {
            pageIndex -= 1
        } else if hasPrevious {
            requestedPage = nil
            requestedLastPage = true
            await openChapter(chapterIndex - 1)
        }
    }

    func jump(to bookmark: BookBookmark) async {
        if bookmark.chapterIndex == chapterIndex {
            pageIndex = min(max(bookmark.pageIndex, 0), max(pages.count - 1, 0))
            return
        }
        requestedPage = bookmark.pageIndex
        await openChapter(bookmark.chapterIndex)
    }

    func makeLayout(font: UIFont, lineSpacing: Double, paragraphSpacing: Double, indent: CGFloat, size: CGSize) -> BookReaderLayout {
        BookReaderLayout(font: font, lineSpacing: lineSpacing, paragraphSpacing: paragraphSpacing, firstLineIndent: indent, pageSize: size)
    }

    func ensureDocument(style: BookReaderStyle) {
        guard !content.isEmpty else { document = nil; return }
        document = BookReaderDocumentBuilder.make(
            title: chapterTitle,
            text: content,
            markers: markers,
            reviewsEnabled: reviewsEnabled,
            font: style.font,
            markerColor: .systemGray
        )
    }

    func ensurePages(key: String, layout: BookReaderLayout, style: BookReaderStyle) async {
        guard key != paginationKey else { return }
        let text = content
        guard !text.isEmpty else {
            pages = []
            document = nil
            chapterForPages = chapterIndex
            paginationKey = key
            return
        }
        let built = BookReaderDocumentBuilder.make(
            title: chapterTitle,
            text: text,
            markers: markers,
            reviewsEnabled: reviewsEnabled,
            font: layout.font,
            markerColor: .systemGray
        )
        let chapter = chapterIndex
        let result: [BookReaderPage]
        if let cached = BookReaderPageCache.shared.get(key) {
            result = cached
        } else {
            result = await Task.detached(priority: .userInitiated) {
                let value = BookReaderPagination.makePages(document: built, layout: layout, key: key)
                if !value.isEmpty { BookReaderPageCache.shared.put(value, key: key) }
                return value
            }.value
        }
        guard !Task.isCancelled, chapter == chapterIndex, text == content else { return }
        document = built
        pages = result
        chapterForPages = chapter
        if let target = requestedPage {
            pageIndex = min(max(target, 0), max(result.count - 1, 0))
            requestedPage = nil
        } else if requestedLastPage {
            pageIndex = max(result.count - 1, 0)
            requestedLastPage = false
        } else if !restored {
            restored = true
            if let saved, saved.chapterIndex == chapter, !result.isEmpty {
                pageIndex = result.firstIndex { saved.characterOffset < NSMaxRange($0.sourceRange) } ?? result.count - 1
            } else if pageIndex >= result.count { pageIndex = 0 }
        } else if pageIndex >= result.count {
            pageIndex = 0
        }
        paginationKey = key
    }

    func savePosition() {
        let offset = pages.indices.contains(pageIndex) ? pages[pageIndex].sourceRange.location : 0
        BookReaderPositionStore.save(BookReaderPosition(chapterIndex: chapterIndex, characterOffset: offset), key: bookKey)
    }
}
