import Foundation

/// 引擎日志级别
public enum EngineLogLevel: String {
    case info, warn, error
}

/// 引擎日志出口：由宿主 App 注入 sink，把引擎日志接到自己的日志系统
public enum EngineLogger {
    public static var sink: ((_ level: EngineLogLevel, _ tag: String, _ message: String) -> Void)?

    public static func log(_ message: String, tag: String = "engine", level: EngineLogLevel = .info) {
        sink?(level, tag, message)
    }
}
