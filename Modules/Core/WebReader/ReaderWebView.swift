import SwiftUI
import WebKit

/// 承载 Web 阅读内核的 WKWebView（源自「纸阅」）
/// 页面地址为 http://127.0.0.1:<port>（本地服务的真实 HTTP 源），
/// 因此 localStorage / IndexedDB 等持久化能力与浏览器一致。
struct ReaderWebView: UIViewRepresentable {
    let url: URL

    /// 全局引用，Phase 2 的原生桥（WKScriptMessageHandler）将挂到这里
    static weak var current: WKWebView?

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// 把页面里的脚本加载失败 / 运行时错误转发给 LocalServer 写入 server.log
    class Coordinator: NSObject, WKScriptMessageHandler {
        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            if let text = message.body as? String, !text.isEmpty {
                LocalServer.shared.logWeb(text)
            }
        }
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let prefs = WKPreferences()
        prefs.javaScriptCanOpenWindowsAutomatically = false
        config.preferences = prefs

        // 错误桥：必须在文档开始时注入，才能抓到 <script> 资源加载失败
        config.userContentController.addUserScript(
            WKUserScript(
                source: Self.errorBridgeScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )
        config.userContentController.add(context.coordinator, name: "zyConsole")

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.isOpaque = false
        wv.backgroundColor = .systemBackground
        wv.scrollView.bounces = false
        // 网页自身用 viewport-fit=cover + env(safe-area-inset-*) 处理刘海
        wv.scrollView.contentInsetAdjustmentBehavior = .never

        let request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 30
        )
        wv.load(request)
        ReaderWebView.current = wv
        return wv
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    /// 注入到页面的错误采集脚本（capture 阶段的 error 事件可捕获资源加载失败）
    static let errorBridgeScript = """
    (function () {
        function send(t) {
            try { window.webkit.messageHandlers.zyConsole.postMessage(String(t)); } catch (e) {}
        }
        window.addEventListener('error', function (e) {
            var t = e.target;
            if (t && (t.src || t.href)) {
                send('load-fail ' + (t.src || t.href));
            } else {
                send('error ' + e.message + ' @' + (e.filename || '') + ':' + e.lineno);
            }
        }, true);
        window.addEventListener('unhandledrejection', function (e) {
            send('promise ' + e.reason);
        });
        var origError = console.error ? console.error.bind(console) : null;
        console.error = function () {
            var a = Array.prototype.map.call(arguments, function (x) {
                try { return typeof x === 'object' ? JSON.stringify(x) : String(x); }
                catch (err) { return '[object]'; }
            });
            send('console.error ' + a.join(' '));
            if (origError) origError.apply(null, arguments);
        };
    })();
    """
}
