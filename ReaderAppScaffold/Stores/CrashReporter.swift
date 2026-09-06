import Foundation
import MetricKit
import Observation
import Darwin

struct CrashLogEntry: Codable, Identifiable, Sendable {
    let id: UUID
    let timestamp: Date
    let kind: String
    let title: String
    let details: String
    let appVersion: String
    let osVersion: String
}

private var crashSignalMarkerPath: UnsafeMutablePointer<CChar>?

private func crashSignalHandler(_ signalNumber: Int32) {
    guard let path = crashSignalMarkerPath else { _exit(128 + signalNumber) }
    let descriptor = Darwin.open(path, O_WRONLY | O_CREAT | O_TRUNC, S_IRUSR | S_IWUSR)
    if descriptor >= 0 {
        let message: StaticString
        switch signalNumber {
        case SIGABRT: message = "SIGABRT"
        case SIGILL: message = "SIGILL"
        case SIGSEGV: message = "SIGSEGV"
        case SIGFPE: message = "SIGFPE"
        case SIGBUS: message = "SIGBUS"
        case SIGTRAP: message = "SIGTRAP"
        default: message = "UNKNOWN_SIGNAL"
        }
        _ = Darwin.write(descriptor, message.utf8Start, message.utf8CodeUnitCount)
        _ = Darwin.fsync(descriptor)
        _ = Darwin.close(descriptor)
    }
    Darwin.signal(signalNumber, SIG_DFL)
    Darwin.raise(signalNumber)
    _exit(128 + signalNumber)
}

private func crashExceptionHandler(_ exception: NSException) {
    CrashReporter.shared.writeExceptionMarker(exception)
}

final class CrashReporter: NSObject, MXMetricManagerSubscriber {
    static let shared = CrashReporter()

    private let directoryURL: URL
    private let sessionMarkerURL: URL
    private let signalMarkerURL: URL
    private let exceptionMarkerURL: URL
    private let breadcrumbURL: URL
    private let lock = NSLock()
    private let breadcrumbQueue = DispatchQueue(label: "legado.crash.breadcrumbs", qos: .utility)
    private var started = false

    private override init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = base.appendingPathComponent("CrashLogs", isDirectory: true)
        directoryURL = directory
        sessionMarkerURL = directory.appendingPathComponent("session-active.flag")
        signalMarkerURL = directory.appendingPathComponent("signal.marker")
        exceptionMarkerURL = directory.appendingPathComponent("exception.marker")
        breadcrumbURL = directory.appendingPathComponent("breadcrumbs.log")
        super.init()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func start() {
        lock.lock()
        guard !started else { lock.unlock(); return }
        started = true
        lock.unlock()

        processPreviousTermination()
        crashSignalMarkerPath = strdup(signalMarkerURL.path)
        NSSetUncaughtExceptionHandler(crashExceptionHandler)
        [SIGABRT, SIGILL, SIGSEGV, SIGFPE, SIGBUS, SIGTRAP].forEach {
            Darwin.signal($0, crashSignalHandler)
        }
        MXMetricManager.shared.add(self)
    }

    func markSessionActive(_ active: Bool) {
        if active {
            try? Data("active".utf8).write(to: sessionMarkerURL, options: .atomic)
        } else {
            try? FileManager.default.removeItem(at: sessionMarkerURL)
        }
    }

    func breadcrumb(level: String, tag: String, message: String) {
        let line = "[\(ISO8601DateFormatter().string(from: Date()))] [\(level)] [\(tag)] \(redact(message))\n"
        breadcrumbQueue.async { [breadcrumbURL] in
            let data = Data(line.utf8)
            if !FileManager.default.fileExists(atPath: breadcrumbURL.path) {
                try? data.write(to: breadcrumbURL, options: .atomic)
                return
            }
            guard let handle = try? FileHandle(forWritingTo: breadcrumbURL) else { return }
            do {
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.close()
                let size = (try? breadcrumbURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                if size > 96_000, let all = try? Data(contentsOf: breadcrumbURL) {
                    try? Data(all.suffix(64_000)).write(to: breadcrumbURL, options: .atomic)
                }
            } catch {
                try? handle.close()
            }
        }
    }

    func writeExceptionMarker(_ exception: NSException) {
        let text = """
        Objective-C exception: \(exception.name.rawValue)
        Reason: \(exception.reason ?? "unknown")
        Stack:\n\(exception.callStackSymbols.joined(separator: "\n"))
        """
        try? Data(redact(text).utf8).write(to: exceptionMarkerURL, options: .atomic)
    }

    func didReceive(_ payloads: [MXMetricPayload]) {
        // 性能指标不是崩溃日志，不单独落盘；实现此方法保证完整订阅兼容。
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            let data = payload.jsonRepresentation()
            let details = String(data: data, encoding: .utf8) ?? "无法读取 MetricKit 诊断内容"
            record(kind: "MetricKit", title: "系统崩溃与性能诊断", details: details)
        }
    }

    func loadEntries() -> [CrashLogEntry] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return urls
            .filter { $0.pathExtension == "json" }
            .compactMap { try? decoder.decode(CrashLogEntry.self, from: Data(contentsOf: $0)) }
            .sorted { $0.timestamp > $1.timestamp }
    }

    func clearEntries() {
        let files = (try? FileManager.default.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.pathExtension == "json" {
            try? FileManager.default.removeItem(at: file)
        }
        Task { @MainActor in CrashLogStore.shared.reload() }
    }

    func reportText() -> String {
        loadEntries().map {
            "[\(ISO8601DateFormatter().string(from: $0.timestamp))] \($0.kind) · \($0.title)\n\($0.details)"
        }.joined(separator: "\n\n====================\n\n")
    }

    private func processPreviousTermination() {
        let active = FileManager.default.fileExists(atPath: sessionMarkerURL.path)
        let signal = try? String(contentsOf: signalMarkerURL, encoding: .utf8)
        let exception = try? String(contentsOf: exceptionMarkerURL, encoding: .utf8)
        let breadcrumbs = try? String(contentsOf: breadcrumbURL, encoding: .utf8)

        if active || signal != nil || exception != nil {
            var parts: [String] = []
            if let signal { parts.append("Signal: \(signal)") }
            if let exception { parts.append(exception) }
            if active && signal == nil && exception == nil {
                parts.append("上次应用在前台会话中异常结束；可能是系统终止、内存压力、强制结束或原生崩溃。")
            }
            if let breadcrumbs, !breadcrumbs.isEmpty {
                parts.append("最近运行步骤:\n\(breadcrumbs)")
            }
            record(kind: signal ?? "异常终止", title: "检测到上次会话异常结束", details: parts.joined(separator: "\n\n"))
        }

        try? FileManager.default.removeItem(at: sessionMarkerURL)
        try? FileManager.default.removeItem(at: signalMarkerURL)
        try? FileManager.default.removeItem(at: exceptionMarkerURL)
        try? FileManager.default.removeItem(at: breadcrumbURL)
    }

    private func record(kind: String, title: String, details: String) {
        let entry = CrashLogEntry(
            id: UUID(),
            timestamp: Date(),
            kind: kind,
            title: title,
            details: redact(details),
            appVersion: "\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"))",
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(entry) {
            let file = directoryURL.appendingPathComponent("\(entry.timestamp.timeIntervalSince1970)-\(entry.id.uuidString).json")
            try? data.write(to: file, options: .atomic)
        }
        prune()
        Task { @MainActor in CrashLogStore.shared.reload() }
    }

    private func prune() {
        let entries = loadEntries()
        guard entries.count > 60 else { return }
        let keep = Set(entries.prefix(60).map(\.id))
        let files = (try? FileManager.default.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil)) ?? []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let entry = try? decoder.decode(CrashLogEntry.self, from: data),
                  !keep.contains(entry.id) else { continue }
            try? FileManager.default.removeItem(at: file)
        }
    }

    private func redact(_ input: String) -> String {
        let pattern = #"(?i)(password|token|api[_-]?key|cookie|authorization)(\s*[:=]\s*)[^&\s\"']+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return input }
        let range = NSRange(input.startIndex..., in: input)
        return regex.stringByReplacingMatches(in: input, range: range, withTemplate: "$1$2<redacted>")
    }
}

@MainActor
@Observable
final class CrashLogStore {
    static let shared = CrashLogStore()
    private(set) var entries: [CrashLogEntry] = []

    private init() { reload() }

    func reload() {
        entries = CrashReporter.shared.loadEntries()
    }

    func clear() {
        CrashReporter.shared.clearEntries()
    }
}
