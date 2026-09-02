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
    /// 对应 source.getLoginInfoMap() —— 登录表单填的各字段（账号/密码/自定义字段等）
    func getLoginInfoMap() -> [String: String]
}

@objc protocol SourceJSBridgeExport: JSExport {
    func getVariable() -> String
    func setVariable(_ value: String)
    func getLoginHeader() -> String
    func getLoginInfoMap() -> [String: String]
}

@objc final class SourceJSBridge: NSObject, SourceJSBridgeExport {
    weak var context: SourceJSContext?
    init(_ context: SourceJSContext?) { self.context = context }

    func getVariable() -> String { context?.getVariable() ?? "" }
    func setVariable(_ value: String) { context?.setVariable(value) }
    func getLoginHeader() -> String { context?.getLoginHeader() ?? "" }
    func getLoginInfoMap() -> [String: String] { context?.getLoginInfoMap() ?? [:] }
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
