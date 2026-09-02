import Foundation

/// 本地 TXT 阅读视图模型（无需书源，直接读已解析章节）
@Observable
@MainActor
final class TxtReaderViewModel: Identifiable {
    let id = UUID()
    let bookName: String
    private(set) var chapters: [LocalChapter] = []
    private(set) var currentIndex = 0
    private(set) var currentContent = ""

    init(book: LocalBook) {
        self.bookName = book.name
        self.chapters = TxtParser.decode(book.chaptersData)
        if chapters.isEmpty {
            chapters = [LocalChapter(title: book.name, content: "")]
        }
        self.currentContent = chapters.first?.content ?? ""
    }

    var currentTitle: String {
        chapters.isEmpty ? bookName : chapters[min(currentIndex, chapters.count - 1)].title
    }

    func openChapter(_ index: Int) {
        guard !chapters.isEmpty else { return }
        currentIndex = min(max(index, 0), chapters.count - 1)
        currentContent = chapters[currentIndex].content
    }

    func nextChapter() {
        if currentIndex + 1 < chapters.count { openChapter(currentIndex + 1) }
    }

    func prevChapter() {
        if currentIndex > 0 { openChapter(currentIndex - 1) }
    }
}
