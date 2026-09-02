import SwiftUI
import Foundation

/// 书签模型与持久化（UserDefaults + JSON，轻量实现）
struct BookBookmark: Codable, Identifiable {
    let bookUrl: String
    let chapterIndex: Int
    let pageIndex: Int
    let label: String
    let createdAt: Date

    var id: String { "\(bookUrl)#\(chapterIndex)#\(pageIndex)" }
}

enum BookmarkStore {
    private static let key = "reader.bookmarks"

    static func all(for bookUrl: String) -> [BookBookmark] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let list = try? JSONDecoder().decode([BookBookmark].self, from: data) else { return [] }
        return list.filter { $0.bookUrl == bookUrl }.sorted { $0.createdAt > $1.createdAt }
    }

    static func add(_ bookmark: BookBookmark) {
        var list = loadAll()
        list.removeAll { $0.id == bookmark.id }
        list.append(bookmark)
        save(list)
    }

    static func remove(_ bookmark: BookBookmark) {
        var list = loadAll()
        list.removeAll { $0.id == bookmark.id }
        save(list)
    }

    private static func loadAll() -> [BookBookmark] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let list = try? JSONDecoder().decode([BookBookmark].self, from: data) else { return [] }
        return list
    }

    private static func save(_ list: [BookBookmark]) {
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
