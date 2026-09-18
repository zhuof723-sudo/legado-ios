import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// 导入本地 TXT：选择文件 → 按章节切分 → 存入书架（本地书籍）
struct TxtImportView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var message: String?
    @State private var isPicking = false

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
                    pickFile()
                } label: {
                    Label("选择 .txt 文件", systemImage: "folder")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                }
                .prominentGlassButton()
                .tint(Theme.accent)
                .foregroundStyle(.white)
                .disabled(isPicking)

                if isPicking {
                    Text("正在打开文件选择器…").font(.footnote).foregroundStyle(Theme.accent)
                }

                if let message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
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
        }
    }

    /// 同书源导入：用 UIKit 的选择器，避免 `.fileImporter` 在 sheet 内静默失效。
    private func pickFile() {
        isPicking = true
        message = nil
        FilePicker.present(contentTypes: [.plainText, .text, .data]) { result in
            isPicking = false
            switch result {
            case .success(let urls):
                guard let url = urls.first else {
                    message = "没有选择文件"
                    return
                }
                importFile(url)
            case .failure(let error):
                if (error as? FilePicker.PickerError) == .cancelled { return }
                message = "打开文件选择器失败：\(error.localizedDescription)"
            }
        }
    }

    private func importFile(_ url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        let text: String
        do {
            text = try FileTextReader.readText(from: url)
        } catch {
            message = error.localizedDescription
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
}
