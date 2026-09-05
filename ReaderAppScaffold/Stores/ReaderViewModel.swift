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
    private var persistentBookURL: String?

    public init(source: BookSource, persistentBookURL: String? = nil) {
        self.runtime = BookSourceRuntime(source)
        self.persistentBookURL = persistentBookURL
    }

    public func enablePersistentCache(bookURL: String) {
        persistentBookURL = bookURL
        guard !currentContent.isEmpty,
              currentIndex >= 0, currentIndex < chapters.count else { return }
        let chapterURL = chapters[currentIndex].url
        let text = currentContent
        Task { await ChapterContentCache.shared.save(text, bookURL: bookURL, chapterURL: chapterURL) }
    }

    public var currentChapterTitle: String? {
        guard currentIndex >= 0, currentIndex < chapters.count else { return nil }
        return chapters[currentIndex].name
    }

    public func loadToc(bookUrl: String) async {
        isLoadingToc = true
        errorMessage = nil
        chapters = []
        defer { isLoadingToc = false }
        guard !bookUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "无法打开：书籍地址为空"
            return
        }
        do {
            let loaded = try await runtime.getToc(bookUrl: bookUrl)
            guard !loaded.isEmpty else {
                errorMessage = "目录为空：当前书源未返回章节，请更换书源或测试配置"
                return
            }
            chapters = loaded
        } catch {
            engineLog("获取目录失败: \(error.localizedDescription)", tag: "reader", level: .error)
            errorMessage = "获取目录失败：\(error.localizedDescription)"
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
        guard currentIndex >= 0, currentIndex < chapters.count else {
            isLoadingContent = false
            errorMessage = "无法打开正文：章节参数无效"
            return
        }
        if let cached = contentCache[currentIndex] {
            currentContent = cached
            prefetchNext()
            return
        }
        let chapterURL = chapters[currentIndex].url
        if let bookURL = persistentBookURL,
           let cached = await ChapterContentCache.shared.load(bookURL: bookURL, chapterURL: chapterURL) {
            contentCache[currentIndex] = cached
            currentContent = cached
            prefetchNext()
            return
        }
        isLoadingContent = true
        errorMessage = nil
        defer { isLoadingContent = false }
        do {
            let text = try await runtime.getContent(chapterUrl: chapters[currentIndex].url)
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                errorMessage = "正文为空：当前章节没有返回内容"
                return
            }
            contentCache[currentIndex] = text
            currentContent = text
            if let bookURL = persistentBookURL {
                await ChapterContentCache.shared.save(text, bookURL: bookURL, chapterURL: chapters[currentIndex].url)
            }
            prefetchNext()
        } catch {
            engineLog("获取正文失败: \(error.localizedDescription)", tag: "reader", level: .error)
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
                if let bookURL = persistentBookURL {
                    await ChapterContentCache.shared.save(text, bookURL: bookURL, chapterURL: chapters[next].url)
                }
            }
        }
    }
}

extension ReaderViewModel: Identifiable, Hashable {
    public var id: ObjectIdentifier { ObjectIdentifier(self) }
    public static func == (lhs: ReaderViewModel, rhs: ReaderViewModel) -> Bool { lhs === rhs }
    public func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
}
