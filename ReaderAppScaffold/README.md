# ReaderAppScaffold

基于 `LegadoRuleEngine` 的最小可用 SwiftUI 阅读App骨架：书源管理 + 跨书源搜索 + 书架 + 阅读器。
这些是**参考实现/脚手架**，不是生产级代码——能跑通主流程，UI很朴素，边界情况(网络失败提示、
分页搜索、图片封面加载等)按你实际需求再补。

## 依赖

- iOS 17+（用了 SwiftData 和 `@Observable`，这两个都要求 iOS 17 起步）
- 已经建好的 `LegadoRuleEngine` 本地 Swift Package（上一份产出物）

## 接入步骤

1. Xcode 新建一个 App 工程（Interface选SwiftUI，不要SwiftData模板自带的Item.swift那套，等下会被替换）。
2. File → Add Package Dependencies → Add Local... 选中 `LegadoRuleEngine` 文件夹，加到你的App target依赖里。
3. 把这份 `ReaderAppScaffold` 里 `Persistence/`、`Stores/`、`Views/` 三个文件夹整个拖进 Xcode 工程（记得勾选"Copy items if needed"和加到你的App target）。
4. `App/ReaderApp.swift` 里的内容合并到 Xcode 自动生成的、带 `@main` 的那个 App 文件里，**不要让两个 `@main` 同时存在**——用这份替换掉 Xcode 生成的默认内容就行，同时删掉 Xcode 自带的 `ContentView.swift`/`Item.swift`（如果有）。
5. Info.plist 加一条 App Transport Security 例外（很多书源站点是 http 或证书不规范），或者按书源实际情况精细配置，别图省事直接全局关ATS上架会被拒。
6. Build & Run。第一次进"书源"Tab导入一个书源json（网上搜"legado 书源"能找到很多社区书源仓库），然后去"搜索"Tab搜书。

## 目录结构

```
ReaderAppScaffold/
├── Persistence/
│   ├── BookSourceRecord.swift   # SwiftData: 书源持久化记录
│   └── ShelfBook.swift          # SwiftData: 书架里保存的书
├── Stores/
│   ├── BookSourceStore.swift    # 导入/启用禁用/列出书源
│   ├── SearchViewModel.swift    # 并发跨书源搜索
│   ├── ReaderViewModel.swift    # 目录加载 + 正文翻页 + 预取下一章
│   └── ImageLoader.swift        # 带自定义header的图片加载+内存缓存
├── Views/
│   ├── BookSourceListView.swift # 书源管理页
│   ├── ImportSourceView.swift   # 导入书源(粘贴/选文件)
│   ├── SearchView.swift         # 搜索页(带封面缩略图)
│   ├── BookDetailView.swift     # 详情+目录页(带封面)
│   ├── ReaderView.swift         # 阅读页(CoreText真分页+点击/滑动翻页+调字号)
│   ├── TextPaginator.swift      # CoreText分页计算(纯逻辑，无UI)
│   ├── ShelfView.swift          # 书架页(带封面缩略图)
│   └── CoverImageView.swift     # 类似AsyncImage，支持自定义header的封面组件
└── App/
    └── ReaderApp.swift          # @main入口，TabView(书架/搜索/书源)
```

## 已知没做的（自己按需补）

- ~~搜索只搜第一页~~ 已实现：`SearchViewModel.loadMore()` 翻下一页追加结果，`SearchView` 里滑到底部自动加载(也有手动按钮兜底)，某一页所有源都没结果了就标记 `reachedEnd` 停止（不是逐源精细跟踪"谁还有下一页"，书源数量正常范围内够用）。
- ~~封面图片~~ 已实现：`Stores/ImageLoader.swift`(带自定义header的图片加载+内存缓存) + `Views/CoverImageView.swift`(类似`AsyncImage`的封面组件)，搜索结果/详情页/书架都接上了。
- ~~正文分页排版~~ 已实现：`Views/TextPaginator.swift` 用 CoreText (`CTFramesetter`) 按屏幕尺寸/字号/行距精确断页，`ReaderView` 改成了点击分区(左/右/中)+滑动翻页，翻到章节首尾自动接上一章/下一章。CoreText分页量出来的断页点和SwiftUI `Text` 用相同字体/宽度渲染的结果理论上应该一致（两者底层都是CoreText排版），实测如果发现个别情况下最后一行被裁掉一点，把 `bottomPadding` 稍微调大一点留点余量就行。
- **没做字体反爬解密的接入**：`QueryTTF` 已经在引擎里了，但 `BookSourceRuntime.getContent` 没有自动检测/下载/应用自定义字体这一步（`ContentRule` 里其实没有专门的"字体URL"规则字段，legado是从返回的HTML里找`@font-face`/`.ttf`链接再下载解密，这部分识别逻辑建议你按实际遇到的书源单独处理)。
- ~~并发限流~~ 已接入：`LegadoRuleEngine` 的 `BookSourceRuntime` 每次请求前会按书源的 `concurrentRate` 字段过一遍 `SourceRateLimiter.shared`（时间窗口限流，"1/1000"这种格式）。
- **没有错误重试UI**、没有"换源"功能（一本书换成另一个书源继续读，legado里叫"换源"，需要额外做"用书名+作者反查其他书源里的书"的逻辑）。
