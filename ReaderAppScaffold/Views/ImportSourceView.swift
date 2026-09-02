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
            .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.json]) { result in
                switch result {
                case .success(let url):
                    if url.startAccessingSecurityScopedResource() {
                        defer { url.stopAccessingSecurityScopedResource() }
                        if let text = try? String(contentsOf: url, encoding: .utf8) {
                            doImport(text)
                        }
                    }
                case .failure(let error):
                    resultMessage = "读取文件失败: \(error.localizedDescription)"
                }
            }
        }
    }

    private func doImport(_ text: String) {
        let store = BookSourceStore(context: context)
        let count = store.importSources(from: text)
        if let err = store.errorMessage {
            resultMessage = err
        } else {
            resultMessage = "成功导入 \(count) 个书源"
            if count > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { dismiss() }
            }
        }
    }
}
