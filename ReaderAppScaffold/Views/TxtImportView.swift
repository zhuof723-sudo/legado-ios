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
                    .background(RoundedRectangle(cornerRadius: 28).fill(Color.white))
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
            .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.plainText, .text]) { result in
                switch result {
                case .success(let url):
                    importFile(url)
                case .failure(let error):
                    message = "读取失败: \(error.localizedDescription)"
                }
            }
        }
    }

    private func importFile(_ url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        let encoding: String.Encoding = .utf8
        guard let data = try? Data(contentsOf: url) else {
            message = "无法读取文件"
            return
        }
        // 优先 utf8，失败退 gbk
        let text: String
        if let s = String(data: data, encoding: .utf8) {
            text = s
        } else if let s = decodeGBK(data) {
            text = s
        } else {
            message = "文件编码无法识别（需 UTF-8 或 GBK）"
            return
        }

        let chapters = TxtParser.chapters(from: text)
        let name = url.deletingPathExtension().lastPathComponent
        let book = LocalBook(name: name, author: "本地导入", chaptersData: TxtParser.encode(chapters))
        context.insert(book)
        try? context.save()
        message = "已导入「\(name)」，共 \(chapters.count) 章"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { dismiss() }
    }

    private func decodeGBK(_ data: Data) -> String? {
        let cfEncoding = CFStringEncodings.GB_18030_2000
        let enc = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(cfEncoding.rawValue))
        return String(data: data, encoding: String.Encoding(rawValue: enc))
    }
}
