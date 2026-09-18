import Foundation

// MARK: - Localization shim (engine side)
//
// The engine reports user-facing check labels through this funnel; the host app
// can swap in its own table. Default: NSLocalizedString against the main bundle.

func localized(_ key: String, bundle: Bundle = .main) -> String {
    NSLocalizedString(key, bundle: bundle, comment: "")
}

// MARK: - Suspicious chapter content detector
//
// Extracted from the app's ChapterFetchManager so the engine (health checker,
// cache revalidation) can reject merged/duplicated chapter caches without
// depending on the reading pipeline.

enum BSChapterContentInspector {
    /// Over this prose character count, a multi-chapter merge is nearly certain.
    private static let suspiciousContentLengthThreshold = 150_000
    /// If the content contains this many "Chapter N / Volume N" headings, treat as merged.
    private static let suspiciousChapterHeadingThreshold = 3
    private static let chapterHeadingRegex = try! NSRegularExpression(
        pattern: #"第\s*[\d零一二三四五六七八九十百千萬万]+\s*[章回卷節节篇部]"#
    )

    static func isSuspiciousChapterContent(_ content: String) -> Bool {
        // Measure prose only: 段評-heavy chapters embed 100s of KB of legitimate
        // base64 SVG bubbles; counting that bulk would trip the merge heuristic
        // into an endless re-fetch loop. Exclude the payloads.
        let proseLength = ReaderHTMLUtilities.lengthExcludingBase64Payloads(content)
        if proseLength > suspiciousContentLengthThreshold {
            AppLogger.parse(
                "⟐ suspiciousContent length",
                context: ["len": content.count, "prose": proseLength]
            )
            return true
        }
        let range = NSRange(content.startIndex..., in: content)
        let headingCount = chapterHeadingRegex.numberOfMatches(in: content, range: range)
        if headingCount >= suspiciousChapterHeadingThreshold {
            AppLogger.parse(
                "⟐ suspiciousContent headings",
                context: ["len": content.count, "headingCount": headingCount]
            )
        }
        return headingCount >= suspiciousChapterHeadingThreshold
    }
}

/// Compatibility shim: engine call sites refer to the manager by its app name.
enum ChapterFetchManager {
    static func isSuspiciousChapterContent(_ content: String) -> Bool {
        BSChapterContentInspector.isSuspiciousChapterContent(content)
    }
}

// MARK: - User-tunable search knobs (engine side)
//
// The app owns the real settings UI; until it exposes one, these read the same
// UserDefaults keys the app would write, with Legado-compatible defaults.

final class GlobalSettings: @unchecked Sendable {
    static let shared = GlobalSettings()

    private let defaults = UserDefaults.standard

    /// In-flight book sources during a search fan-out (Legado threadCount). Default 16.
    var searchConcurrency: Int {
        get { (defaults.object(forKey: "yd_search_concurrency") as? Int) ?? 16 }
        set { defaults.set(newValue, forKey: "yd_search_concurrency") }
    }

    /// Days a search result set may be served from cache. Default 5.
    var searchCacheDays: Int {
        get { (defaults.object(forKey: "yd_search_cache_days") as? Int) ?? 5 }
        set { defaults.set(newValue, forKey: "yd_search_cache_days") }
    }

    /// Auto-pause after this many exact hits in one aggregate search (0 = off).
    var searchAutoPauseCount: Int {
        get { (defaults.object(forKey: "yd_search_auto_pause_count") as? Int) ?? 0 }
        set { defaults.set(newValue, forKey: "yd_search_auto_pause_count") }
    }
}

// MARK: - Direct chapter audio resolver (engine-side port)
//
// Detects audiobook chapters served by text-type sources: a bare media URL or
// <audio> markup with almost no prose left. Keeps replace-rules from eating
// the audio URL (see upstream TTSAudioProvider for the full story).

enum DirectChapterAudioResolver {
    private static let audioExtensions: Set<String> = [
        "aac", "aiff", "aif", "flac", "m4a", "m4b", "mp3", "oga", "ogg", "opus", "wav"
    ]

    static func request(from content: String) -> URLRequest? {
        for candidate in candidates(from: content) {
            guard isAudioCandidate(candidate) else { continue }
            if let url = URL(string: stripLegadoOptions(from: candidate)) {
                return URLRequest(url: url)
            }
        }
        return nil
    }

    static func looksLikeAudioContent(_ content: String) -> Bool {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, request(from: trimmed) != nil else { return false }

        var residual = trimmed
        for candidate in candidates(from: trimmed) where isAudioCandidate(candidate) {
            residual = residual.replacingOccurrences(of: candidate, with: "")
        }
        for pattern in [
            #"(?is)<audio\b[^>]*>.*?</audio>"#,
            #"(?is)<audio\b[^>]*/?>"#,
            #"<[^>]+>"#,
            #"https?://[^\s<>"']+"#,
            #"\{[^}]*\}"#,
        ] {
            residual = residual.replacingOccurrences(
                of: pattern, with: "", options: .regularExpression)
        }
        residual = residual.trimmingCharacters(in: .whitespacesAndNewlines)
        return residual.count <= 16
    }

    private static func candidates(from content: String) -> [String] {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        var values: [String] = [trimmed]
        values.append(contentsOf: urlLikeMatches(in: trimmed))
        values.append(contentsOf: htmlMediaSources(in: trimmed))
        return values
    }

    private static func urlLikeMatches(in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(
            pattern: #"https?://[^\s<>"']+(?:\s*,\s*\{[^ \n\r]*\})?"#,
            options: [.caseInsensitive]
        ) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            Range(match.range, in: text).map { String(text[$0]) }
        }
    }

    private static func htmlMediaSources(in text: String) -> [String] {
        guard text.localizedCaseInsensitiveContains("<audio"),
              let regex = try? NSRegularExpression(
                pattern: #"<audio\b[^>]*\bsrc\s*=\s*["']([^"']+)["']"#,
                options: [.caseInsensitive]
              )
        else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            Range(match.range(at: 1), in: text).map { String(text[$0]) }
        }
    }

    private static func isAudioCandidate(_ candidate: String) -> Bool {
        let rawURL = stripLegadoOptions(from: candidate)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: rawURL),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else { return false }
        let pathExtension = url.pathExtension.lowercased()
        if audioExtensions.contains(pathExtension) { return true }
        let lowered = rawURL.lowercased()
        return lowered.contains("mime=audio")
            || lowered.contains("mime_type=audio")
            || lowered.contains("content-type=audio")
            || lowered.contains("/audio/")
            || lowered.contains("/audiobook/")
            || lowered.contains("/tts/")
    }

    private static func stripLegadoOptions(from candidate: String) -> String {
        if let range = candidate.range(of: #"\s*,\s*\{"#, options: .regularExpression) {
            return String(candidate[..<range.lowerBound])
        }
        return candidate
    }
}
