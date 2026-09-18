import SwiftUI
import LegadoRuleEngine

private enum BatchTestKind: String, CaseIterable, Identifiable {
    case all = "全部书源"
    case enabled = "已启用书源"
    var id: String { rawValue }
}

@MainActor
private final class BatchTestStage: ObservableObject, Identifiable {
    enum Kind: String, CaseIterable {
        case search = "搜索"
        case detail = "详情"
        case toc = "目录"
        case content = "正文"
    }
    enum StageStatus: Equatable {
        case pending, running, passed, failed, skipped
        var color: Color {
            switch self {
            case .passed: return .green
            case .failed: return .red
            case .running: return Theme.accent
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

    let kind: Kind
    let id: String
    @Published var status: StageStatus = .pending
    @Published var detail = "尚未执行"
    var firstBook: SearchResult?
    var chapters: [ChapterInfo]?

    init(kind: Kind) {
        self.kind = kind
        self.id = kind.rawValue
    }
}

@MainActor
private final class BatchTestSourceResult: ObservableObject, Identifiable {
    let id = UUID()
    let record: BookSourceRecord
    let url: String
    @Published var overall: BatchTestStage.StageStatus = .pending
    let search = BatchTestStage(kind: .search)
    let detail = BatchTestStage(kind: .detail)
    let toc = BatchTestStage(kind: .toc)
    let content = BatchTestStage(kind: .content)
    @Published var errorMessage: String?
    @Published var elapsed: TimeInterval = 0

    var stages: [BatchTestStage] { [search, detail, toc, content] }
    var passedCount: Int { stages.filter { $0.status == .passed }.count }
    var failedCount: Int { stages.filter { $0.status == .failed }.count }

    init(record: BookSourceRecord, url: String) {
        self.record = record
        self.url = url
    }
}

@MainActor
private final class BatchTestRunner: ObservableObject {
    @Published var results: [BatchTestSourceResult] = []
    @Published var isRunning = false
    @Published var progress: (done: Int, total: Int) = (0, 0)

    func run(records: [BookSourceRecord], keyword: String) async {
        isRunning = true
        progress = (0, records.count)
        results = records.map { BatchTestSourceResult(record: $0, url: $0.bookSourceUrl) }
        let raw = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        let startedAt = Date()

        for index in 0..<results.count {
            let result = results[index]
            guard let source = result.record.decodeSource() else {
                result.overall = .failed
                result.errorMessage = "书源解析失败"
                skipPending(in: result, reason: "书源解析失败")
                result.elapsed = Date().timeIntervalSince(startedAt)
                progress = (index + 1, records.count)
                continue
            }
            let runtime = BookSourceRuntime(source)
            var didFail = false

            if !didFail {
                do {
                    try await runSearch(result, runtime: runtime, source: source,
                                        keyword: raw.isEmpty ? suggestedKeyword(source) : raw)
                } catch {
                    result.search.status = .failed
                    result.search.detail = error.localizedDescription
                    didFail = true
                }
            }
            if !didFail, let book = result.search.firstBook {
                do {
                    try await runDetail(result, runtime: runtime, book: book)
                } catch {
                    result.detail.status = .failed
                    result.detail.detail = error.localizedDescription
                    didFail = true
                }
            }
            if !didFail, result.detail.status == .passed, let book = result.search.firstBook {
                do {
                    try await runToc(result, runtime: runtime, book: book)
                } catch {
                    result.toc.status = .failed
                    result.toc.detail = error.localizedDescription
                    didFail = true
                }
            }
            if !didFail, result.toc.status == .passed,
               let chapters = result.toc.chapters, let first = chapters.first {
                do {
                    try await runContent(result, runtime: runtime, url: first.url)
                } catch {
                    result.content.status = .failed
                    result.content.detail = error.localizedDescription
                    didFail = true
                }
            }

            result.elapsed = Date().timeIntervalSince(startedAt)
            if result.passedCount == 4 {
                result.overall = .passed
            } else if result.failedCount > 0 {
                result.overall = .failed
            } else {
                result.overall = .skipped
            }
            progress = (index + 1, records.count)
        }
        isRunning = false
    }

    private func skipPending(in result: BatchTestSourceResult, reason: String) {
        for stage in result.stages where stage.status == .pending {
            stage.status = .skipped
            stage.detail = reason
        }
    }

    private func runSearch(_ result: BatchTestSourceResult, runtime: BookSourceRuntime,
                           source: BookSource, keyword: String) async throws {
        result.search.status = .running
        guard source.searchUrl?.isEmpty == false, source.ruleSearch?.bookList?.isEmpty == false else {
            result.search.status = .failed
            result.search.detail = "搜索规则缺失"
            throw NSError(domain: "batch", code: 1)
        }
        let list = try await runtime.search(keyword, resultLimit: 5)
        guard let first = list.first else {
            result.search.status = .failed
            result.search.detail = "没有搜索结果"
            throw NSError(domain: "batch", code: 2)
        }
        result.search.status = .passed
        result.search.detail = "找到 \(list.count) 本"
        result.search.firstBook = first
    }

    private func runDetail(_ result: BatchTestSourceResult, runtime: BookSourceRuntime,
                           book: SearchResult) async throws {
        result.detail.status = .running
        let info = try await runtime.getBookInfo(bookUrl: book.bookUrl)
        result.detail.status = .passed
        result.detail.detail = info.name.isEmpty ? "解析完成" : info.name
    }

    private func runToc(_ result: BatchTestSourceResult, runtime: BookSourceRuntime,
                        book: SearchResult) async throws {
        result.toc.status = .running
        let chapters = try await runtime.getToc(bookUrl: book.bookUrl, resolvedTocUrl: book.bookUrl)
        guard !chapters.isEmpty else {
            result.toc.status = .failed
            result.toc.detail = "目录为空"
            throw NSError(domain: "batch", code: 3)
        }
        result.toc.status = .passed
        result.toc.detail = "\(chapters.count) 章"
        result.toc.chapters = chapters
    }

    private func runContent(_ result: BatchTestSourceResult, runtime: BookSourceRuntime,
                            url: String) async throws {
        result.content.status = .running
        let text = try await runtime.getContent(chapterUrl: url)
        if text.isEmpty {
            result.content.status = .failed
            result.content.detail = "正文为空"
            throw NSError(domain: "batch", code: 4)
        } else {
            result.content.status = .passed
            result.content.detail = "\(text.count) 字"
        }
    }

    private func suggestedKeyword(_ source: BookSource) -> String {
        let raw = source.ruleSearch?.checkKeyWord?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !raw.isEmpty {
            return raw.components(separatedBy: "@").first?.trimmingCharacters(in: .whitespaces) ?? raw
        }
        return "我的"
    }
}

struct BatchTestView: View {
    @Environment(\.dismiss) private var dismiss
    let records: [BookSourceRecord]
    @StateObject private var runner = BatchTestRunner()
    @State private var keyword = ""
    @State private var selectedKind: BatchTestKind = .enabled
    @State private var showResult = false

    private var targets: [BookSourceRecord] {
        switch selectedKind {
        case .all: return records
        case .enabled: return records.filter { $0.enabled }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Theme.bg.ignoresSafeArea()
                if showResult {
                    resultBody
                } else {
                    configBody
                }
            }
            .navigationTitle("批量测试")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 14)
                        .frame(height: 36)
                        .glassCard(Capsule(), interactive: true)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if showResult {
                        Button("返回配置") { showResult = false }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                            .padding(.horizontal, 14)
                            .frame(height: 36)
                            .glassCard(Capsule(), interactive: true)
                    } else {
                        Button("开始测试") { startTest() }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                            .padding(.horizontal, 14)
                            .frame(height: 36)
                            .glassCard(Capsule(), interactive: true)
                            .disabled(runner.isRunning || targets.isEmpty)
                    }
                }
            }
        }
    }

    private var configBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("测试配置")
                    .font(.subheadline.bold())
                    .padding(.top, 8)

                VStack(alignment: .leading, spacing: 12) {
                    Text("测试范围").font(.footnote.bold()).foregroundStyle(.secondary)
                    Picker("测试范围", selection: $selectedKind) {
                        ForEach(BatchTestKind.allCases) { kind in
                            Text(kind.rawValue).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                    .tint(Theme.accent)
                    .disabled(runner.isRunning)
                }
                .padding(14)
                .glassCard(RoundedRectangle(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 12) {
                    Text("搜索关键词").font(.footnote.bold()).foregroundStyle(.secondary)
                    TextField("留空则使用书源默认校验词", text: $keyword)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 14)
                        .frame(height: 48)
                        .glassCard(RoundedRectangle(cornerRadius: 14), interactive: true)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .disabled(runner.isRunning)
                    Text("将按 搜索 → 详情 → 目录 → 正文 顺序逐源测试，每个源取首本书与首章。")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                .padding(14)
                .glassCard(RoundedRectangle(cornerRadius: 14))

                HStack {
                    Text("共 \(targets.count) 个书源")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }
            }
            .padding(16)
            .padding(.bottom, 24)
        }
    }

    private var resultBody: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if runner.isRunning {
                    VStack(spacing: 8) {
                        ProgressView()
                        Text("测试中 \(runner.progress.done)/\(runner.progress.total)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(16)
                    .glassCard(RoundedRectangle(cornerRadius: 14))
                }

                ForEach(runner.results) { result in
                    BatchTestResultCard(result: result)
                }
            }
            .padding(16)
            .padding(.bottom, 24)
        }
    }

    private func startTest() {
        showResult = true
        Task {
            await runner.run(records: targets, keyword: keyword)
        }
    }
}

private struct BatchTestResultCard: View {
    @ObservedObject var result: BatchTestSourceResult

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: result.overall.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(result.overall.color)
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.record.bookSourceName)
                        .font(.subheadline.bold()).foregroundStyle(.primary).lineLimit(1)
                    Text(result.url)
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                if result.overall != .pending, result.overall != .running {
                    Text(String(format: "%.2fs", result.elapsed))
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 8) {
                ForEach(result.stages) { stage in
                    HStack(spacing: 4) {
                        Image(systemName: stage.status.icon)
                            .font(.caption2)
                            .foregroundStyle(stage.status.color)
                        Text(stage.kind.rawValue)
                            .font(.caption2)
                            .foregroundStyle(stage.status == .pending ? .secondary : .primary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(stage.status.color.opacity(0.08), in: Capsule())
                }
            }
            if let error = result.errorMessage {
                Text(error)
                    .font(.caption2).foregroundStyle(.red)
            }
        }
        .padding(14)
        .glassCard(RoundedRectangle(cornerRadius: 14))
    }
}
