import SwiftUI
import WebKit
import Combine

struct BrowserDestination: Identifiable {
    let id = UUID()
    let url: URL
    let title: String
    let injectedJavaScript: String?

    init(url: URL, title: String? = nil, injectedJavaScript: String? = nil) {
        self.url = url
        self.title = title?.isEmpty == false ? title! : (url.host ?? "浏览器")
        self.injectedJavaScript = injectedJavaScript
    }

    init?(urlString: String, title: String? = nil, injectedJavaScript: String? = nil) {
        guard let url = URL(string: urlString),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" || scheme == "data" else { return nil }
        self.init(url: url, title: title, injectedJavaScript: injectedJavaScript)
    }
}

final class InAppBrowserModel: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    @Published var isLoading = false
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var pageTitle = ""
    @Published var currentURL: URL?

    weak var webView: WKWebView?

    func attach(_ webView: WKWebView) {
        self.webView = webView
        updateState(webView)
    }

    func goBack() { webView?.goBack() }
    func goForward() { webView?.goForward() }
    func reload() { webView?.reload() }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        isLoading = true
        updateState(webView)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoading = false
        updateState(webView)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        isLoading = false
        updateState(webView)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        isLoading = false
        updateState(webView)
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if navigationAction.targetFrame == nil, let requestURL = navigationAction.request.url {
            webView.load(URLRequest(url: requestURL))
        }
        return nil
    }

    private func updateState(_ webView: WKWebView) {
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        pageTitle = webView.title ?? ""
        currentURL = webView.url
    }
}

private struct BrowserWebView: UIViewRepresentable {
    let destination: BrowserDestination
    @ObservedObject var model: InAppBrowserModel

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        if let js = destination.injectedJavaScript, !js.isEmpty {
            configuration.userContentController.addUserScript(
                WKUserScript(source: js, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
            )
        }
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = model
        webView.uiDelegate = model
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .automatic
        model.attach(webView)
        webView.load(URLRequest(url: destination.url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 30))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}
}

struct InAppBrowserView: View {
    @Environment(\.dismiss) private var dismiss
    let destination: BrowserDestination
    @StateObject private var model = InAppBrowserModel()

    var body: some View {
        NavigationStack {
            BrowserWebView(destination: destination, model: model)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(model.pageTitle.isEmpty ? destination.title : model.pageTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                        }
                        .accessibilityLabel("关闭")
                    }
                    ToolbarItemGroup(placement: .primaryAction) {
                        if model.isLoading { ProgressView().controlSize(.small) }
                        ShareLink(item: model.currentURL ?? destination.url) {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    HStack {
                        Button { model.goBack() } label: { Image(systemName: "chevron.left") }
                            .disabled(!model.canGoBack)
                        Spacer()
                        Button { model.goForward() } label: { Image(systemName: "chevron.right") }
                            .disabled(!model.canGoForward)
                        Spacer()
                        Button { model.reload() } label: { Image(systemName: "arrow.clockwise") }
                        Spacer()
                        Text(model.currentURL?.host ?? destination.url.host ?? "")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .font(.system(size: 18, weight: .medium))
                    .padding(.horizontal, 24)
                    .frame(height: 48)
                    .background(.regularMaterial)
                }
        }
    }
}
