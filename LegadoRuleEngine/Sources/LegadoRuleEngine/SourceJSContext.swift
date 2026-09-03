import Foundation
import JavaScriptCore

/// 对应书源规则JS里 `this.source` —— 很多复杂书源(尤其"聚合"类)的共享脚本(jsLib)
/// 会用 `let { source } = this; source.getVariable()/setVariable()` 读写"书源级别的持久变量"
/// （和 `RuleDataInterface.variableMap` 不是一回事：那个是单本书/单章节的变量，这个是整个
/// 书源自己的配置存储，比如用户在聚合书源里选的"服务器/性别"选项）。
/// 这块存储天然需要持久化(数据库/文件)，`LegadoRuleEngine` 本身不管持久化，所以设计成协议，
/// 由调用方（比如 App 里的 `BookSourceRecord`）实现后注入进来；不注入的话相关JS调用会拿到空值，
/// 不会崩，只是那部分"记住配置"的功能不生效。
public protocol SourceJSContext: AnyObject {
    func getVariable() -> String
    func setVariable(_ value: String)
    /// 对应 source.getLoginHeader() —— 登录后要在后续请求头里带的鉴权信息
    func getLoginHeader() -> String?
    /// 对应 source.putLoginHeader(value) —— 登录成功后把鉴权串写回持久层
    func putLoginHeader(_ value: String)
    /// 对应 source.getLoginInfoMap() —— 登录表单填的各字段（账号/密码/自定义字段等）
    func getLoginInfoMap() -> [String: String]
    /// 对应 source.putLoginInfo(jsonString) —— 把整张表单序列化回写到持久层
    func putLoginInfo(_ json: String)
}

@objc protocol SourceJSBridgeExport: JSExport {
    func getVariable() -> String
    func setVariable(_ value: String)
    func getLoginHeader() -> String
    func putLoginHeader(_ value: String) -> String
    func getLoginInfoMap() -> [String: String]
    func putLoginInfo(_ value: String) -> String
    func getLoginInfo() -> String
    func getKey() -> String
}

@objc final class SourceJSBridge: NSObject, SourceJSBridgeExport {
    weak var context: SourceJSContext?
    var sourceKey: String = ""
    init(_ context: SourceJSContext?, sourceKey: String = "") {
        self.context = context
        self.sourceKey = sourceKey
    }

    func getVariable() -> String { context?.getVariable() ?? "" }
    func setVariable(_ value: String) { context?.setVariable(value) }
    func getLoginHeader() -> String { context?.getLoginHeader() ?? "" }
    func putLoginHeader(_ value: String) -> String {
        context?.putLoginHeader(value); return ""
    }
    func getLoginInfoMap() -> [String: String] { context?.getLoginInfoMap() ?? [:] }
    /// 旧版 legado 是 putLoginInfo(obj)；JS 端传的是对象不是 JSON 字符串
    /// 这里两个签名都接受，便于不同书源
    func putLoginInfo(_ value: String) -> String {
        context?.putLoginInfo(value); return ""
    }
    func getLoginInfo() -> String {
        if let info = context?.getLoginInfoMap() {
            if let data = try? JSONSerialization.data(withJSONObject: info),
               let s = String(data: data, encoding: .utf8) { return s }
        }
        return ""
    }
    func getKey() -> String { sourceKey }
}

@objc protocol CookieJSBridgeExport: JSExport {
    func getCookie(_ domain: String) -> String
    func setCookie(_ domain: String, _ cookie: String)
}

/// 对应 `this.cookie` —— 读写 `AnalyzeUrl.cookieStore`（同一个进程内所有书源共用的cookie存储）
@objc final class CookieJSBridge: NSObject, CookieJSBridgeExport {
    func getCookie(_ domain: String) -> String { AnalyzeUrl.cookieStore.getCookie(domain) }
    func setCookie(_ domain: String, _ cookie: String) { AnalyzeUrl.cookieStore.setCookie(domain, cookie) }
}

// MARK: - java.post / java.ajax 返回的响应对象

@objc public protocol JSStrResponseExport: JSExport {
    func body() -> String
    func url() -> String
}

@objc public final class JSStrResponse: NSObject, JSStrResponseExport {
    private let bodyText: String
    private let urlText: String
    public init(body: String, url: String) {
        self.bodyText = body
        self.urlText = url
    }
    public func body() -> String { bodyText }
    public func url() -> String { urlText }
}
