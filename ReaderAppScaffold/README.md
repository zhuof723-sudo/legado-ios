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
│   ├── （阅读层已迁至 Reading/）
│   └── ImageLoader.swift        # 带自定义header的图片加载+内存缓存
├── Views/
│   ├── BookSourceListView.swift # 书源管理页
│   ├── ImportSourceView.swift   # 导入书源(粘贴/选文件)
│   ├── SearchView.swift         # 搜索页(带封面缩略图)
│   ├── BookDetailView.swift     # 详情+目录页(带封面)
│   ├── ShelfView.swift          # 书架页(带封面缩略图)
│   └── CoverImageView.swift     # 类似AsyncImage，支持自定义header的封面组件
└── App/
    └── ReaderApp.swift          # @main入口，TabView(书架/搜索/书源)
```

## 阅读页架构（2026-09 推倒重建）

阅读层位于 `Reading/`，全部组件从零编写，旧 Reader* 组件一个不剩：

| 组件 | 文件 | 职责 |
|---|---|---|
| `ReadingScreen` | `Reading/ReadingScreen.swift` | 唯一阅读页（TXT/EPUB/在线共用），控制层与状态编排 |
| `ReadingSession` | `Reading/ReadingSession.swift` | 阅读会话：章节导航、分页编排（单飞+缓存）、阅读位置持久化（章节+字符偏移） |
| `BookContentSource` / `LocalChapterSource` / `OnlineChapterSource` | `Reading/BookContentSource.swift` | 内容源协议；本地（TXT/EPUB 已解析章节）与在线（书源引擎 + 内存/磁盘缓存 + 并发预取 + 段评） |
| `PaginationEngine` / `LayoutParams` / `PageCache` | `Reading/PaginationEngine.swift` | CoreText 分页：CTTypesetter 断行（UAX#14 中文禁则）、两端对齐、首行缩进；LRU 缓存 8 章 |
| `ChapterDocument` / `ChapterDocumentBuilder` / `InlineLink` | `Reading/ChapterDocument.swift` | 段落切分、段评 PUA 占位符 → 可点角标 run |
| `PageCanvasView` | `Reading/PageCanvas.swift` | CoreText 逐 run 直绘（测量=渲染同源），链接命中 + 点击分区 |
| `PageTurnerView` / `FlowTurnController` / `InstantTurnController` | `Reading/PageTurner.swift` | 翻页三档：仿真卷页(.pageCurl) / 平移(.scroll) / 无动画 |
| `ReadingTopBar` / `ReadingBottomBar` / `ProgressHairline` / `TapZones` | `Reading/ReadingChrome.swift` | 控制层：顶栏/底栏/进度细线/点击热区（左24%上一页、右24%下一页、中间唤出） |
| `AppearancePanel` | `Reading/AppearancePanel.swift` | 排版面板：字体/字号/行距/主题/亮度/翻页方式/开关 |
| `ContentsSheet` | `Reading/ContentsSheet.swift` | 目录 + 书签分段面板 |
| `SpeechController` / `ChapterSearchView` | `Reading/ReadingSupport.swift` | TTS 朗读、章内搜索 |
| `ReadingPreferences` | `Reading/ReadingSettings.swift` | 排版/主题/翻页偏好（沿用原 UserDefaults 键，设置不丢失） |

PDF 阅读器（`Views/PDFReaderView.swift`）独立走 PDFKit，控制层复用 ReadingChrome。

## 已知没做的（自己按需补）

- ~~搜索只搜第一页~~ 已实现：`SearchViewModel.loadMore()` 翻下一页追加结果，`SearchView` 里滑到底部自动加载(也有手动按钮兜底)，某一页所有源都没结果了就标记 `reachedEnd` 停止（不是逐源精细跟踪"谁还有下一页"，书源数量正常范围内够用）。
- ~~封面图片~~ 已实现：`Stores/ImageLoader.swift`(带自定义header的图片加载+内存缓存) + `Views/CoverImageView.swift`(类似`AsyncImage`的封面组件)，搜索结果/详情页/书架都接上了。
- 正文分页排版：`Reading/PaginationEngine.swift` 用 CoreText（CTTypesetter）按屏幕尺寸/字号/行距精确断页，中文禁则断行 + 两端对齐 + 首行缩进，点击分区(左/右/中) + 三种翻页，章节首尾自动接续。
- **没做字体反爬解密的接入**：`QueryTTF` 已经在引擎里了，但 `BookSourceRuntime.getContent` 没有自动检测/下载/应用自定义字体这一步（`ContentRule` 里其实没有专门的"字体URL"规则字段，legado是从返回的HTML里找`@font-face`/`.ttf`链接再下载解密，这部分识别逻辑建议你按实际遇到的书源单独处理)。
- ~~并发限流~~ 已接入：`LegadoRuleEngine` 的 `BookSourceRuntime` 每次请求前会按书源的 `concurrentRate` 字段过一遍 `SourceRateLimiter.shared`（时间窗口限流，"1/1000"这种格式）。
- **没有错误重试UI**、没有"换源"功能（一本书换成另一个书源继续读，legado里叫"换源"，需要额外做"用书名+作者反查其他书源里的书"的逻辑）。
