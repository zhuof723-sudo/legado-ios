import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import PDFKit

/// 导入本地书籍（TXT / EPUB / PDF）：选择文件 → 解析 → 存入书架。
/// - TXT：按章节正则切分
/// - EPUB：MiniZIP 解包 → OPF/spine → XHTML 抽正文（Fuzi），产出与 TXT 相同的章节结构
/// - PDF：文件副本存入沙盒，PDFKit 按页渲染（见 PDFReaderView）
struct TxtImportView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var message: String?
    @State private var isPicking = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Spacer()
                Image(systemName: "books.vertical")
                    .font(.system(size: 52, weight: .light))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 110, height: 110)
                    .glassCard(RoundedRectangle(cornerRadius: 28))
                Text("导入本地书籍")
                    .font(.title3.bold())
                Text("支持 TXT / EPUB / PDF\nTXT 自动按「第X章/卷/节…」切分；\nEPUB 解析 OPF 目录结构；PDF 按页渲染。")
                    .font(.footnote).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button {
                    pickFile()
                } label: {
                    Label("选择书籍文件", systemImage: "folder")
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
            .navigationTitle("导入书籍")
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
        FilePicker.present(contentTypes: [.plainText, .text, .data, .pdf, .epub]) { result in
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
        do {
            let result = try LocalLibraryImportService.importBook(from: url, context: context)
            message = "已导入《\(result.title)》，\(result.detail)"
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { dismiss() }
        } catch {
            message = "导入失败：\(error.localizedDescription)"
        }
    }
}
