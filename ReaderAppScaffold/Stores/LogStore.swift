import Foundation

/// 引擎日志：记录搜索/目录/正文的请求与解析过程，方便排查"搜得到但打不开"这类问题
enum LogLevel: String, CaseIterable {
    case info, warn, error
    var symbol: String {
        switch self {
        case .info: return "ℹ️"
        case .warn: return "⚠️"
        case .error: return "❌"
        }
    }
}

struct LogEntry: Identifiable {
    let id = UUID()
    let time: Date
    let level: LogLevel
    let tag: String
    let message: String
}

@MainActor
@Observable
final class LogStore {
    static let shared = LogStore()

    private(set) var entries: [LogEntry] = []
    private let maxCount = 600

    func log(_ message: String, tag: String = "engine", level: LogLevel = .info) {
        entries.append(LogEntry(time: Date(), level: level, tag: tag, message: message))
        if entries.count > maxCount {
            entries.removeFirst(entries.count - maxCount)
        }
    }

    func clear() {
        entries.removeAll()
    }
}

/// 供引擎在任意线程安全地写日志
func engineLog(_ message: String, tag: String = "engine", level: LogLevel = .info) {
    Task { @MainActor in
        LogStore.shared.log(message, tag: tag, level: level)
    }
}
