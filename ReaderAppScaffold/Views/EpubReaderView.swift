import SwiftUI

/// EPUB/TXT 阅读器（Web 内核，源自「纸阅」）
///
/// 架构：应用内本地 HTTP 服务（LocalServer）+ WKWebView。
/// 页面从 http://127.0.0.1:<port>/index.html 加载，因此：
/// - 图书与进度存在 IndexedDB / localStorage（真实源，持久化可靠）；
/// - 导入走 HTML `<input type="file">` —— WebKit 自带系统文件选择器，
///   不经过 SwiftUI 呈现链，天然可靠（这也是它能直接导入的原因）；
/// - 支持 EPUB 与 TXT，阅读器带目录/字号/主题/进度/书内搜索/高亮笔记。
struct EpubReaderView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var appURL: URL?
    @State private var failed = false

    var body: some View {
        NavigationStack {
            Group {
                if let url = appURL {
                    ReaderWebView(url: url)
                        .ignoresSafeArea()
                } else if failed {
                    VStack(spacing: 18) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 44))
                            .foregroundStyle(.secondary)
                        Text("本地服务启动失败，请退出应用后重试")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ProgressView("启动阅读服务…")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .task { await boot() }
    }

    private func boot() async {
        do {
            let port = try await LocalServer.shared.start()
            appURL = URL(string: "http://127.0.0.1:\(port)/index.html")
        } catch {
            failed = true
        }
    }
}

#Preview {
    EpubReaderView()
}
