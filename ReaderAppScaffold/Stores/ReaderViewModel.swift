import Foundation
import LegadoRuleEngine

@Observable
@MainActor
public final class ReaderViewModel {
    public private(set) var chapters: [ChapterInfo] = []
    public private(set) var currentIndex: Int = 0
    public private(set) var currentContent: String = ""
    public var isLoadingToc = false
    public var isLoadingContent = false
    public var errorMessage: String?

    private let runtime: BookSourceRuntime
    private var contentCache: [Int: String] = [:]

    public init(source: BookSource) {
        self.runtime = BookSourceRuntime(source)
    }

    public var currentChapterTitle: String? {
        guard currentIndex >= 0, currentIndex < chapters.count else { return nil }
        return chapters[currentIndex].name
    }

    public func loadToc(bookUrl: String) async {
        isLoadingToc = true
        errorMessage = nil
        defer { isLoadingToc = false }
        do {
            chapters = try await runtime.getToc(bookUrl: bookUrl)
        } catch {
            errorMessage = "获取目录失败: \(error.localizedDescription)"
        }
    }

    /// 打开某一章，startIndex 一般是书架里记的"上次读到第几章"
    public func openChapter(at index: Int) async {
        guard index >= 0, index < chapters.count else { return }
        currentIndex = index
        await loadCurrentContent()
    }

    public func nextChapter() async {
        guard currentIndex + 1 < chapters.count else { return }
        currentIndex += 1
        await loadCurrentContent()
    }

    public func prevChapter() async {
        guard currentIndex - 1 >= 0 else { return }
        currentIndex -= 1
        await loadCurrentContent()
    }

    private func loadCurrentContent() async {
        guard currentIndex >= 0, currentIndex < chapters.count else { return }
        if let cached = contentCache[currentIndex] {
            currentContent = cached
            prefetchNext()
            return
        }
        isLoadingContent = true
        errorMessage = nil
        defer { isLoadingContent = false }
        do {
            let text = try await runtime.getContent(chapterUrl: chapters[currentIndex].url)
            contentCache[currentIndex] = text
            currentContent = text
            prefetchNext()
        } catch {
            errorMessage = "获取正文失败: \(error.localizedDescription)"
        }
    }

    /// 预取下一章，翻页体验更顺滑
    private func prefetchNext() {
        let next = currentIndex + 1
        guard next < chapters.count, contentCache[next] == nil else { return }
        Task {
            if let text = try? await runtime.getContent(chapterUrl: chapters[next].url) {
                contentCache[next] = text
            }
        }
    }
}

extension ReaderViewModel: Identifiable, Hashable {
    public var id: ObjectIdentifier { ObjectIdentifier(self) }
    public static func == (lhs: ReaderViewModel, rhs: ReaderViewModel) -> Bool { lhs === rhs }
    public func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
}
