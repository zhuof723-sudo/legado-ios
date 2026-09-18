import Foundation

// MARK: - Engine-side storage locations
//
// Simplified port of the app's StorageLocations: only the cache directories the
// book-source engine needs, all under Application Support.

enum StorageLocations {
    static var support: URL {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        ensureDirectory(url)
        return url
    }

    /// Downloaded chapters of online books, per book id.
    static var onlineCache: URL { directory("online_cache") }

    /// Book-source table-of-contents cache.
    static var tocCache: URL { directory("toc_cache") }

    /// Book-source book-detail cache.
    static var bookInfoCache: URL { directory("book_info_cache") }

    private static func directory(_ name: String) -> URL {
        let url = support.appendingPathComponent(name, isDirectory: true)
        ensureDirectory(url)
        return url
    }

    private static func ensureDirectory(_ url: URL) {
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            AppLogger.error("StorageLocations could not create \(url.lastPathComponent)", error: error)
        }
    }
}

// MARK: - Chapter cache models

struct ChapterPackageArtifact: Codable, Equatable {
    let sourceURL: String?
    let tocTitle: String?
    let canonicalTitle: String?
    let contentChecksum: String
    let rawHTMLFilename: String?
    let normalizedHTMLFilename: String?
    var renderArtifactVersion: Int? = nil
    let savedAt: Date
}

enum ChapterPackageState: String, Codable, Equatable {
    case cached
    case failed
}

enum OnlineChapterRenderArtifact {
    /// Bump when normalized chapter HTML semantics change in a way that cannot
    /// be reconstructed from the persisted plain-text chapter body.
    static let currentVersion = 3
}

struct BSChapterPackage: Codable, Equatable {
    let bookId: UUID
    let chapterIndex: Int
    let sourceURL: String?
    let tocTitle: String?
    let canonicalTitle: String?
    let content: String
    let contentChecksum: String
    let rawHTMLFilename: String?
    let normalizedHTMLFilename: String?
    var renderArtifactVersion: Int? = nil
    let savedAt: Date
    let state: ChapterPackageState
    let failureReason: String?

    var renderTitle: String {
        canonicalTitle?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? canonicalTitle!.trimmingCharacters(in: .whitespacesAndNewlines)
            : (tocTitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct BSTOCPackage: Codable {
    let sourceId: UUID
    let sourceName: String
    let tocURL: String
    let runtimeVariables: [String: String]?
    let chapters: [BSOnlineChapterRef]
    let rawHTMLFilename: String?
    let savedAt: Date
}

struct BSBookInfoPackage: Codable {
    let sourceId: UUID
    let sourceName: String
    let bookURL: String
    let name: String
    let author: String
    let intro: String
    let coverUrl: String
    let tocUrl: String
    let wordCount: String
    let lastChapter: String
    let kind: String
    let runtimeVariables: [String: String]?
    let rawHTMLFilename: String?
    let savedAt: Date

    var onlineBook: BSOnlineBook {
        BSOnlineBook(
            name: name,
            author: author,
            intro: intro,
            coverUrl: coverUrl,
            bookUrl: bookURL,
            tocUrl: tocUrl,
            wordCount: wordCount,
            lastChapter: lastChapter,
            kind: kind,
            sourceId: sourceId,
            sourceName: sourceName,
            runtimeVariables: runtimeVariables
        )
    }

    /// Fills empty fields from the search result the user actually picked.
    ///
    /// Legado's analyzeBookInfo updates the Book it was handed rather than building a
    /// fresh one, so a field the detail page does not yield keeps whatever the search
    /// stage found. Many real sources ship an empty `ruleBookInfo.name` precisely
    /// because they rely on that.
    func merging(searchResult known: BSOnlineBook?, canReName: Bool) -> BSBookInfoPackage {
        guard let known else { return self }

        func preferParsed(_ parsed: String, _ fallback: String) -> String {
            parsed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallback : parsed
        }
        func preferParsedRenamable(_ parsed: String, _ fallback: String) -> String {
            guard !parsed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return fallback
            }
            let fallbackIsEmpty = fallback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            return (canReName || fallbackIsEmpty) ? parsed : fallback
        }

        return BSBookInfoPackage(
            sourceId: sourceId,
            sourceName: sourceName,
            bookURL: bookURL,
            name: preferParsedRenamable(name, known.name),
            author: preferParsedRenamable(author, known.author),
            intro: preferParsed(intro, known.intro),
            coverUrl: preferParsed(coverUrl, known.coverUrl),
            tocUrl: preferParsed(tocUrl, known.tocUrl),
            wordCount: preferParsed(wordCount, known.wordCount),
            lastChapter: preferParsed(lastChapter, known.lastChapter),
            kind: preferParsed(kind, known.kind),
            runtimeVariables: runtimeVariables ?? known.runtimeVariables,
            rawHTMLFilename: rawHTMLFilename,
            savedAt: savedAt
        )
    }
}
