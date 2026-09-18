# LegadoRuleEngine (Swift)

legado (阅读) 书源规则引擎的 Swift 移植版，源码逐文件对照
`app/src/main/java/io/legado/app/model/analyzeRule/` 下的 Kotlin 实现改写而成。

## 已移植（可用）

| Swift 文件 | 对应 Kotlin 源文件 | 说明 |
|---|---|---|
| `RuleAnalyzer.swift` | `RuleAnalyzer.kt` | 规则字符串通用切分器（&&/\|\|/%%、[]()平衡组、{}内嵌规则）。纯 Foundation，无三方依赖，逻辑**逐行对照**移植。 |
| `AnalyzeByRegex.swift` | `AnalyzeByRegex.kt` | 正则规则解析（":"开头的 AllInOne 规则）。基于 `NSRegularExpression`。 |
| `MiniJSONPath.swift` + `AnalyzeByJSonPath.swift` | `AnalyzeByJSonPath.kt` | JSONPath 规则解析。**自实现的轻量 JSONPath**（无直接对应的 Swift 官方库），支持 `$.a.b`、`[0]`、`[*]`、`[1:3]`、`[0,2]`、`..key` 等常用子集，**不支持过滤表达式** `?(@.x>1)`。 |
| `AnalyzeByJSoup.swift` | `AnalyzeByJSoup.kt` | CSS 规则解析，含阅读特有的索引选择器语法（`tag.div.-1:10:2`、`tag.div[-1,3:-2:-10,2]` 等）。基于 [SwiftSoup](https://github.com/scinfu/SwiftSoup)。 |
| `AnalyzeRule.swift` + `SourceRule.swift` | `AnalyzeRule.kt` | 总调度器：识别 `@css:`/`@xpath:`/`@json:`/`@@`/`/`(xpath)/JSON自动识别 等前缀，拆分 `@put:{}`、`@get:{}`、`{{js}}`、`$1$2`正则组、末尾 `##正则##替换##` 后缀；JS 执行基于 `JavaScriptCore`；变量存取（put/get）。 |

## 已移植（第二批）

| Swift 文件 | 对应 Kotlin 源文件 | 说明 |
|---|---|---|
| `AnalyzeUrl.swift` | `AnalyzeUrl.kt` | URL 规则解析 + 网络请求执行。URL语法解析部分（`<js>`/`@js:`嵌入、`{{js}}`、`<page1,page2>`分页、`url,{urlOption json}`后缀、query/form编码）**逐段对照移植**；网络执行部分改用 `URLSession` + `async/await` 重写（原版是 OkHttp），行为对齐但非逐行翻译。 |

`AnalyzeUrl` 目前独立于 `AnalyzeRule`，两者通过你自己的胶水代码串起来：先用 `AnalyzeUrl` 把书源里的 url 规则解析成真实请求并拿到响应文本，再把响应文本喂给 `AnalyzeRule.setContent(_:baseUrl:)` 继续解析列表/详情/正文规则。

## 未移植 / 需要你补充

1. **AnalyzeByXPath**：原版依赖 Java 的 JXPath 库，Swift 没有直接对应实现。当前 `AnalyzeRule` 里命中 `Mode.xpath` 会打印一次警告并返回空结果。多数书源规则以 CSS 为主，XPath 占比小；如果你的书源大量用到 XPath，建议用 `libxml2`（iOS 系统自带）的 `xmlXPathEvalExpression` 单独实现一个 `AnalyzeByXPath.swift`，接口对齐现有的 `getString/getStringList/getElements`。

2. **AnalyzeUrl 里未覆盖的部分**：WebView渲染取值（`useWebView`/`webJs`，需通过 `webViewEvaluator` 注入 `WKWebView` 实现）、自定义DNS(`dnsIp`，已解析出来但当前不生效)、代理(`proxy`，同样已解析但不生效)。Cookie 用了简化的内存版 `InMemoryCookieStore`，生产环境建议换成持久化实现（替换 `AnalyzeUrl.cookieStore` 静态属性）。并发限流 `SourceRateLimiter` 支持按 `"count/毫秒"` 的时间窗口限流（也兼容纯数字形式退化成"只限并发数"），语义等价但非逐行移植（原版 `ConcurrentRateLimiter.kt` 源码不在本次输入范围内），`BookSourceRuntime` 已经接进去了，每次请求前会按对应书源的 `concurrentRate` 过一遍。

3. **@webJs: 规则**：依赖真实 WebView 渲染执行 JS 后取值（原版用 `BackstageWebView`）。这里留了 `AnalyzeRule.webJsEvaluator` 注入点，你需要用 `WKWebView` 实现一版（加载 HTML、注入 JS、取执行结果）。

4. **JS 里的 java.xxx() 扩展方法**：原版 `JsExtensions` 有几十个方法，这里 `LegadoJSBridge`/`AnalyzeUrlJSBridge` 已经实现了一批常用的：`put/get/log/ajax/ajaxAll`、`base64Encode/base64Decode/base64DecodeToByteArray/hexDecodeToString`、`timeFormat`、`toast/longToast`、`androidId/deviceID/getWebViewUA`（iOS 的 `deviceID` 只有宿主注入系统 `identifierForVendor` 后才返回；未取得时为空，绝不发送伪造设备码）、`createSymmetricCrypto`(支持AES/DES/3DES，CBC/ECB，PKCS7填充，用CommonCrypto实现，`.encryptBase64()/.decryptStr()`等方法齐全)。还有一批需要真实App UI才有意义的（`open/showBrowser/startBrowser*`打开应用内浏览器、`refreshExplore`刷新发现页、`searchBook`触发App内搜索）做成了弱化实现——调用不会报错，但要接进真实交互得通过 `AnalyzeRule`/`AnalyzeUrl`/`BookSourceRuntime` 上的 `browserOpener`/`refreshExploreHandler`/`searchBookHandler`/`toastHandler` 这些闭包注入你自己的实现。`qread()`固定返回`"0"`（表示不是QQ阅读兼容壳，多数书源这个判断走不到什么特殊分支）。

5. **书源公共JS库(jsLib)和 `this.source`/`this.cookie` 绑定**：`BookSource.jsLib` 字段（复杂书源常见，定义一堆公共辅助函数）现在会在每次 `evalJS` 前自动跑一遍，规则脚本能直接调用里面的函数；JS里 `this.source.getVariable()/setVariable()/getLoginHeader()/getLoginInfoMap()`（书源级别的持久变量+登录信息，和单本书的变量是两回事）和 `this.cookie.getCookie()/setCookie()` 也都接上了——不过 `source` 的持久变量默认没有真实存储后端（`AnalyzeRule.sourceContext`/`AnalyzeUrl.sourceContext` 不注入的话读写都是空转），要接真实持久化需要你自己实现 `SourceJSContext` 协议并注入（比如让 App 里的 `BookSourceRecord` 顶一个字段存起来）。`header` 字段如果是 `@js:`/`<js>` 动态脚本（不少书源靠这个算签名/伪装UA），`BookSourceRuntime.resolveHeaderMap()` 现在会真的执行一遍JS而不是直接当JSON解析失败返回空。

5. **SwiftSoup API 版本差异**：`AnalyzeByJSoup.swift` 里调用的 `select/getElementsByClass/getElementsByTag/getElementById/getElementsContainingOwnText/textNodes/outerHtml` 等方法名是按目前主流 SwiftSoup 版本写的，个别方法的 `throws` 标注在不同版本间可能有出入。真机编译时如果报"多余的 try"或"缺少 try"，照编译器提示改一下即可，属于版本差异，不是逻辑问题。

## 集成方式

1. 用 Xcode 新建/打开你的 iOS 工程。
2. File → Add Package Dependencies，把这个 `LegadoRuleEngine` 文件夹拖进工程作为本地 Swift Package（或直接把 `Sources/LegadoRuleEngine` 下的 .swift 文件拖进主工程，然后单独用 SPM 添加 SwiftSoup 依赖）。
3. `import LegadoRuleEngine`，参考下面示例调用。

## 示例

```swift
import LegadoRuleEngine

// 1. CSS 规则示例：解析搜索结果列表
let html = """
<div class="book-list">
  <div class="item"><a class="name" href="/book/1">凡人修仙传</a><span class="author">忘语</span></div>
  <div class="item"><a class="name" href="/book/2">诡秘之主</a><span class="author">爱潜水的乌贼</span></div>
</div>
"""
let rule = AnalyzeRule()
rule.setContent(html, baseUrl: "https://example.com")

let items = rule.getElements(".book-list .item")
for item in items {
    let name = rule.getString("class.name@text", mContent: item)
    let author = rule.getString("class.author@text", mContent: item)
    let url = rule.getString("class.name@href", mContent: item, isUrl: true)
    print(name, author, url)
}

// 2. JSON 规则示例
let json = #"{"data":{"list":[{"title":"书名A"},{"title":"书名B"}]}}"#
let jsonRule = AnalyzeRule()
jsonRule.setContent(json)
let titles = jsonRule.getStringList("$.data.list[*].title")
print(titles as Any) // ["书名A", "书名B"]

// 3. 正则替换后缀示例：取文本后再做一次正则替换
let text = rule.getString("class.name@text##凡人##FANREN##")

// 4. AnalyzeUrl 示例：解析url规则 -> 发起请求 -> 结果喂给 AnalyzeRule 继续解析
Task {
    let au = AnalyzeUrl(url: "https://example.com/search?wd=凡人修仙传", key: "凡人修仙传")
    do {
        let resp = try await au.getStrResponse()
        let rule = AnalyzeRule()
        rule.setContent(resp.body ?? "", baseUrl: au.url)
        let items = rule.getElements(".book-list .item")
        print("共\(items.count)条结果")
    } catch {
        print("请求失败: \(error)")
    }
}
```

## 已知与原版的行为差异（有意简化）

- `getAnalyzeByJSoup(o)` / `getAnalyzeByJSonPath(o)` 原版有"若 o 与当前 content 是同一对象则复用缓存实例"的性能优化，Swift 版为了避免引用相等性判断的复杂度，简化成每次都新建一个解析实例，只影响性能不影响正确性。
- HTML 实体反转义 (`&amp;` 等) 用了 `NSAttributedString(html:)`，在大内容/高频调用场景性能一般，需要的话可以换成手写的实体表替换。
- 绝对 URL 拼接用了 `URL(string:relativeTo:)`，覆盖了常见相对路径场景，但没有对齐原版 `NetworkUtils.getAbsoluteURL` 里所有边界情况（如协议相对 `//host/path`），如果发现拼接不对可以针对性补丁。

## 已移植（第三批，收尾）

| Swift 文件 | 对应 Kotlin/Java 源文件 | 说明 |
|---|---|---|
| `CustomUrl.swift` | `CustomUrl.kt` | `"url,{attr json}"` 格式的自定义地址封装，逐行移植。 |
| `RuleData.swift` | `RuleData.kt` | `RuleDataInterface` 的通用默认实现。 |
| `QueryTTF.swift` | `QueryTTF.java` | **TTF字体解析**，破解书源正文的"自定义字体反爬"。逐字段对照移植（文件头/目录表/head/cmap(format 0,4,6)/loca/maxp/glyf简单与复合字形），字节读取按大端序手写，不依赖任何第三方库。⚠️ 复合字形的浮点缩放值转字符串在 Java/Swift 间可能有极小的精度表示差异，简单字形（绝大多数汉字走这条路径）不受影响，细节见文件顶部注释。 |

`Tests/` 里补了 `testQueryTTFParsesMinimalFont`，手工拼了一个最小合法TTF二进制（只含 head/cmap/loca/maxp/glyf 五张表），验证了字节读取器、表偏移定位、cmap format0解析、简单字形坐标解析这条完整链路，这是这次移植里风险最高（二进制格式，无法离线编译验证）的部分，建议接入真实带自定义字体的书源实测一遍。

## 目前还剩什么

对照最初 legado 源码里 `model/analyzeRule/` 目录，这次基本全覆盖了（RuleAnalyzer/AnalyzeByRegex/AnalyzeByJSonPath/AnalyzeByJSoup/AnalyzeRule/SourceRule/AnalyzeUrl/CustomUrl/RuleData/QueryTTF）。规则引擎本身可以认为是完整的。真正要把"能跑起来的阅读App"拼起来，还缺的是引擎之外的东西：书源JSON模型（BookSource/SearchRule/BookInfoRule等数据结构）、书籍/章节数据模型与本地持久化、目录页翻页与并发抓取调度、阅读器UI（分页排版/主题/手势）、TTS播放。这些和"规则引擎"是两层不同的东西，等你规划到这一步了再继续对照移植。

## 已新增：书源数据模型 + 搜索/目录/正文 胶水层

| Swift 文件 | 对应 | 说明 |
|---|---|---|
| `BookSource.swift` | `data/entities/BookSource.kt` + `data/entities/rule/*.kt` | 书源 JSON 的数据模型，字段名和 legado 原版 JSON key 完全一致，可以直接 `BookSourceImporter.parse(jsonString)` 导入现成的书源文件（单个对象或数组都支持）。个别书源文件里 `ruleXxx` 字段被整体编码成字符串而不是JSON对象的情况也兼容处理了。 |
| `BookSourceRuntime.swift` | 无直接对应（legado这部分逻辑在 `WebBook.kt` 等协程任务类里，和UI/数据库耦合较深）| 把 `BookSource` + `AnalyzeUrl` + `AnalyzeRule` 串起来的胶水层，`search()`/`getToc()`/`getContent()` 三个async方法直接可用，目录和正文都会自动翻页。当参考实现来看，生产用之前建议按 `BookSourceRuntime.swift` 文件头注释里列的几点自己补一下（并发限流、详情页解析、缓存）。 |

```swift
// 端到端示例：导入书源 -> 搜索 -> 拿目录 -> 拿正文
let json = try String(contentsOf: bookSourceFileURL, encoding: .utf8)
let sources = try BookSourceImporter.parse(json)
let runtime = BookSourceRuntime(sources[0])

let results = try await runtime.search("凡人修仙传")
if let first = results.first {
    let chapters = try await runtime.getToc(bookUrl: first.bookUrl)
    if let firstChapter = chapters.first {
        let content = try await runtime.getContent(chapterUrl: firstChapter.url)
        print(content)
    }
}
```
