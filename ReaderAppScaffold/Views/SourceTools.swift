import SwiftUI
import SwiftData
import LegadoRuleEngine
import UniformTypeIdentifiers

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

// MARK: - 从网络导入

struct UrlImportView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var urlText = ""
    @State private var loading = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                TextField("书源 JSON 地址（https://…）", text: $urlText)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                Button {
                    Task { await fetch() }
                } label: {
                    Label("获取并导入", systemImage: "arrow.down.circle")
                        .frame(maxWidth: .infinity).padding(.vertical, 13)
                }
                .prominentGlassButton()
                .tint(Theme.accent)
                .foregroundStyle(.white)
                .disabled(urlText.trimmingCharacters(in: .whitespaces).isEmpty || loading)

                if loading { ProgressView("下载中…") }
                if let message {
                    Text(message).font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding()
            .navigationTitle("从网络导入")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }

    private func fetch() async {
        let raw = urlText.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: raw) else {
            message = "地址无效"
            return
        }
        loading = true
        message = nil
        do {
            var req = URLRequest(url: url)
            req.timeoutInterval = 30
            let (data, _) = try await URLSession.shared.data(for: req)
            var text = String(data: data, encoding: .utf8)
            if text == nil {
                let cf = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
                text = String(data: data, encoding: String.Encoding(rawValue: cf))
            }
            guard let text, !text.isEmpty else {
                message = "下载内容为空或编码无法识别"
                loading = false
                return
            }
            let store = BookSourceStore(context: context)
            let count = store.importSources(from: text)
            message = store.errorMessage ?? (store.skippedCount > 0
                ? "成功导入 \(count) 个，跳过 \(store.skippedCount) 个"
                : "成功导入 \(count) 个书源")
            if count > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { dismiss() }
            }
        } catch {
            message = "下载失败: \(error.localizedDescription)"
        }
        loading = false
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
