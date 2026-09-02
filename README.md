# legado-ios（暂定名，改成你喜欢的）

参照 [legado(阅读)](https://github.com/gedoor/legado) 的书源规则引擎，从 Kotlin 逐文件对照移植到 Swift，
外加一个基于此引擎的最小可用 SwiftUI 阅读App骨架。

## 目录结构

```
.
├── LegadoRuleEngine/     Swift Package：书源规则引擎本体（可独立复用，不依赖UI）
└── ReaderAppScaffold/    SwiftUI App骨架源码（依赖 LegadoRuleEngine）
```

## LegadoRuleEngine

规则解析（CSS/JSON/正则/JS）+ URL规则解析 + 网络请求 + 书源JSON数据模型 + TTF字体反爬解密。
详见 [LegadoRuleEngine/README.md](./LegadoRuleEngine/README.md)。

作为 Swift Package 使用：

```swift
dependencies: [
    .package(path: "../LegadoRuleEngine")
    // 或者发布后: .package(url: "https://github.com/你的用户名/仓库名.git", from: "0.1.0")
]
```

## ReaderAppScaffold

基于 LegadoRuleEngine 的 SwiftUI 参考实现：书源管理、跨书源搜索、书架、CoreText真分页阅读器。
详见 [ReaderAppScaffold/README.md](./ReaderAppScaffold/README.md)。

这部分是**源码文件**，不是独立的Xcode工程，接入步骤见其README。

## 状态 / 免责声明

- 规则引擎部分有单元测试覆盖核心路径（`LegadoRuleEngine/Tests/`），但**没有经过真实设备编译验证**（这里没有Swift工具链），接入Xcode后如果遇到编译错误，大概率是SwiftSoup等三方库API版本差异，对照报错信息小改一下就行。
- 不含任何具体书源规则/站点信息，书源需要用户自己导入。
- 仅供学习交流，请遵守你所在地区的法律法规，尊重内容版权方。

## License

<!-- TODO: 选一个license。个人/学习项目常见选 MIT 或 GPL-3.0（legado本身是GPL-3.0，
如果你的实现直接抄了它的算法逻辑、想跟上游保持同协议兼容，选GPL-3.0比较合适；
如果想让别人更自由地把你的代码用进闭源项目，选MIT更宽松）。定了之后把这段替换成
真正的 LICENSE 文件内容，GitHub创建仓库时也可以直接选模板生成。 -->
