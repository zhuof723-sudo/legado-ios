import SwiftUI
import SwiftData
import LegadoRuleEngine
import UniformTypeIdentifiers

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
