import SwiftUI
import SwiftData
import UIKit
import PDFKit
import LegadoRuleEngine

@main
struct ReaderApp: App {
    @AppStorage("app.themeMode") private var themeMode: String = AppThemeMode.light.rawValue

    var currentThemeMode: AppThemeMode {
        AppThemeMode(rawValue: themeMode) ?? .light
    }

    init() {
        // 只使用系统提供的 identifierForVendor；获取不到时保持空，不伪造设备码。
        JSCommonMethods.deviceIdentifier = UIDevice.current.identifierForVendor?.uuidString ?? ""
        CrashReporter.shared.start()
        EngineLogger.sink = { lvl, tag, msg in
            let level: LogLevel = lvl == .error ? .error : (lvl == .warn ? .warn : .info)
            CrashReporter.shared.breadcrumb(level: level.rawValue, tag: tag, message: msg)
            Task { @MainActor in LogStore.shared.log(msg, tag: tag, level: level) }
        }
        // 配置 iOS 26 原生 UITabBar 毛玻璃效果
        configureTabBarAppearance()
    }

    /// 配置 UITabBar 外观：iOS 26 交给系统原生 Liquid Glass；旧系统使用材质背景。
    private func configureTabBarAppearance() {
        let tabBar = UITabBar.appearance()
        tabBar.tintColor = UIColor(Theme.accent)
        tabBar.unselectedItemTintColor = UIColor.secondaryLabel

        if #available(iOS 26.0, *) {
            // 链接 iOS 26 SDK 后，标准 TabView 会自动采用 Liquid Glass。
            // 不设置自定义 background，避免覆盖系统的玻璃形变与高光。
            return
        }

        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        tabBar.standardAppearance = appearance
        tabBar.scrollEdgeAppearance = appearance
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(currentThemeMode == .dark ? .dark : .light)
        }
        .modelContainer(for: [BookSourceRecord.self, ShelfBook.self, LocalBook.self, PDFBook.self])
    }
}

/// 根视图：四个标签 + 悬浮玻璃搜索按钮（对照设计稿的底部导航）
struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        TabView {
            ShelfView()
                .tabItem { Label("书架", systemImage: "book.fill") }
            BrowseView()
                .tabItem { Label("发现", systemImage: "safari") }
            SearchView(embeddedInTab: true)
                .tabItem { Label("搜索", systemImage: "magnifyingglass") }
            HistoryView()
                .tabItem { Label("历史", systemImage: "clock") }
            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape") }
        }
        .tint(Theme.accent)
        .minimizeTabBarOnScroll()
        .onAppear {
            CrashReporter.shared.markSessionActive(true)
            CrashLogStore.shared.reload()
        }
        .onChange(of: scenePhase) { _, _ in
            switch scenePhase {
            case .active:
                CrashReporter.shared.markSessionActive(true)
            case .background:
                CrashReporter.shared.markSessionActive(false)
            default:
                break
            }
        }
        // 处理「用其他 App 打开 / 分享到 Legado」送进来的文件。
        // Info.plist 里声明了 public.json 与 public.plain-text，
        // 没有这个入口的话那些声明等于白写，外部文件根本进不来。
        .onOpenURL { url in
            ExternalFileImporter.importFile(at: url, context: modelContext)
        }
    }
}

// MARK: - 外部文件导入

/// 把从 Files/其他 App 打开的文件导入 App。
/// .json 视作书源；.epub / .pdf 走本地书籍管线；其余按本地 TXT 处理。
enum ExternalFileImporter {
    @MainActor
    static func importFile(at url: URL, context: ModelContext) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let ext = url.pathExtension.lowercased()
        let name = url.deletingPathExtension().lastPathComponent

        switch ext {
        case "epub":
            importEpub(url: url, fallbackName: name, context: context)
        case "pdf":
            importPDF(url: url, fallbackName: name, context: context)
        default:
            importTextBookSource(url: url, context: context)
        }
    }

    @MainActor
    private static func importEpub(url: URL, fallbackName: String, context: ModelContext) {
        let parsed: BookReaderFileParser.EPUBBook
        do {
            parsed = try BookReaderFileParser.parseEPUB(url: url)
        } catch {
            notify("EPUB 导入失败：\(error.localizedDescription)")
            return
        }
        guard !parsed.chapters.isEmpty else {
            notify("EPUB 没有可读取的正文章节")
            return
        }
        let book = LocalBook(
            name: parsed.title.isEmpty ? fallbackName : parsed.title,
            author: parsed.author,
            chaptersData: BookReaderFileParser.encode(parsed.chapters),
            coverData: parsed.coverData
        )
        context.insert(book)
        do {
            try context.save()
            notify("已导入《\(book.name)》，共 \(parsed.chapters.count) 章")
        } catch {
            notify("保存失败：\(error.localizedDescription)")
        }
    }

    @MainActor
    private static func importPDF(url: URL, fallbackName: String, context: ModelContext) {
        let fileName = UUID().uuidString + ".pdf"
        let dest = PDFBook.pdfDirectory.appendingPathComponent(fileName)
        do {
            try FileManager.default.copyItem(at: url, to: dest)
        } catch {
            notify("PDF 保存失败：\(error.localizedDescription)")
            return
        }
        let meta = PDFReaderViewModel.metadata(from: dest)
        let pageCount = PDFDocument(url: dest)?.pageCount ?? 0
        guard pageCount > 0 else {
            try? FileManager.default.removeItem(at: dest)
            notify("PDF 无法解析（可能已损坏）")
            return
        }
        let pdfBook = PDFBook(
            name: meta.title ?? fallbackName,
            author: meta.author ?? "未知作者",
            fileName: fileName,
            pageCount: pageCount
        )
        context.insert(pdfBook)
        do {
            try context.save()
            notify("已导入《\(pdfBook.name)》，共 \(pageCount) 页")
        } catch {
            try? FileManager.default.removeItem(at: dest)
            notify("保存失败：\(error.localizedDescription)")
        }
    }

    @MainActor
    private static func importTextBookSource(url: URL, context: ModelContext) {
        let text: String
        do {
            text = try FileTextReader.readText(from: url)
        } catch {
            notify("导入「\(url.lastPathComponent)」失败：\(error.localizedDescription)")
            return
        }

        let ext = url.pathExtension.lowercased()
        if ext == "json" || looksLikeBookSourceJSON(text) {
            let store = BookSourceStore(context: context)
            let count = store.importSources(from: text)
            if let err = store.errorMessage {
                notify("书源导入失败：\(err)")
            } else {
                notify("已导入 \(count) 个书源")
            }
        } else {
            let chapters = BookReaderFileParser.chapters(from: text)
            guard !chapters.isEmpty else {
                notify("没能切分出章节：\(url.lastPathComponent)")
                return
            }
            let book = LocalBook(
                name: url.deletingPathExtension().lastPathComponent,
                author: "本地导入",
                chaptersData: BookReaderFileParser.encode(chapters)
            )
            context.insert(book)
            do {
                try context.save()
                notify("已导入《\(book.name)》，共 \(chapters.count) 章")
            } catch {
                notify("保存失败：\(error.localizedDescription)")
            }
        }
    }

    /// 粗略判断内容是否为书源 JSON（避免把 .txt 后缀的书源文件当小说处理）。
    private static func looksLikeBookSourceJSON(_ text: String) -> Bool {
        let head = text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(400)
        guard head.hasPrefix("{") || head.hasPrefix("[") else { return false }
        return head.contains("bookSourceUrl") || head.contains("bookSourceName")
    }

    @MainActor
    private static func notify(_ message: String) {
        CrashReporter.shared.breadcrumb(level: "info", tag: "import", message: message)
        Task { @MainActor in LogStore.shared.log(message, tag: "导入", level: .info) }
    }
}
