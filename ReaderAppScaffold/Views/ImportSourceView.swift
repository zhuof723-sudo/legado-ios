import SwiftUI
import SwiftData
import UniformTypeIdentifiers

public struct ImportSourceView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var jsonText = ""
    @State private var resultMessage: String?
    @State private var isPicking = false

    public init() {}

    public var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                TextEditor(text: $jsonText)
                    .font(.system(.footnote, design: .monospaced))
                    .frame(minHeight: 220)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator))

                Button {
                    pickFile()
                } label: {
                    Label("从文件导入(.json)", systemImage: "doc.badge.plus")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .plainGlassButton()
                .tint(Theme.accent)
                .disabled(isPicking)

                if let resultMessage {
                    Text(resultMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
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
        }
    }

    /// 直接用 UIKit 的选择器呈现（见 DocumentPicker.swift 里关于
    /// `.fileImporter` 在 sheet 内静默失效的说明）。
    private func pickFile() {
        isPicking = true
        resultMessage = nil
        FilePicker.present(contentTypes: [.json, .text, .data]) { result in
            isPicking = false
            switch result {
            case .success(let urls):
                guard let url = urls.first else {
                    resultMessage = "没有选择文件"
                    return
                }
                loadSourceFile(url)
            case .failure(let error):
                // 用户主动取消不算错误，不打扰
                if (error as? FilePicker.PickerError) == .cancelled { return }
                resultMessage = "打开文件选择器失败：\(error.localizedDescription)"
            }
        }
    }

    private func loadSourceFile(_ url: URL) {
        // asCopy 已把文件复制到临时目录，理论上无需安全作用域；
        // 仍按规范调用一次，但返回 false 也继续读（不再静默跳过）。
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        do {
            let text = try FileTextReader.readText(from: url)
            // 回填输入框：即使解析失败，用户也能看到内容并手动修
            jsonText = text
            doImport(text)
        } catch {
            resultMessage = error.localizedDescription
        }
    }

    private func doImport(_ text: String) {
        let store = BookSourceStore(context: context)
        let count = store.importSources(from: text)
        if let err = store.errorMessage {
            resultMessage = "导入失败：\(err)"
        } else if count == 0 {
            resultMessage = "没有解析出任何书源（请确认是 legado 书源 JSON）"
        } else {
            if store.skippedCount > 0 {
                resultMessage = "成功导入 \(count) 个书源，跳过 \(store.skippedCount) 个（缺少 bookSourceUrl）"
            } else {
                resultMessage = "成功导入 \(count) 个书源"
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { dismiss() }
        }
    }
}
