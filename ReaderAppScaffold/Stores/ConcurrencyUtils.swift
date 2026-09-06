import Foundation

// MARK: - 限制并发数（参考 legado-E mapParallel / onEachParallel）

/// 限制并发数执行异步操作，避免同时启动数百个书源请求导致限流和内存峰值。
/// 用法：
/// ```
/// await withLimitedConcurrency(items: sources, limit: 8) { source in
///     await search(source)
/// }
/// ```
public func withLimitedConcurrency<T: Sendable>(
    items: [T],
    limit: Int,
    operation: @escaping (T) async -> Void
) async {
    let semaphore = AsyncSemaphore(value: max(1, limit))
    await withTaskGroup(of: Void.self) { group in
        for item in items {
            group.addTask {
                await semaphore.wait()
                defer { semaphore.signal() }
                await operation(item)
            }
        }
    }
}

/// 限制并发数执行异步操作并返回结果（保持原始顺序）。
public func withLimitedConcurrency<T: Sendable, R: Sendable>(
    items: [T],
    limit: Int,
    operation: @escaping (T) async -> R
) async -> [R] {
    let semaphore = AsyncSemaphore(value: max(1, limit))
    return await withTaskGroup(of: (Int, R).self) { group in
        for (index, item) in items.enumerated() {
            group.addTask {
                await semaphore.wait()
                defer { semaphore.signal() }
                let result = await operation(item)
                return (index, result)
            }
        }
        var results: [R?] = Array(repeating: nil, count: items.count)
        for await (index, result) in group {
            results[index] = result
        }
        return results.compactMap { $0 }
    }
}

// MARK: - 异步信号量

public final class AsyncSemaphore: @unchecked Sendable {
    private var value: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private let lock = NSLock()

    public init(value: Int) {
        self.value = value
    }

    public func wait() async {
        lock.lock()
        value -= 1
        if value >= 0 {
            lock.unlock()
            return
        }
        lock.unlock()
        await withCheckedContinuation { continuation in
            lock.lock()
            waiters.append(continuation)
            lock.unlock()
        }
    }

    public func signal() {
        lock.lock()
        value += 1
        if !waiters.isEmpty {
            let waiter = waiters.removeFirst()
            lock.unlock()
            waiter.resume()
        } else {
            lock.unlock()
        }
    }
}

// MARK: - 超时控制（参考 legado-E withTimeout）

public enum TimeoutError: Error, LocalizedError {
    case timedOut(seconds: TimeInterval)

    public var errorDescription: String? {
        switch self {
        case .timedOut(let seconds):
            return "请求超时（\(Int(seconds))秒）"
        }
    }
}

/// 为异步操作添加超时，超时后自动取消任务。
public func withTimeout<T: Sendable>(
    _ seconds: TimeInterval,
    operation: @escaping () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw TimeoutError.timedOut(seconds: seconds)
        }
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}

// MARK: - 暂停/恢复控制器（参考 legado-E MutableStateFlow workingState）

public final class PauseController: @unchecked Sendable {
    private var isPaused = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private let lock = NSLock()

    public init() {}

    /// 暂停：后续调用 waitIfPaused() 的任务会阻塞
    public func pause() {
        lock.lock()
        isPaused = true
        lock.unlock()
    }

    /// 恢复：唤醒所有等待的任务
    public func resume() {
        lock.lock()
        isPaused = false
        let currentWaiters = waiters
        waiters.removeAll()
        lock.unlock()
        currentWaiters.forEach { $0.resume() }
    }

    /// 如果已暂停，等待恢复；否则立即返回
    public func waitIfPaused() async {
        lock.lock()
        if !isPaused {
            lock.unlock()
            return
        }
        lock.unlock()
        await withCheckedContinuation { continuation in
            lock.lock()
            if isPaused {
                waiters.append(continuation)
                lock.unlock()
            } else {
                lock.unlock()
                continuation.resume()
            }
        }
    }

    public var paused: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isPaused
    }
}

// MARK: - 进度上报

public struct ProgressInfo: Sendable {
    public let current: Int
    public let total: Int
    public let label: String

    public init(current: Int, total: Int, label: String = "") {
        self.current = current
        self.total = total
        self.label = label
    }

    public var fraction: Double {
        guard total > 0 else { return 0 }
        return Double(current) / Double(total)
    }
}

// MARK: - 线程安全的集合（参考 legado-E ConcurrentHashMap / SynchronizedList）

public final class ThreadSafeSet<Element: Hashable>: @unchecked Sendable {
    private var set = Set<Element>()
    private let lock = NSLock()

    public init() {}

    @discardableResult
    public func insert(_ element: Element) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return set.insert(element).inserted
    }

    @discardableResult
    public func remove(_ element: Element) -> Element? {
        lock.lock()
        defer { lock.unlock() }
        return set.remove(element)
    }

    public func contains(_ element: Element) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return set.contains(element)
    }

    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return set.count
    }

    public var isEmpty: Bool {
        lock.lock()
        defer { lock.unlock() }
        return set.isEmpty
    }

    public func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        set.removeAll()
    }

    public func forEach(_ body: (Element) -> Void) {
        lock.lock()
        let snapshot = Array(set)
        lock.unlock()
        snapshot.forEach(body)
    }
}

public final class ThreadSafeArray<Element>: @unchecked Sendable {
    private var array: [Element] = []
    private let lock = NSLock()

    public init() {}

    public func append(_ element: Element) {
        lock.lock()
        defer { lock.unlock() }
        array.append(element)
    }

    public func append(contentsOf elements: [Element]) {
        lock.lock()
        defer { lock.unlock() }
        array.append(contentsOf: elements)
    }

    @discardableResult
    public func remove(at index: Int) -> Element {
        lock.lock()
        defer { lock.unlock() }
        return array.remove(at: index)
    }

    public func removeAll(where shouldBeRemoved: (Element) -> Bool) {
        lock.lock()
        defer { lock.unlock() }
        array.removeAll(where: shouldBeRemoved)
    }

    public func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        array.removeAll()
    }

    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return array.count
    }

    public var isEmpty: Bool {
        lock.lock()
        defer { lock.unlock() }
        return array.isEmpty
    }

    public var first: Element? {
        lock.lock()
        defer { lock.unlock() }
        return array.first
    }

    public func snapshot() -> [Element] {
        lock.lock()
        defer { lock.unlock() }
        return array
    }

    public func forEach(_ body: (Element) -> Void) {
        lock.lock()
        let snapshot = array
        lock.unlock()
        snapshot.forEach(body)
    }
}
