import Foundation
import os.log

// MARK: - Structured Logging (engine side)
//
// Simplified port of the app's AppLogger: all engine call sites funnel through
// these category functions. Output goes to os.log (Console.app / Xcode console).

enum DiagnosticSeverity {
    case notice
    case info
    case warning
    case error
    case critical
}

enum AppLogger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.legado.engine"

    private static let networkLog = Logger(subsystem: subsystem, category: "network")
    private static let parseLog = Logger(subsystem: subsystem, category: "parse")
    private static let cacheLog = Logger(subsystem: subsystem, category: "cache")
    private static let securityLog = Logger(subsystem: subsystem, category: "security")
    private static let generalLog = Logger(subsystem: subsystem, category: "general")

    /// Engine call sites may pass a severity hint; this simplified port maps it
    /// onto os.log levels but does not keep the app's on-disk diagnostic log.
    typealias Level = DiagnosticSeverity

    private static func format(_ message: String, error: Error?, context: [String: Any]) -> String {
        var out = message
        if let error { out += " | error=\(error.localizedDescription)" }
        if !context.isEmpty {
            let pairs = context.keys.sorted().compactMap { key -> String? in
                guard let value = context[key] else { return nil }
                return "\(key)=\(value)"
            }
            out += " | " + pairs.joined(separator: ", ")
        }
        return out
    }

    private static func severityHint(_ level: DiagnosticSeverity?) -> OSLogType {
        switch level {
        case .critical: return .fault
        case .error: return .error
        case .warning: return .default
        case .info: return .info
        default: return .default
        }
    }

    static func network(_ message: String, error: Error? = nil, context: [String: Any] = [:], level: DiagnosticSeverity? = nil) {
        networkLog.log(level: severityHint(level), "\(Self.format(message, error: error, context: context), privacy: .public)")
    }

    static func parse(_ message: String, error: Error? = nil, context: [String: Any] = [:], level: DiagnosticSeverity? = nil) {
        parseLog.log(level: severityHint(level), "\(Self.format(message, error: error, context: context), privacy: .public)")
    }

    static func cache(_ message: String, error: Error? = nil, context: [String: Any] = [:], level: DiagnosticSeverity? = nil) {
        cacheLog.log(level: severityHint(level), "\(Self.format(message, error: error, context: context), privacy: .public)")
    }

    static func security(_ message: String, context: [String: Any] = [:], level: DiagnosticSeverity? = nil) {
        securityLog.log(level: severityHint(level), "\(Self.format(message, error: nil, context: context), privacy: .public)")
    }

    static func error(_ message: String, error: Error? = nil, context: [String: Any] = [:], level: DiagnosticSeverity? = nil) {
        generalLog.log(level: severityHint(level), "\(Self.format(message, error: error, context: context), privacy: .public)")
    }

    static func info(_ message: String, context: [String: Any] = [:], level: DiagnosticSeverity? = nil) {
        generalLog.log(level: severityHint(level), "\(Self.format(message, error: nil, context: context), privacy: .public)")
    }
}

// MARK: - Lightweight telemetry sink (engine side)
//
// NOTE: `WebCrawlerDebugger` is defined by the engine itself
// (BookSourceFetcher.swift) — do not redeclare it here.

final class ReaderTelemetry: @unchecked Sendable {
    static let shared = ReaderTelemetry()

    /// Optional host hook (e.g. signpost / analytics). Engine never depends on it.
    var handler: ((String, [String: Any]) -> Void)?

    func log(_ event: String, attributes: [String: Any] = [:]) {
        handler?(event, attributes)
    }
}
