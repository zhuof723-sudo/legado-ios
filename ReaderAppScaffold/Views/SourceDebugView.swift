import SwiftUI
import UIKit
import Foundation
import LegadoRuleEngine

struct SourceDebugView: View {
    let record: BookSourceRecord
    @Environment(\.dismiss) private var dismiss

    @State private var keyword = ""
    @State private var running = false
    @State private var didAutoRun = false
    @State private var stages = StageKind.allCases.map { StageResult(kind: $0) }
    @State private var books: [DebugBook] = []
    @State private var chapters: [ChapterInfo] = []
    @State private var contentText = ""
    @State private var bookInfo: BookInfo?
    @State private var timeline: [TimelineEntry] = []
    @State private var activeSheet: DebugSheet?
    @State private var notice: String?

    private enum StageKind: String, CaseIterable, Identifiable, Equatable {
        case search = "搜索"
        case detail = "书籍详情"
        case toc = "目录列表"
        case content = "正文内容"

        var id: String { rawValue }
        var icon: String {
            switch self {
            case .search: return "magnifyingglass"
            case .detail: return "book.closed"
            case .toc: return "list.bullet.rectangle"
            case .content: return "doc.text"
            }
        }
        var color: Color {
            switch self {
            case .search: return .blue
            case .detail: return .indigo
            case .toc: return .orange
            case .content: return .green
            }
        }
    }

    private enum StageStatus: Equatable {
        case pending, running, passed, failed, skipped

        var title: String {
            switch self {
            case .pending: return "待测试"
            case .running: return "测试中"
            case .passed: return "通过"
            case .failed: return "失败"
            case .skipped: return "跳过"
            }
        }
        var color: Color {
            switch self {
            case .passed: return .green
            case .failed: return .red
            case .running: return .blue
            default: return .secondary
            }
        }
        var icon: String {
            switch self {
            case .passed: return "checkmark.circle.fill"
            case .failed: return "xmark.circle.fill"
            case .running: return "bolt.circle.fill"
            case .skipped: return "minus.circle.fill"
            case .pending: return "circle"
            }
        }
    }

    private struct StageResult: Identifiable {
        let kind: StageKind
        var status: StageStatus = .pending
        var detail = "尚未执行"
        var duration: TimeInterval = 0
        var id: String { kind.id }
    }

    private struct DebugBook: Identifiable {
        let id: String
        let name: String
        let author: String
        let kind: String
        let bookURL: String
        let sourceName: String
    }

    private struct TimelineEntry: Identifiable {
        let id = UUID()
        let elapsed: TimeInterval
        let text: String
        let level: LogLevel
    }

    private enum DebugSheet: Identifiable {
        case source(String, String)
        case chapters
        case logs
        case timeline
        case jsConsole

        var id: String {
            switch self {
            case .source(let title, _): return "source-\(title)"
            case .chapters: return "chapters"
            case .logs: return "logs"
            case .timeline: return "timeline"
            case .jsConsole: return "js"
            }
        }
    }

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                ScrollView {
                    LazyVStack(spacing: 18) {
                        startCard
                        resultCard
                        if !books.isEmpty { searchResultsCard }
                        if !chapters.isEmpty { chapterCard }
                        if !contentText.isEmpty { contentCard }
                        if !timeline.isEmpty { debugLogCard }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .padding(.bottom, 28)
                }
                .scrollDismissesKeyboard(.interactively)
            }

            if let notice {
                Text(notice)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.78), in: Capsule())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 90)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: notice)
        .task {
            guard !didAutoRun else { return }
            didAutoRun = true
            if let source = record.decodeSource(), keyword.isEmpty {
                keyword = suggestedKeyword(source)
            }
            await run()
        }
        .sheet(item: $activeSheet) { sheet in
            sheetView(sheet)
        }
    }

    private var topBar: some View {
        HStack {
            Button("关闭") { dismiss() }
                .font(.headline)
                .foregroundStyle(.primary)
                .padding(.horizontal, 18)
                .frame(height: 52)
                .background(.thinMaterial, in: Capsule())

            Spacer()
            Text("配置测试")
                .font(.title3.bold())
            Spacer()

            debugMenu
                .frame(width: 58, height: 52)
                .background(.thinMaterial, in: Capsule())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var debugMenu: some View {
        Menu {
            sourceMenuButton("搜索页源码", icon: "doc.text.magnifyingglass", kind: .search)
            sourceMenuButton("发现页源码", icon: "safari", kind: .explore)
                .disabled(record.decodeSource()?.exploreUrl?.isEmpty != false)
            sourceMenuButton("详情页源码", icon: "doc", kind: .detail)
            sourceMenuButton("目录页源码", icon: "list.bullet.rectangle", kind: .toc)
            sourceMenuButton("正文页源码", icon: "doc.text", kind: .content)
            Divider()
            Button("JS控制台 (\(jsEntries.count))", systemImage: "terminal") {
                activeSheet = .jsConsole
            }
            .disabled(jsEntries.isEmpty)
            Button("系统日志 (\(LogStore.shared.entries.count))", systemImage: "waveform.path.ecg.rectangle") {
                activeSheet = .logs
            }
            Button("诊断时间线 (\(timeline.count))", systemImage: "chart.bar.xaxis") {
                activeSheet = .timeline
            }
            Divider()
            Button("复制测试报告", systemImage: "doc.on.doc") { copyReport() }
            Button("重置测试", systemImage: "arrow.counterclockwise") {
                Task { await run() }
            }
            Button("清除配置变量", systemImage: "xmark.app", role: .destructive) {
                clearVariables()
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title2)
                .foregroundStyle(.primary)
        }
    }

    private enum SourceCodeKind { case search, explore, detail, toc, content }

    private func sourceMenuButton(_ title: String, icon: String, kind: SourceCodeKind) -> some View {
        Button {
            let source = sourceCode(kind)
            activeSheet = .source(title, source)
        } label: {
            Label(title, systemImage: icon)
        }
    }

    private var startCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("开始测试").font(.title3.bold())
                    Text(record.bookSourceName).font(.subheadline).foregroundStyle(.secondary)
                }
            }

            Text("本地解析 · \(sourceTypeName)")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(record.bookSourceUrl)
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack(spacing: 10) {
                TextField("搜索关键词 / URL", text: $keyword)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 14)
                    .frame(height: 50)
                    .background(Color.white.opacity(0.45), in: RoundedRectangle(cornerRadius: 14))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onSubmit { Task { await run() } }
                Button("开始") { Task { await run() } }
                    .font(.headline)
                    .foregroundStyle(.blue)
                    .frame(width: 88, height: 50)
                    .background(Color.blue.opacity(0.14), in: RoundedRectangle(cornerRadius: 14))
                    .disabled(running)
            }

            Text("当前模式: \(modeDescription)")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .debugCard()
    }

    private var resultCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: failedCount == 0 && passedCount > 0 ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundStyle(failedCount == 0 && passedCount > 0 ? .green : .orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("测试结果").font(.title3.bold())
                    Text("通过 \(passedCount) · 失败 \(failedCount) · 耗时 \(formatDuration(totalDuration))")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }

            Divider().opacity(0.5)
            ForEach(Array(stages.enumerated()), id: \.element.id) { index, stage in
                stageRow(stage)
                if index < stages.count - 1 { Divider().opacity(0.35) }
            }
        }
        .debugCard()
    }

    private func stageRow(_ stage: StageResult) -> some View {
        HStack(spacing: 12) {
            Image(systemName: stage.status.icon)
                .font(.title3)
                .foregroundStyle(stage.status.color)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(stage.kind.rawValue).font(.headline)
                Text(stage.detail).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
            if stage.status == .running {
                ProgressView().controlSize(.small)
            } else {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(stage.status.title).foregroundStyle(stage.status.color)
                    if stage.duration > 0 {
                        Text(formatDuration(stage.duration)).foregroundStyle(.secondary)
                    }
                }
                .font(.footnote)
            }
        }
        .padding(.vertical, 8)
    }

    private var searchResultsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("搜索结果", icon: "magnifyingglass.circle.fill", color: .blue,
                          subtitle: "共 \(books.count) 本，点击条目继续详情链路")
            ForEach(Array(books.prefix(5).enumerated()), id: \.element.id) { index, book in
                Button {
                    Task { await runBookChain(book) }
                } label: {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(book.name).font(.headline).foregroundStyle(.primary).lineLimit(1)
                            Text([book.author, book.kind].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                            Text(book.bookURL)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.blue)
                    }
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .disabled(running)
                if index < min(books.count, 5) - 1 { Divider().opacity(0.35) }
            }
            if books.count > 5 {
                Text("还有 \(books.count - 5) 本未展开")
                    .font(.footnote).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
            }
        }
        .debugCard()
    }

    private var chapterCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("章节列表", icon: "list.bullet.rectangle.fill", color: .orange,
                          subtitle: "共 \(chapters.count) 章，可继续下钻正文")
            if let first = chapters.first {
                valueRow("第一章", first.name)
            }
            if let last = chapters.last {
                valueRow("最新章", last.name)
            }
            Button {
                activeSheet = .chapters
            } label: {
                HStack {
                    Label("查看全部章节", systemImage: "book.pages")
                    Spacer()
                    Text("\(chapters.count) 章").foregroundStyle(.secondary)
                    Image(systemName: "chevron.right").foregroundStyle(.secondary)
                }
                .font(.headline)
                .foregroundStyle(.primary)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
        }
        .debugCard()
    }

    private var contentCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("正文预览", icon: "doc.text.magnifyingglass", color: .green,
                          subtitle: "当前正文片段 · \(contentText.count) 字")
            Text(String(contentText.prefix(4000)))
                .font(.system(size: 17))
                .lineSpacing(8)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
            if contentText.count > 4000 {
                Text("……正文预览已截断")
                    .font(.footnote).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .debugCard()
    }

    private var debugLogCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionHeader("调试日志", icon: "waveform.path.ecg", color: .indigo,
                              subtitle: "共 \(timeline.count) 条，按时间顺序记录关键步骤")
                Spacer()
            }
            ForEach(Array(timeline.suffix(40).enumerated()), id: \.element.id) { index, entry in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: entry.level == .error ? "xmark.circle.fill" : "bolt.circle.fill")
                        .foregroundStyle(entry.level == .error ? .red : .blue)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("[\(formatTimestamp(entry.elapsed))]")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Text(entry.text)
                            .font(.system(.footnote, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 6)
                if index < min(timeline.count, 40) - 1 { Divider().opacity(0.3) }
            }
            Button {
                timeline.removeAll()
            } label: {
                Label("清除日志", systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
        }
        .debugCard()
    }

    private func sectionHeader(_ title: String, icon: String, color: Color, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.title2).foregroundStyle(color).frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.title3.bold())
                Text(subtitle).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func valueRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label).font(.footnote).foregroundStyle(.secondary).frame(width: 58, alignment: .leading)
            Text(value).font(.headline).lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func sheetView(_ sheet: DebugSheet) -> some View {
        switch sheet {
        case .source(let title, let text):
            DebugTextSheet(title: title, text: text)
        case .chapters:
            DebugChapterSheet(chapters: chapters)
        case .logs:
            NavigationStack { LogView() }
        case .timeline:
            DebugTimelineSheet(entries: timeline.map {
                SourceDebugTimelineItem(text: "[\(formatTimestamp($0.elapsed))] \($0.text)")
            })
        case .jsConsole:
            DebugTextSheet(
                title: "JS控制台",
                text: jsEntries.isEmpty ? "暂无 JS 控制台消息" : jsEntries.map(\.text).joined(separator: "\n\n")
            )
        }
    }

    // MARK: - Test execution

    @MainActor
    private func run() async {
        guard !running else { return }
        running = true
        books = []
        chapters = []
        contentText = ""
        bookInfo = nil
        stages = StageKind.allCases.map { StageResult(kind: $0) }
        timeline = []
        let startedAt = Date()
        let previousSink = EngineLogger.sink
        defer {
            EngineLogger.sink = previousSink
            running = false
        }

        guard let source = record.decodeSource() else {
            fail(.search, "书源配置解析失败", startedAt)
            return
        }
        let runtime = BookSourceRuntime(source)
        attachLogging(startedAt: startedAt)
        log("解析模式：本地解析", startedAt: startedAt)

        let raw = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.hasPrefix("--") {
            skip(.search, "直接测试正文")
            skip(.detail, "直接测试正文")
            skip(.toc, "直接测试正文")
            await runContent(runtime, url: String(raw.dropFirst(2)).trimmingCharacters(in: .whitespaces), startedAt: startedAt)
        } else if raw.hasPrefix("++") {
            skip(.search, "直接测试目录")
            skip(.detail, "直接测试目录")
            let url = String(raw.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            await runTocAndContent(runtime, source: source, bookURL: url, startedAt: startedAt)
        } else if isURL(raw) {
            skip(.search, "直接测试详情")
            let book = DebugBook(id: raw, name: "指定书籍", author: "", kind: "", bookURL: raw,
                                 sourceName: source.bookSourceName)
            await runBookChain(book, runtime: runtime, source: source, startedAt: startedAt)
        } else {
            await runSearch(runtime, source: source, keyword: raw.isEmpty ? suggestedKeyword(source) : raw,
                            startedAt: startedAt)
        }
    }

    @MainActor
    private func runSearch(
        _ runtime: BookSourceRuntime,
        source: BookSource,
        keyword: String,
        startedAt: Date
    ) async {
        let stageStart = Date()
        begin(.search, "正在搜索 \(keyword)")
        log("开始搜索关键字：\(keyword)", startedAt: startedAt)
        guard source.searchUrl?.isEmpty == false, source.ruleSearch?.bookList?.isEmpty == false else {
            fail(.search, "搜索规则缺失", stageStart)
            return
        }
        do {
            let list = try await runtime.search(keyword, resultLimit: 10)
            books = list.map {
                DebugBook(
                    id: $0.bookUrl + "|" + $0.name,
                    name: $0.name,
                    author: $0.author,
                    kind: $0.kind,
                    bookURL: $0.bookUrl,
                    sourceName: source.bookSourceName
                )
            }
            guard let first = books.first else {
                fail(.search, "没有搜索结果", stageStart)
                return
            }
            pass(.search, "找到 \(books.count) 本书", stageStart)
            log("搜索完成，找到 \(books.count) 本书", startedAt: startedAt)
            await runBookChain(first, runtime: runtime, source: source, startedAt: startedAt)
        } catch {
            fail(.search, error.localizedDescription, stageStart)
            log("搜索失败：\(error.localizedDescription)", level: .error, startedAt: startedAt)
        }
    }

    @MainActor
    private func runBookChain(_ book: DebugBook) async {
        guard !running, let source = record.decodeSource() else { return }
        running = true
        chapters = []
        contentText = ""
        bookInfo = nil
        for kind in [StageKind.detail, .toc, .content] {
            update(kind, status: .pending, detail: "尚未执行", duration: 0)
        }
        let startedAt = Date()
        let previousSink = EngineLogger.sink
        defer {
            EngineLogger.sink = previousSink
            running = false
        }
        attachLogging(startedAt: startedAt)
        let runtime = BookSourceRuntime(source)
        await runBookChain(book, runtime: runtime, source: source, startedAt: startedAt)
    }

    @MainActor
    private func runBookChain(
        _ book: DebugBook,
        runtime: BookSourceRuntime,
        source: BookSource,
        startedAt: Date
    ) async {
        let detailStart = Date()
        begin(.detail, "正在解析详情")
        log("开始解析详情页", startedAt: startedAt)
        do {
            let info = try await runtime.getBookInfo(bookUrl: book.bookURL, lightweight: true)
            bookInfo = info
            let author = book.author
            pass(.detail, author.isEmpty ? "详情解析完成" : "作者: \(author)", detailStart)
            log("详情页解析完成", startedAt: startedAt)
        } catch {
            fail(.detail, error.localizedDescription, detailStart)
            log("详情页解析失败：\(error.localizedDescription)", level: .error, startedAt: startedAt)
            skip(.toc, "详情解析失败")
            skip(.content, "详情解析失败")
            return
        }
        await runTocAndContent(
            runtime,
            source: source,
            bookURL: book.bookURL,
            resolvedTocURL: bookInfo?.tocUrl,
            startedAt: startedAt
        )
    }

    @MainActor
    private func runTocAndContent(
        _ runtime: BookSourceRuntime,
        source: BookSource,
        bookURL: String,
        resolvedTocURL: String? = nil,
        startedAt: Date
    ) async {
        let tocStart = Date()
        begin(.toc, "正在解析目录")
        log("开始解析目录页", startedAt: startedAt)
        do {
            chapters = try await runtime.getToc(bookUrl: bookURL, resolvedTocUrl: resolvedTocURL)
            guard let first = chapters.first else {
                fail(.toc, "目录为空", tocStart)
                skip(.content, "目录为空")
                return
            }
            pass(.toc, "共 \(chapters.count) 章", tocStart)
            log("目录页解析完成，共 \(chapters.count) 章", startedAt: startedAt)
            await runContent(runtime, url: first.url, startedAt: startedAt)
        } catch {
            fail(.toc, error.localizedDescription, tocStart)
            skip(.content, "目录解析失败")
            log("目录解析失败：\(error.localizedDescription)", level: .error, startedAt: startedAt)
        }
    }

    @MainActor
    private func runContent(_ runtime: BookSourceRuntime, url: String, startedAt: Date) async {
        let contentStart = Date()
        begin(.content, "正在解析正文")
        log("开始解析正文页", startedAt: startedAt)
        do {
            contentText = try await runtime.getContent(chapterUrl: url)
            if contentText.isEmpty {
                fail(.content, "正文为空", contentStart)
            } else {
                pass(.content, "\(contentText.count) 字", contentStart)
                log("正文页解析完成，\(contentText.count) 字", startedAt: startedAt)
            }
        } catch {
            fail(.content, error.localizedDescription, contentStart)
            log("正文解析失败：\(error.localizedDescription)", level: .error, startedAt: startedAt)
        }
    }

    @MainActor
    private func attachLogging(startedAt: Date) {
        EngineLogger.sink = { level, tag, message in
            Task { @MainActor in
                LogStore.shared.log(message, tag: tag, level: level == .error ? .error : (level == .warn ? .warn : .info))
                timeline.append(
                    TimelineEntry(
                        elapsed: Date().timeIntervalSince(startedAt),
                        text: message,
                        level: level == .error ? .error : (level == .warn ? .warn : .info)
                    )
                )
            }
        }
    }

    @MainActor
    private func log(_ text: String, level: LogLevel = .info, startedAt: Date) {
        timeline.append(TimelineEntry(elapsed: Date().timeIntervalSince(startedAt), text: text, level: level))
    }

    @MainActor
    private func begin(_ kind: StageKind, _ detail: String) {
        update(kind, status: .running, detail: detail, duration: 0)
    }

    @MainActor
    private func pass(_ kind: StageKind, _ detail: String, _ start: Date) {
        update(kind, status: .passed, detail: detail, duration: Date().timeIntervalSince(start))
    }

    @MainActor
    private func fail(_ kind: StageKind, _ detail: String, _ start: Date) {
        update(kind, status: .failed, detail: detail, duration: Date().timeIntervalSince(start))
    }

    @MainActor
    private func skip(_ kind: StageKind, _ detail: String) {
        update(kind, status: .skipped, detail: detail, duration: 0)
    }

    @MainActor
    private func update(_ kind: StageKind, status: StageStatus, detail: String, duration: TimeInterval) {
        guard let index = stages.firstIndex(where: { $0.kind == kind }) else { return }
        stages[index].status = status
        stages[index].detail = detail
        stages[index].duration = duration
    }

    // MARK: - Derived values and actions

    private var passedCount: Int { stages.filter { $0.status == .passed }.count }
    private var failedCount: Int { stages.filter { $0.status == .failed }.count }
    private var totalDuration: TimeInterval { stages.reduce(0) { $0 + $1.duration } }
    private var jsEntries: [TimelineEntry] {
        timeline.filter {
            let text = $0.text.lowercased()
            return text.contains("javascript") || text.contains("evaljs") || text.contains("js ")
        }
    }

    private var sourceTypeName: String {
        guard let type = record.decodeSource()?.bookSourceType else { return "文本配置" }
        switch type {
        case .text: return "文本配置"
        case .audio: return "音频配置"
        case .image: return "图片配置"
        case .file: return "文件配置"
        case .video: return "视频配置"
        }
    }

    private var modeDescription: String {
        let text = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("--") { return "正文 · 直接解析正文" }
        if text.hasPrefix("++") { return "目录 · 目录 → 正文" }
        if isURL(text) { return "详情 · 详情 → 目录 → 正文" }
        return "搜索 · 搜索 → 详情 → 目录 → 正文"
    }

    private func suggestedKeyword(_ source: BookSource) -> String {
        let raw = source.ruleSearch?.checkKeyWord?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !raw.isEmpty {
            return raw.components(separatedBy: "@").first?.trimmingCharacters(in: .whitespaces) ?? raw
        }
        return "我的"
    }

    private func sourceCode(_ kind: SourceCodeKind) -> String {
        guard let source = record.decodeSource() else { return "书源配置解析失败" }
        switch kind {
        case .search:
            return "searchUrl:\n\(source.searchUrl ?? "未配置")\n\nruleSearch:\n\(prettyJSON(source.ruleSearch))"
        case .explore:
            return "exploreUrl:\n\(source.exploreUrl ?? "未配置")\n\nruleExplore:\n\(prettyJSON(source.ruleExplore))"
        case .detail:
            return "ruleBookInfo:\n\(prettyJSON(source.ruleBookInfo))"
        case .toc:
            return "ruleToc:\n\(prettyJSON(source.ruleToc))"
        case .content:
            return "ruleContent:\n\(prettyJSON(source.ruleContent))"
        }
    }

    private func prettyJSON<T: Encodable>(_ value: T?) -> String {
        guard let value else { return "未配置" }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value), let text = String(data: data, encoding: .utf8) else {
            return "无法序列化"
        }
        return text
    }

    private func copyReport() {
        let stageText = stages.map {
            "\($0.kind.rawValue): \($0.status.title) · \($0.detail) · \(formatDuration($0.duration))"
        }.joined(separator: "\n")
        let bookText = books.prefix(10).map { "\($0.name) · \($0.author) · \($0.bookURL)" }.joined(separator: "\n")
        let logText = timeline.map { "[\(formatTimestamp($0.elapsed))] \($0.text)" }.joined(separator: "\n")
        UIPasteboard.general.string = """
        配置测试：\(record.bookSourceName)
        地址：\(record.bookSourceUrl)
        输入：\(keyword)

        \(stageText)

        搜索结果：
        \(bookText)

        章节数：\(chapters.count)
        正文字数：\(contentText.count)

        调试日志：
        \(logText)
        """
        showNotice("测试报告已复制")
    }

    private func clearVariables() {
        UserDefaultsKeyValueStore(namespace: record.bookSourceUrl).removeAll()
        showNotice("配置变量已清除")
    }

    private func showNotice(_ text: String) {
        notice = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if notice == text { notice = nil }
        }
    }

    private func formatDuration(_ value: TimeInterval) -> String {
        String(format: "%.2fs", value)
    }

    private func formatTimestamp(_ value: TimeInterval) -> String {
        let minutes = Int(value) / 60
        let seconds = value - Double(minutes * 60)
        return String(format: "%02d:%06.3f", minutes, seconds)
    }

    private func isURL(_ text: String) -> Bool {
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https" || scheme == "data"
    }
}

private struct DebugTextSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let text: String

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(text)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { UIPasteboard.general.string = text } label: {
                        Image(systemName: "doc.on.doc")
                    }
                }
            }
        }
    }
}

private struct DebugChapterSheet: View {
    @Environment(\.dismiss) private var dismiss
    let chapters: [ChapterInfo]

    var body: some View {
        NavigationStack {
            List(Array(chapters.enumerated()), id: \.offset) { index, chapter in
                VStack(alignment: .leading, spacing: 4) {
                    Text(chapter.name).font(.headline)
                    Text("第 \(index + 1) 章 · \(chapter.url)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .padding(.vertical, 4)
            }
            .navigationTitle("章节列表 · \(chapters.count)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}

private struct DebugTimelineSheet: View {
    @Environment(\.dismiss) private var dismiss
    let entries: [SourceDebugTimelineItem]

    var body: some View {
        NavigationStack {
            List(entries) { entry in
                Text(entry.text)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(.vertical, 4)
            }
            .navigationTitle("诊断时间线")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}

private struct SourceDebugTimelineItem: Identifiable {
    let id = UUID()
    let text: String
}

private extension View {
    func debugCard() -> some View {
        padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.55), lineWidth: 0.6))
    }
}
