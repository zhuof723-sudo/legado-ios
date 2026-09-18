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
│   ├── ReaderPage/              # 全新正文阅读内核（TXT/EPUB/在线 + 段评 + pageCurl）
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

## 阅读页架构（2026-09 再次重构）

正文阅读层位于 `ReaderPage/`，上一版 `Reading/` 已整体删除。正文只保留段评和仿真翻页：

| 组件 | 文件 | 职责 |
|---|---|---|
| `ReaderPageScreen` | `ReaderPage/ReaderPageScreen.swift` | 唯一正文阅读页：章节、页码、返回、段评入口 |
| `ReaderPageSession` | `ReaderPage/ReaderPageSession.swift` | 阅读会话、章节切换、分页任务、字符偏移进度 |
| `ReaderPageLocalSource` / `ReaderPageOnlineSource` | `ReaderPage/ReaderPageSource.swift` | TXT/EPUB 与在线正文内容源，在线源保留段评数据 |
| `ReaderPageDocumentBuilder` | `ReaderPage/ReaderPageDocument.swift` | 中文段落切分、段评占位符与可点击角标 |
| `ReaderPagePagination` | `ReaderPage/ReaderPagePagination.swift` | CoreText 中文断行、标点禁则、两端对齐、首行缩进、按屏幕尺寸分页 |
| `ReaderPageCanvas` | `ReaderPage/ReaderPageCanvas.swift` | CoreText 逐 run 直绘、段评链接命中、左右翻页热区 |
| `ReaderPageCurlController` | `ReaderPage/ReaderPageCurl.swift` | 唯一翻页实现：`UIPageViewController.pageCurl` 仿真翻页 |
| `ReaderPageStyle` | `ReaderPage/ReaderPageStyle.swift` | 字体、字号、行距、段距、边距、主题；不包含翻页模式 |
| `ReaderPageSettingsPage` | `ReaderPage/ReaderPageSettings.swift` | 新排版设置页；仅调整正文样式 |

已从正文阅读页移除：平移翻页、无动画翻页、旧控制层、旧目录、书签、TTS、章内搜索和旧 Aa 面板。PDF 仍是独立 PDFKit 格式模块，但使用相同的极简样式模型和 `pageCurl`。


## 已知没做的（自己按需补）

- ~~搜索只搜第一页~~ 已实现：`SearchViewModel.loadMore()` 翻下一页追加结果，`SearchView` 里滑到底部自动加载(也有手动按钮兜底)，某一页所有源都没结果了就标记 `reachedEnd` 停止（不是逐源精细跟踪"谁还有下一页"，书源数量正常范围内够用）。
- ~~封面图片~~ 已实现：`Stores/ImageLoader.swift`(带自定义header的图片加载+内存缓存) + `Views/CoverImageView.swift`(类似`AsyncImage`的封面组件)，搜索结果/详情页/书架都接上了。
- 正文分页排版：`ReaderPage/ReaderPagePagination.swift` 用 CoreText（CTTypesetter）按屏幕尺寸/字号/行距精确断页，中文禁则断行 + 两端对齐 + 首行缩进；正文固定使用 `pageCurl`，章节首尾自动接续。
- **没做字体反爬解密的接入**：`QueryTTF` 已经在引擎里了，但 `BookSourceRuntime.getContent` 没有自动检测/下载/应用自定义字体这一步（`ContentRule` 里其实没有专门的"字体URL"规则字段，legado是从返回的HTML里找`@font-face`/`.ttf`链接再下载解密，这部分识别逻辑建议你按实际遇到的书源单独处理)。
- ~~并发限流~~ 已接入：`LegadoRuleEngine` 的 `BookSourceRuntime` 每次请求前会按书源的 `concurrentRate` 字段过一遍 `SourceRateLimiter.shared`（时间窗口限流，"1/1000"这种格式）。
- **没有错误重试UI**、没有"换源"功能（一本书换成另一个书源继续读，legado里叫"换源"，需要额外做"用书名+作者反查其他书源里的书"的逻辑）。
