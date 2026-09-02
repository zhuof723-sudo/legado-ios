import SwiftUI
import SwiftData
import LegadoRuleEngine
import UniformTypeIdentifiers

// MARK: - 测试配置

struct SourceTestView: View {
    let record: BookSourceRecord
    @Environment(\.dismiss) private var dismiss
    @State private var keyword = "斗破苍穹"
    @State private var running = false
    @State private var results: [SearchResult] = []
    @State private var errorMsg: String?
    @State private var source: BookSource?

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    TextField("测试关键词", text: $keyword)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                    Button {
                        Task { await run() }
                    } label: {
                        Text("开始测试").bold()
                    }
                    .prominentGlassButton()
                    .tint(Theme.accent)
                    .foregroundStyle(.white)
                    .disabled(running || source == nil)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                if running {
                    Spacer()
                    ProgressView("测试中…")
                    Spacer()
                } else if let errorMsg {
                    Text("❌ \(errorMsg)")
                        .font(.footnote).foregroundStyle(.red)
                        .padding(.horizontal, 16)
                    Spacer()
                } else if !results.isEmpty {
                    List(results, id: \.bookUrl) { r in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(r.name).font(.subheadline.bold())
                            Text("作者: \(r.author)").font(.caption).foregroundStyle(.secondary)
                            Text(r.bookUrl).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                        }
                    }
                    .listStyle(.plain)
                } else {
                    Spacer()
                    ContentUnavailableView("尚未测试", systemImage: "play.circle",
                                           description: Text("输入关键词点「开始测试」，会按 searchUrl 规则请求并解析"))
                    Spacer()
                }

                Text("测试结果会同步写入「运行日志」")
                    .font(.caption2).foregroundStyle(.secondary)
                    .padding(.bottom, 8)
            }
            .navigationTitle("测试配置 · \(record.bookSourceName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .task {
                source = record.decodeSource()
                engineLog("打开书源测试: \(record.bookSourceName)", tag: "测试", level: .info)
            }
        }
    }

    private func run() async {
        guard let source else { return }
        running = true
        errorMsg = nil
        results = []
        engineLog("开始测试搜索: \(keyword)", tag: record.bookSourceName, level: .info)
        let runtime = BookSourceRuntime(source)
        do {
            results = try await runtime.search(keyword)
            engineLog("测试命中 \(results.count) 条结果", tag: record.bookSourceName, level: .info)
        } catch {
            errorMsg = error.localizedDescription
            engineLog("测试失败: \(error.localizedDescription)", tag: record.bookSourceName, level: .error)
        }
        running = false
    }
}

// MARK: - 编辑配置

struct SourceEditView: View {
    let record: BookSourceRecord
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var message: String?

    init(record: BookSourceRecord) {
        self.record = record
        self._text = State(initialValue: record.rawJSON)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 8) {
                TextEditor(text: $text)
                    .font(.system(.footnote, design: .monospaced))
                    .autocorrectionDisabled()
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator))
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                if let message {
                    Text(message).font(.footnote).foregroundStyle(.red).padding(.horizontal, 16)
                }
            }
            .navigationTitle("编辑配置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                }
            }
        }
    }

    private func save() {
        let parsed = try? BookSourceImporter.parse(text)
        guard let s = parsed?.first, !s.bookSourceUrl.isEmpty else {
            message = "JSON 解析失败或缺少 bookSourceUrl 字段"
            return
        }
        record.rawJSON = text
        record.bookSourceName = s.bookSourceName
        record.bookSourceGroup = s.bookSourceGroup
        record.bookSourceUrl = s.bookSourceUrl
        record.enabled = s.enabled
        try? context.save()
        dismiss()
    }
}

// MARK: - 登录

struct SourceLoginView: View {
    let record: BookSourceRecord
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let src = record.decodeSource(), let loginUrl = src.loginUrl, !loginUrl.isEmpty {
                    VStack(spacing: 16) {
                        Spacer()
                        Image(systemName: "person.crop.circle")
                            .font(.system(size: 52, weight: .light))
                            .foregroundStyle(Theme.accent)
                        Text("该书源配置了登录地址").font(.headline)
                        Text(loginUrl).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        if let url = URL(string: loginUrl) {
                            Link(destination: url) {
                                Label("在浏览器中打开登录页", systemImage: "safari")
                                    .frame(maxWidth: .infinity).padding(.vertical, 13)
                            }
                            .prominentGlassButton()
                            .tint(Theme.accent)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 24)
                        }
                        Text("说明：登录主要是让带 Cookie 的书源生效。当前版本 Cookie 持久化能力有限，登录后若仍无法访问，需要在书源规则里补充 Cookie 相关处理。")
                            .font(.footnote).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                        Spacer()
                    }
                } else {
                    ContentUnavailableView("未配置登录地址", systemImage: "person.crop.circle.badge.xmark",
                                           description: Text("该书源没有 loginUrl 字段"))
                }
            }
            .navigationTitle("登录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}

// MARK: - 导出配置文件

struct SourceJSONDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .plainText] }
    var text: String

    init(text: String) { self.text = text }

    init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents,
           let s = String(data: data, encoding: .utf8) {
            text = s
        } else {
            text = ""
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
