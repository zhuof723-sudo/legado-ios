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

        let ext = url.pathExtension.lowercased()
        let name = url.deletingPathExtension().lastPathComponent

        switch ext {
        case "epub":
            importEpub(url, fallbackName: name)
        case "pdf":
            importPDF(url, fallbackName: name)
        default:
            importTXT(url, fallbackName: name)
        }
    }

    // MARK: - TXT

    private func importTXT(_ url: URL, fallbackName: String) {
        let text: String
        do {
            text = try BookReaderFileParser.readText(url: url)
        } catch {
            message = error.localizedDescription
            return
        }

        let chapters = BookReaderFileParser.chapters(from: text)
        guard !chapters.isEmpty else {
            message = "没能从文件里切分出任何章节（文件可能不是纯文本）"
            return
        }

        let book = LocalBook(name: fallbackName, author: "本地导入", chaptersData: BookReaderFileParser.encode(chapters))
        context.insert(book)
        do {
            try context.save()
        } catch {
            message = "保存失败：\(error.localizedDescription)"
            return
        }
        message = "已导入「\(book.name)」，共 \(chapters.count) 章"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { dismiss() }
    }

    // MARK: - EPUB

    private func importEpub(_ url: URL, fallbackName: String) {
        let parsed: BookReaderFileParser.EPUBBook
        do {
            parsed = try BookReaderFileParser.parseEPUB(url: url)
        } catch {
            message = "EPUB 导入失败：\(error.localizedDescription)"
            return
        }
        guard !parsed.chapters.isEmpty else {
            message = "EPUB 没有可读取的正文章节"
            return
        }

        let title = parsed.title.isEmpty ? fallbackName : parsed.title
        let book = LocalBook(
            name: title,
            author: parsed.author,
            chaptersData: BookReaderFileParser.encode(parsed.chapters)
        )
        context.insert(book)
        do {
            try context.save()
        } catch {
            message = "保存失败：\(error.localizedDescription)"
            return
        }
        message = "已导入《\(title)》，共 \(parsed.chapters.count) 章"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { dismiss() }
    }

    // MARK: - PDF

    private func importPDF(_ url: URL, fallbackName: String) {
        let fileName = UUID().uuidString + ".pdf"
        let dest = PDFBook.pdfDirectory.appendingPathComponent(fileName)
        do {
            try FileManager.default.copyItem(at: url, to: dest)
        } catch {
            message = "PDF 保存失败：\(error.localizedDescription)"
            return
        }

        let meta = PDFReaderViewModel.metadata(from: dest)
        let pageCount = PDFDocument(url: dest)?.pageCount ?? 0
        guard pageCount > 0 else {
            try? FileManager.default.removeItem(at: dest)
            message = "PDF 无法解析（可能已损坏）"
            return
        }

        let pdfBook = PDFBook(
            name: meta.title ?? fallbackName,
            author: meta.author ?? "未知作者",
            fileName: fileName,
            pageCount: pageCount
        )
        context.insert(pdfBook)
        do {
            try context.save()
        } catch {
            try? FileManager.default.removeItem(at: dest)
            message = "保存失败：\(error.localizedDescription)"
            return
        }
        message = "已导入《\(pdfBook.name)》，共 \(pageCount) 页"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { dismiss() }
    }
}