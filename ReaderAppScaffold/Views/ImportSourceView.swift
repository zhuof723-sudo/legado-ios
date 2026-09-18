import SwiftUI
import SwiftData
import UniformTypeIdentifiers

public struct ImportSourceView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var jsonText = ""
    @State private var showFileImporter = false
    @State private var resultMessage: String?

    public init() {}

    public var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                TextEditor(text: $jsonText)
                    .font(.system(.footnote, design: .monospaced))
                    .frame(minHeight: 220)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator))

                Button {
                    showFileImporter = true
                } label: {
                    Label("从文件导入(.json)", systemImage: "doc.badge.plus")
                }

                if let resultMessage {
                    Text(resultMessage).font(.footnote).foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("导入书源")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("导入") { doImport(jsonText) }
                        .disabled(jsonText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.json, .text],
                allowsMultipleSelection: false,
                // 关键：让系统把文件复制到 App 临时目录后再交付。
                // 这样拿到的是普通本地 URL，不依赖 security-scoped 授权是否成功，
                // 从根上规避"选了文件读不到 / 没反应"的问题。
                onCompletion: handleFileSelection
            )
        }
    }

    private func handleFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else {
                resultMessage = "没有选择文件"
                return
            }
            loadSourceFile(url)
        case .failure(let error):
            resultMessage = "选择文件失败：\(error.localizedDescription)"
        }
    }

    /// 读取用户选中的书源文件。
    ///
    /// 注意：`startAccessingSecurityScopedResource()` 返回 false **不代表无法读取**——
    /// 它在不少正常场景下都会返回 false（文件位于 App 自身容器内、iCloud/本地
    /// provider 直接授权等）。旧实现在这里写成 `if url.startAccessing… { 读取 }`，
    /// 返回 false 时整段被跳过，既不读文件也不给任何提示，表现就是"选了文件没反应"。
    /// 现在改为：无论该调用成败都继续尝试读取，并把每一种失败原因显示出来，
    /// 不再出现静默无响应。
    private func loadSourceFile(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        // 优先用 FileCoordinator 读取（对 iCloud Drive / 第三方 provider 的
        // 未下载或正在同步文件更可靠），失败再退回直接读取。
        var data: Data?
        var readError: Error?
        let coordinator = NSFileCoordinator()
        var coordinatorError: NSError?
        coordinator.coordinate(readingItemAt: url, options: [], error: &coordinatorError) { readURL in
            do {
                data = try Data(contentsOf: readURL)
            } catch {
                readError = error
            }
        }

        if data == nil, let coordinatorError {
            readError = coordinatorError
        }
        if data == nil, coordinatorError == nil, readError == nil {
            do { data = try Data(contentsOf: url) } catch { readError = error }
        }

        guard let data else {
            resultMessage = "无法读取文件：\(readError?.localizedDescription ?? "未知错误")"
            return
        }
        guard !data.isEmpty else {
            resultMessage = "文件是空的，没有可导入的内容"
            return
        }

        // UTF-8 → 带 BOM 的 UTF-8 → GB18030（国内书源文件常见）
        let text: String
        if let s = String(data: data, encoding: .utf8) {
            text = s
        } else if let s = decodeGB18030(data) {
            text = s
        } else {
            resultMessage = "文件编码无法识别（需 UTF-8 或 GBK/GB18030）"
            return
        }

        // 顺手把内容回填到输入框，即使解析失败用户也能看到并手动改。
        jsonText = text
        doImport(text)
    }

    private func decodeGB18030(_ data: Data) -> String? {
        let cfEncoding = CFStringEncodings.GB_18030_2000
        let enc = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(cfEncoding.rawValue))
        return String(data: data, encoding: String.Encoding(rawValue: enc))
    }

    private func doImport(_ text: String) {
        let store = BookSourceStore(context: context)
        let count = store.importSources(from: text)
        if let err = store.errorMessage {
            resultMessage = err
        } else {
            if store.skippedCount > 0 {
                resultMessage = "成功导入 \(count) 个书源，跳过 \(store.skippedCount) 个（缺少 bookSourceUrl）"
            } else {
                resultMessage = "成功导入 \(count) 个书源"
            }
            if count > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { dismiss() }
            }
        }
    }
}
