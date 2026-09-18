import Foundation
import LegadoRuleEngine

// MARK: - 章节下载管理器（参考 legado-E CacheBook）

/// 全局章节下载管理器，负责管理所有书籍的章节下载/缓存。
/// 参考 legado-E 的 object CacheBook 设计：
/// - 全局单例
/// - 每本书独立的下载队列
/// - 并发控制（限制同时下载的章节数）
/// - 失败重试（3次）
/// - 暂停/恢复
/// - 进度上报
public final class ChapterDownloadManager: @unchecked Sendable {
    public static let shared = ChapterDownloadManager()

    /// 每本书的下载模型映射（参考 legado-E cacheBookMap）
    private var bookMap: [String: BookDownloadModel] = [:]
    private let lock = NSLock()

    /// 并发下载的章节数量（参考 legado-E AppConfig.threadCount）
    public var concurrentLimit: Int = 4

    /// 单个章节下载超时（秒）
    public var downloadTimeout: TimeInterval = 30

    /// 失败重试次数（参考 legado-E 重试3次）
    public var maxRetryCount: Int = 3

    /// 暂停控制器（参考 legado-E workingState）
    private let pauseController = PauseController()

    /// 下载进度回调
    public var onProgress: ((ProgressInfo) -> Void)?

    /// 是否正在下载
    public var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return bookMap.contains { $0.value.isRunning }
    }

    private init() {}

    // MARK: - 公共接口

    /// 添加下载任务（参考 legado-E CacheBookModel.addDownload）
    public func addDownload(
        bookURL: String,
        book: BookSource,
        chapters: [ChapterInfo],
        startIndex: Int,
        endIndex: Int
    ) {
        lock.lock()
        let model = bookMap[bookURL] ?? BookDownloadModel(bookURL: bookURL, book: book)
        model.addDownload(chapters: chapters, start: startIndex, end: endIndex)
        bookMap[bookURL] = model
        lock.unlock()

        // 启动下载进程
        Task { await startProcessIfNeeded() }
    }

    /// 下载单个章节（阅读时即时加载），保留段评图元数据。
    public func downloadChapterContent(
        bookURL: String,
        book: BookSource,
        chapter: ChapterInfo
    ) async throws -> ReaderChapterContent {
        let runtime = BookSourceRuntime(book)
        if let cached = await ChapterContentCache.shared.loadDocument(bookURL: bookURL, chapterURL: chapter.url),
           cached.formatVersion >= ReaderChapterContent.currentFormatVersion,
           cached.inlineReviewProcessed {
            return cached
        }
        let document = try await withTimeout(downloadTimeout) {
            try await runtime.getChapterContent(chapterUrl: chapter.url)
        }
        if !document.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            await ChapterContentCache.shared.saveDocument(document, bookURL: bookURL, chapterURL: chapter.url)
        }
        return document
    }

    /// 兼容旧调用方。
    public func downloadChapter(
        bookURL: String,
        book: BookSource,
        chapter: ChapterInfo
    ) async throws -> String {
        (try await downloadChapterContent(bookURL: bookURL, book: book, chapter: chapter)).text
    }

    /// 暂停所有下载（参考 legado-E CacheBook.setWorkingState(false)）
    public func pause() {
        pauseController.pause()
    }

    /// 恢复所有下载
    public func resume() {
        pauseController.resume()
    }

    /// 停止某本书的下载
    public func stop(bookURL: String) {
        lock.lock()
        bookMap[bookURL]?.stop()
        bookMap.removeValue(forKey: bookURL)
        lock.unlock()
    }

    /// 停止所有下载
    public func stopAll() {
        lock.lock()
        bookMap.forEach { $0.value.stop() }
        bookMap.removeAll()
        lock.unlock()
        pauseController.resume()
    }

    /// 获取某本书的下载进度
    public func progress(for bookURL: String) -> ProgressInfo? {
        lock.lock()
        defer { lock.unlock() }
        return bookMap[bookURL]?.progress
    }

    // MARK: - 内部实现

    /// 启动下载进程（参考 legado-E CacheBook.startProcessJob）
    private func startProcessIfNeeded() async {
        let semaphore = AsyncSemaphore(value: concurrentLimit)

        while true {
            // 检查暂停
            await pauseController.waitIfPaused()

            // 获取下一个待下载的章节
            guard let next = nextDownloadItem() else { break }

            await semaphore.wait()

            Task {
                defer { semaphore.signal() }
                await self.downloadItem(next)
            }
        }
    }

    /// 获取下一个待下载的章节（参考 legado-E CacheBookModel.download）
    private func nextDownloadItem() -> DownloadItem? {
        lock.lock()
        defer { lock.unlock() }

        for (_, model) in bookMap where model.isRunning {
            if let item = model.nextDownload() {
                return item
            }
        }
        return nil
    }

    /// 下载单个章节
    private func downloadItem(_ item: DownloadItem) async {
        do {
            let text = try await downloadChapter(
                bookURL: item.bookURL,
                book: item.book,
                chapter: item.chapter
            )
            // 下载成功
            lock.lock()
            bookMap[item.bookURL]?.onSuccess(chapterIndex: item.chapterIndex)
            lock.unlock()
        } catch {
            // 下载失败，重试
            lock.lock()
            let shouldRetry = bookMap[item.bookURL]?.onError(
                chapterIndex: item.chapterIndex,
                error: error,
                maxRetry: maxRetryCount
            ) ?? false
            lock.unlock()

            if shouldRetry {
                // 延迟1秒后重试（参考 legado-E delay(1000)）
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }

        // 上报进度
        reportProgress()
    }

    private func reportProgress() {
        lock.lock()
        var totalWait = 0
        var totalOn = 0
        var totalDone = 0
        for (_, model) in bookMap {
            totalWait += model.waitCount
            totalOn += model.onDownloadCount
            totalDone += model.successCount
        }
        lock.unlock()

        let total = totalWait + totalOn + totalDone
        let info = ProgressInfo(
            current: totalDone + totalOn,
            total: total,
            label: "正在下载: \(totalOn) | 等待中: \(totalWait) | 已完成: \(totalDone)"
        )
        onProgress?(info)
    }
}

// MARK: - 下载项

private struct DownloadItem {
    let bookURL: String
    let book: BookSource
    let chapter: ChapterInfo
    let chapterIndex: Int
}

// MARK: - 每本书的下载模型（参考 legado-E CacheBook.CacheBookModel）

private final class BookDownloadModel {
    let bookURL: String
    let book: BookSource

    /// 等待下载的章节索引（参考 legado-E waitDownloadSet）
    private var waitSet: Set<Int> = []
    /// 正在下载的章节索引（参考 legado-E onDownloadSet）
    private var onDownloadSet: Set<Int> = []
    /// 已成功下载的章节索引
    private var successSet: Set<Int> = []
    /// 失败重试计数（参考 legado-E errorDownloadMap）
    private var retryCount: [Int: Int] = [:]
    /// 章节信息
    private var chapters: [Int: ChapterInfo] = [:]
    /// 是否已停止
    private var isStopped = false

    var waitCount: Int { waitSet.count }
    var onDownloadCount: Int { onDownloadSet.count }
    var successCount: Int { successSet.count }

    var isRunning: Bool {
        !isStopped && (!waitSet.isEmpty || !onDownloadSet.isEmpty)
    }

    var progress: ProgressInfo {
        let total = waitSet.count + onDownloadSet.count + successSet.count
        return ProgressInfo(
            current: successSet.count + onDownloadSet.count,
            total: total
        )
    }

    init(bookURL: String, book: BookSource) {
        self.bookURL = bookURL
        self.book = book
    }

    /// 添加下载任务（参考 legado-E CacheBookModel.addDownload）
    func addDownload(chapters: [ChapterInfo], start: Int, end: Int) {
        isStopped = false
        for i in start...end where i < chapters.count {
            if !onDownloadSet.contains(i) && !successSet.contains(i) {
                waitSet.insert(i)
                self.chapters[i] = chapters[i]
            }
        }
    }

    /// 获取下一个待下载的章节（参考 legado-E CacheBookModel.download）
    func nextDownload() -> DownloadItem? {
        guard let index = waitSet.min() else { return nil }
        guard let chapter = chapters[index] else {
            waitSet.remove(index)
            return nil
        }
        waitSet.remove(index)
        onDownloadSet.insert(index)
        return DownloadItem(
            bookURL: bookURL,
            book: book,
            chapter: chapter,
            chapterIndex: index
        )
    }

    /// 下载成功（参考 legado-E CacheBookModel.onSuccess）
    func onSuccess(chapterIndex: Int) {
        onDownloadSet.remove(chapterIndex)
        successSet.insert(chapterIndex)
        retryCount.removeValue(forKey: chapterIndex)
    }

    /// 下载失败（参考 legado-E CacheBookModel.onError）
    /// 返回是否需要重试
    @discardableResult
    func onError(chapterIndex: Int, error: Error, maxRetry: Int) -> Bool {
        onDownloadSet.remove(chapterIndex)
        let count = (retryCount[chapterIndex] ?? 0) + 1
        retryCount[chapterIndex] = count

        if count < maxRetry && !isStopped {
            waitSet.insert(chapterIndex)
            return true
        }
        return false
    }

    /// 停止下载（参考 legado-E CacheBookModel.stop）
    func stop() {
        waitSet.removeAll()
        onDownloadSet.removeAll()
        isStopped = true
    }
}
