import Foundation
import Network

/// 应用内本地 HTTP 服务（127.0.0.1 随机端口）
///
/// 职责：
/// 1. 静态资源 —— Bundle 内 WebAssets/（EPUB/TXT 阅读内核，源自「纸阅」）
/// 2. 可写目录 —— Documents/books/…（外部书解包数据，随导入增长）
/// 3. /fetch   —— 书源引擎预留的网络代理（与 Minis 版 Python 桥同协议：
///    GET query 传参：url/method/headers/body/charset，CORS 全开）
///
/// 为什么用本地 HTTP 而不是 WKURLSchemeHandler：
/// 自定义 scheme 的源是不透明的，localStorage/IndexedDB 不可靠；
/// http://127.0.0.1 是真实源，Web 内核的存储行为与浏览器完全一致。
final class LocalServer {

    static let shared = LocalServer()

    // MARK: - 状态

    private var listener: NWListener?
    private let serverQueue = DispatchQueue(label: "legado.localserver")
    private(set) var port: UInt16 = 0

    private enum ServerError: LocalizedError {
        case startFailed
        var errorDescription: String? { "本地服务启动失败" }
    }

    // MARK: - 路径

    private var webRoot: URL {
        Bundle.main.url(forResource: "WebAssets", withExtension: nil)
            ?? (Bundle.main.resourceURL ?? URL(fileURLWithPath: "/"))
    }

    private var docsRoot: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    // MARK: - 启动

    /// 幂等启动，返回实际端口
    @discardableResult
    func start() async throws -> UInt16 {
        if port != 0 { return port }
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        params.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: .any)

        let listener = try NWListener(using: params)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] conn in
            self?.accept(conn)
        }
        listener.start(queue: serverQueue)

        // 等待端口分配（最多 ~2s）
        for _ in 0..<100 {
            if let p = listener.port?.rawValue, p != 0 {
                port = p
                return p
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        throw ServerError.startFailed
    }

    // MARK: - 连接处理

    private func accept(_ conn: NWConnection) {
        conn.start(queue: serverQueue)
        readRequest(conn, buffer: Data())
    }

    private func readRequest(_ conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, _, error in
            var buf = buffer
            if let data = data { buf.append(data) }

            if let req = Self.parseRequest(buf) {
                self.route(req, conn: conn)
            } else if error == nil && buf.count < (4 << 20) {
                self.readRequest(conn, buffer: buf)
            } else {
                self.sendRaw(
                    Data("HTTP/1.1 400 Bad Request\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8),
                    conn
                )
            }
        }
    }

    // MARK: - HTTP 解析

    fileprivate struct HTTPRequest {
        var method = "GET"
        var path = ""
        var query: [String: String] = [:]
        var headers: [String: String] = [:]   // key 已小写
        var body: Data?
    }

    /// 头部完整且 body（若有）收齐时返回请求，否则 nil（继续收）
    fileprivate static func parseRequest(_ data: Data) -> HTTPRequest? {
        guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let headerData = data[..<headerEnd.lowerBound]
        guard let headerText = String(data: headerData, encoding: .utf8) else { return nil }

        var req = HTTPRequest()
        var lines = headerText.components(separatedBy: "\r\n")
        guard !lines.isEmpty else { return nil }
        let parts = lines.removeFirst().split(separator: " ")
        guard parts.count >= 2 else { return nil }
        req.method = String(parts[0]).uppercased()

        let target = String(parts[1])
        if let qIdx = target.firstIndex(of: "?") {
            req.path = String(target[..<qIdx])
            let qs = String(target[(qIdx)...].dropFirst())
            if let comps = URLComponents(string: "/?" + qs) {
                for item in comps.queryItems ?? [] {
                    req.query[item.name] = item.value ?? ""
                }
            }
        } else {
            req.path = target
        }

        for line in lines {
            guard let idx = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<idx]).trimmingCharacters(in: .whitespaces).lowercased()
            let value = String(line[(line.index(after: idx))...]).trimmingCharacters(in: .whitespaces)
            req.headers[key] = value
        }

        let bodyStart = headerEnd.upperBound
        let contentLength = Int(req.headers["content-length"] ?? "0") ?? 0
        if contentLength > 0 {
            guard data.count - bodyStart >= contentLength else { return nil }
            req.body = data[bodyStart..<(bodyStart + contentLength)]
        } else if req.method == "POST", let transfer = req.headers["transfer-encoding"],
                  transfer.lowercased().contains("chunked") {
            // 简单处理：直接把剩余数据当 body
            req.body = data[bodyStart...]
        }
        return req
    }

    // MARK: - 路由

    private func route(_ req: HTTPRequest, conn: NWConnection) {
        let path = req.path
        logLine("\(req.method) \(path)")
        if req.method == "OPTIONS" {
            let head = "HTTP/1.1 204 No Content\r\n"
                + "Access-Control-Allow-Origin: *\r\n"
                + "Access-Control-Allow-Methods: GET, POST, OPTIONS\r\n"
                + "Access-Control-Allow-Headers: *\r\n"
                + "Access-Control-Max-Age: 86400\r\n"
                + "Content-Length: 0\r\n"
                + "Connection: close\r\n\r\n"
            sendRaw(Data(head.utf8), conn)
        } else if path == "/ping" {
            let body = Data("{\"ok\":true,\"app\":\"zhiyue\"}".utf8)
            sendJSONBody(body, status: 200, conn)
        } else if path == "/fetch" {
            proxy(req, conn)
        } else {
            serveStatic(path: path, conn: conn)
        }
    }

    // MARK: - /fetch 代理（Legado 引擎预留，同 Minis 桥协议）

    private func proxy(_ req: HTTPRequest, _ conn: NWConnection) {
        func fail(_ message: String, status: Int = 400) {
            let obj: [String: Any] = ["ok": false, "status": status, "error": message]
            let body = (try? JSONSerialization.data(withJSONObject: obj)) ?? Data()
            sendJSONBody(body, status: 200, conn)
        }

        guard let target = req.query["url"], let url = URL(string: target) else {
            fail("missing url"); return
        }

        var urlReq = URLRequest(url: url)
        urlReq.httpMethod = (req.query["method"] ?? "GET").uppercased()
        if urlReq.httpMethod == "GET" { urlReq.httpMethod = "GET" }

        if let headersJSON = req.query["headers"],
           let data = headersJSON.data(using: .utf8),
           let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: String] {
            for (k, v) in dict where !k.isEmpty {
                urlReq.setValue(v, forHTTPHeaderField: k)
            }
        }
        if urlReq.value(forHTTPHeaderField: "User-Agent") == nil {
            urlReq.setValue(
                "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) "
                    + "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
                forHTTPHeaderField: "User-Agent"
            )
        }
        // 请求方不做 gzip（代理方不做解压）
        urlReq.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        urlReq.timeoutInterval = 25
        if let body = req.query["body"], !body.isEmpty {
            urlReq.httpBody = Data(body.utf8)
        } else if let raw = req.body {
            urlReq.httpBody = raw
        }

        let sem = DispatchSemaphore(value: 0)
        var payload: Data?
        var status = 0
        var finalURL: String?
        var errorText: String?

        let task = URLSession.shared.dataTask(with: urlReq) { data, resp, error in
            if let error = error { errorText = error.localizedDescription }
            if let http = resp as? HTTPURLResponse { status = http.statusCode }
            payload = data
            finalURL = resp?.url?.absoluteString
            sem.signal()
        }
        task.resume()
        _ = sem.wait(timeout: .now() + 30)

        let bodyText: String
        if let payload = payload {
            bodyText = Self.decodeBody(payload, charsetName: req.query["charset"])
        } else {
            bodyText = ""
        }

        let obj: [String: Any] = [
            "ok": errorText == nil,
            "status": status,
            "finalUrl": finalURL ?? target,
            "body": bodyText,
            "error": errorText ?? "",
        ]
        let out = (try? JSONSerialization.data(withJSONObject: obj)) ?? Data()
        sendJSONBody(out, status: 200, conn)
    }

    /// charset 参数 → utf-8 → gb18030 → big5 → 宽松 utf-8
    static func decodeBody(_ data: Data, charsetName: String?) -> String {
        if let name = charsetName?.lowercased() {
            if name == "utf-8" || name == "utf8" {
                if let s = String(data: data, encoding: .utf8) { return s }
            } else if let enc = encodingFor(name) {
                if let s = String(data: data, encoding: enc) { return s }
            }
        }
        if let s = String(data: data, encoding: .utf8) { return s }
        // GB_18030_2000 = 0x0632, Big5 = 0x0A03, GBK = 0x0631
        for raw in [0x0632, 0x0A03] {
            let enc = String.Encoding(
                rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(raw))
            )
            if let s = String(data: data, encoding: enc) { return s }
        }
        return String(decoding: data, as: UTF8.self)
    }

    private static func encodingFor(_ name: String) -> String.Encoding? {
        switch name {
        case "gbk", "gb2312", "gb18030":
            return String.Encoding(
                rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(0x0632))
            )
        case "big5":
            return String.Encoding(
                rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(0x0A03))
            )
        default:
            return nil
        }
    }

    // MARK: - 静态资源

    private let mimeTypes: [String: String] = [
        "html": "text/html; charset=utf-8",
        "js": "application/javascript; charset=utf-8",
        "css": "text/css; charset=utf-8",
        "json": "application/json; charset=utf-8",
        "txt": "text/plain; charset=utf-8",
        "xhtml": "application/xhtml+xml",
        "xml": "application/xml",
        "opf": "application/oebps-package+xml",
        "ncx": "application/x-dtbncx+xml",
        "svg": "image/svg+xml",
        "jpg": "image/jpeg", "jpeg": "image/jpeg",
        "png": "image/png", "gif": "image/gif", "webp": "image/webp",
        "woff": "font/woff", "woff2": "font/woff2", "ttf": "font/ttf",
        "epub": "application/epub+zip",
    ]

    private func serveStatic(path rawPath: String, conn: NWConnection) {
        // 规范化：去前导 /，拒绝 ..
        let decoded = rawPath.removingPercentEncoding ?? rawPath
        let comps = decoded.split(separator: "/").map(String.init).filter { $0 != ".." && $0 != "." }
        guard !comps.isEmpty else {
            // 根路径 → index.html
            sendFile(webRoot.appendingPathComponent("index.html"), conn)
            return
        }

        let fileURL: URL
        if comps[0] == "books" {
            // 可写目录：Documents/books/…
            fileURL = docsRoot.appendingPathComponents(["books"] + Array(comps.dropFirst()))
        } else {
            fileURL = webRoot.appendingPathComponents(comps)
        }

        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDir) {
            if isDir.boolValue {
                sendFile(fileURL.appendingPathComponent("index.html"), conn)
            } else {
                sendFile(fileURL, conn)
            }
        } else {
            let body = Data("{\"error\":\"not found\",\"path\":\"\(decoded)\"}".utf8)
            sendJSONBody(body, status: 404, conn)
        }
    }

    // MARK: - 响应发送

    private func statusText(_ code: Int) -> String {
        switch code {
        case 200: return "OK"
        case 404: return "Not Found"
        default: return "OK"
        }
    }

    private func sendJSONBody(_ body: Data, status: Int, _ conn: NWConnection) {
        let head = "HTTP/1.1 \(status) \(statusText(status))\r\n"
            + "Content-Type: application/json; charset=utf-8\r\n"
            + "Content-Length: \(body.count)\r\n"
            + "Access-Control-Allow-Origin: *\r\n"
            + "Access-Control-Allow-Methods: GET, POST, OPTIONS\r\n"
            + "Access-Control-Allow-Headers: *\r\n"
            + "Cache-Control: no-store\r\n"
            + "Connection: close\r\n\r\n"
        sendRaw(Data(head.utf8) + body, conn)
    }

    private func sendFile(_ fileURL: URL, _ conn: NWConnection) {
        let ext = fileURL.pathExtension.lowercased()
        let mime = mimeTypes[ext] ?? "application/octet-stream"
        let size = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int) ?? 0

        guard size > 0, let handle = try? FileHandle(forReadingFrom: fileURL) else {
            sendJSONBody(
                Data("{\"error\":\"not found\",\"path\":\"\(fileURL.lastPathComponent)\"}".utf8),
                status: 404, conn
            )
            logLine("404 \(fileURL.lastPathComponent)")
            return
        }

        // 常规文件（≤16MB）：整读后 头+体 一次性交给 NWConnection，
        // cancel 只在 .contentProcessed（数据全部送达）之后触发。
        // 旧实现头部走 sendRaw，其完成回调里的 cancel 会与正文分块发送竞态，
        // 大文件正文被掐断（jszip/epub.js 加载失败的根因）。
        let head = "HTTP/1.1 200 OK\r\n"
            + "Content-Type: \(mime)\r\n"
            + "Content-Length: \(size)\r\n"
            + "Access-Control-Allow-Origin: *\r\n"
            + "Cache-Control: no-store\r\n"
            + "Connection: close\r\n\r\n"

        if size <= (16 << 20), let body = try? handle.readToEnd() {
            try? handle.close()
            sendRaw(Data(head.utf8) + body, conn)
            logLine("200 \(fileURL.lastPathComponent) \(body.count)B")
            return
        }

        // 超大文件：头先发（不带 cancel），分块链式发送，全部完成后才取消连接
        let queue = serverQueue
        let chunkSize = 256 * 1024
        func sendNext() {
            let chunk = (try? handle.read(upToCount: chunkSize)) ?? Data()
            if chunk.isEmpty {
                try? handle.close()
                conn.cancel()
                logLine("200 \(fileURL.lastPathComponent) \(size)B (streamed)")
                return
            }
            conn.send(content: chunk, completion: .contentProcessed { _ in
                queue.async(execute: sendNext)
            })
        }
        conn.send(content: Data(head.utf8), completion: .contentProcessed { _ in
            queue.async(execute: sendNext)
        })
    }

    private func sendRaw(_ data: Data, _ conn: NWConnection) {
        conn.send(content: data, completion: .contentProcessed { _ in
            conn.cancel()
        })
    }

    // MARK: - 日志（Documents/server.log，App 的「文件」共享里可直接查看）

    private func logLine(_ line: String) {
        let text = ISO8601DateFormatter().string(from: Date()) + " " + line + "\n"
        let url = docsRoot.appendingPathComponent("server.log")
        if let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, size > 512 * 1024 {
            try? FileManager.default.removeItem(at: url)
        }
        if let h = try? FileHandle(forWritingTo: url) {
            _ = try? h.seekToEnd()
            try? h.write(Data(text.utf8))
            try? h.close()
        } else {
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    /// 供 WebView 桥转发页面 JS 错误（线程安全入口）
    func logWeb(_ line: String) {
        serverQueue.async { self.logLine("JS " + line) }
    }
}

private extension URL {
    func appendingPathComponents(_ comps: [String]) -> URL {
        comps.reduce(self) { $0.appendingPathComponent($1) }
    }
}
