import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// 导入本地 TXT：选择文件 → 按章节切分 → 存入书架（本地书籍）
struct TxtImportView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var showFileImporter = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Spacer()
                Image(systemName: "doc.text")
                    .font(.system(size: 52, weight: .light))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 110, height: 110)
                    .glassCard(RoundedRectangle(cornerRadius: 28))
                Text("导入本地 TXT 小说")
                    .font(.title3.bold())
                Text("自动按「第X章/卷/节…」切分章节；\n识别不到时按空行分块，仍不行则整本一章。")
                    .font(.footnote).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button {
                    showFileImporter = true
                } label: {
                    Label("选择 .txt 文件", systemImage: "folder")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                }
                .prominentGlassButton()
                .tint(Theme.accent)
                .foregroundStyle(.white)

                if let message {
                    Text(message).font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(24)
            .navigationTitle("导入 TXT")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.plainText, .text, .data],
                allowsMultipleSelection: false,
                // 同书源导入：用系统复制的副本读取，避免 security-scoped 授权问题。
                onCompletion: handleFileSelection
            )
        }
    }

    private func handleFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else {
                message = "没有选择文件"
                return
            }
            importFile(url)
        case .failure(let error):
            message = "选择文件失败：\(error.localizedDescription)"
        }
    }

    private func importFile(_ url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        // 同书源导入：FileCoordinator 优先（iCloud/第三方 provider 更可靠），失败再直接读。
        var data: Data?
        var readError: Error?
        let coordinator = NSFileCoordinator()
        var coordinatorError: NSError?
        coordinator.coordinate(readingItemAt: url, options: [], error: &coordinatorError) { readURL in
            do { data = try Data(contentsOf: readURL) } catch { readError = error }
        }
        if data == nil, let coordinatorError { readError = coordinatorError }
        if data == nil, coordinatorError == nil, readError == nil {
            do { data = try Data(contentsOf: url) } catch { readError = error }
        }

        guard let data else {
            message = "无法读取文件：\(readError?.localizedDescription ?? "未知错误")"
            return
        }
        guard !data.isEmpty else {
            message = "文件是空的，没有可导入的内容"
            return
        }

        // 编码识别：UTF-8（含 BOM）→ UTF-16 → GB18030（国内 TXT 常见）
        let text: String
        if let s = String(data: data, encoding: .utf8) {
            text = s
        } else if let s = String(data: data, encoding: .utf16) {
            text = s
        } else if let s = decodeGBK(data) {
            text = s
        } else {
            message = "文件编码无法识别（试过 UTF-8 / UTF-16 / GB18030）"
            return
        }

        let chapters = TxtParser.chapters(from: text)
        guard !chapters.isEmpty else {
            message = "没能从文件里切分出任何章节（文件可能不是纯文本）"
            return
        }

        let name = url.deletingPathExtension().lastPathComponent
        let book = LocalBook(name: name, author: "本地导入", chaptersData: TxtParser.encode(chapters))
        context.insert(book)
        do {
            try context.save()
        } catch {
            message = "保存失败：\(error.localizedDescription)"
            return
        }
        message = "已导入「\(name)」，共 \(chapters.count) 章"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { dismiss() }
    }

    private func decodeGBK(_ data: Data) -> String? {
        let cfEncoding = CFStringEncodings.GB_18030_2000
        let enc = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(cfEncoding.rawValue))
        return String(data: data, encoding: String.Encoding(rawValue: enc))
    }
}
