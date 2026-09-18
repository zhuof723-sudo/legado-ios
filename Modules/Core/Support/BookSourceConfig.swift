import Foundation

// MARK: - Application Configuration Constants (engine side)
//
// Centralizes the hardcoded constants the book-source engine reads.
// Tune values here — no engine file needs to change.

enum AppConfig {
    // MARK: - Chapter Fetching

    /// Hard timeout for one chapter fetch (network + pagination + parse).
    static let chapterFetchTimeoutSeconds: UInt64 = 35

    /// How long a cached TOC / book-info package may be served without going
    /// back to the source. Reasonable range: hours to a day.
    static let tocCacheTTL: TimeInterval = 6 * 60 * 60

    /// Number of cumulative failures before a book source is quarantined.
    static let chapterFetchQuarantineThreshold: Int = 5

    // MARK: - Rule JS

    /// Wall-clock limit for one `@js:` / `<js>` evaluation inside JavaScriptCore.
    static let jsRuleEngineExecutionTimeout: TimeInterval = 8

    // MARK: - WebView Rendering

    /// Default timeout for WebView-based page rendering.
    static let webViewFetchTimeout: TimeInterval = 15

    /// Delay after `didFinish` for a plain WebView response (Legado BackstageWebView
    /// waits ~900ms + 100ms dispatch).
    static let webViewJSRenderWait: TimeInterval = 1.0

    /// Delay before executing an explicit source `webJs`.
    static let webViewExplicitJSWait: TimeInterval = 0.1

    /// Fixed WebView pool size.
    static let webViewPoolSize: Int = 3

    /// Maximum additional temporary WebViews when the pool is saturated.
    static let webViewPoolOverflowMultiplier: Int = 2

    /// Timeout for the whole WebView HTML load.
    static let webViewHTMLLoadTimeout: UInt64 = 10

    /// Polling interval while waiting for a WebView document to stabilize.
    static let webViewPollingIntervalMs: Int = 100

    /// Upper bound for polling wait.
    static let webViewPollingMaxWaitMs: Int = 1_500

    /// Minimum text length considered "rendered".
    static let webViewPollingMinTextLength: Int = 300

    // MARK: - URL Safety (SSRF prevention)

    /// Whitelisted URL schemes for book-source requests. Everything else
    /// (file://, javascript:, data:, ...) is rejected in `safeURL`.
    static let allowedURLSchemes: Set<String> = ["http", "https"]
}
