import SwiftUI
import SwiftData
import UIKit
import LegadoRuleEngine

@main
struct ReaderApp: App {
    init() {
        // 只使用系统提供的 identifierForVendor；获取不到时保持空，不伪造设备码。
        JSCommonMethods.deviceIdentifier = UIDevice.current.identifierForVendor?.uuidString ?? ""
        CrashReporter.shared.start()
        EngineLogger.sink = { lvl, tag, msg in
            let level: LogLevel = lvl == .error ? .error : (lvl == .warn ? .warn : .info)
            CrashReporter.shared.breadcrumb(level: level.rawValue, tag: tag, message: msg)
            Task { @MainActor in LogStore.shared.log(msg, tag: tag, level: level) }
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [BookSourceRecord.self, ShelfBook.self, LocalBook.self])
    }
}

/// 根视图：四个标签 + 悬浮玻璃搜索按钮（对照设计稿的底部导航）
struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("app.appearance") private var appearance = 0

    private var scheme: ColorScheme? {
        switch appearance {
        case 1: return .light
        case 2: return .dark
        default: return nil
        }
    }

    var body: some View {
        TabView {
            ShelfView()
                .tabItem { Label("书架", systemImage: "books.vertical") }
            BrowseView()
                .tabItem { Label("浏览", systemImage: "square.grid.2x2") }
            SearchView(embeddedInTab: true)
                .tabItem { Label("搜索", systemImage: "magnifyingglass") }
            HistoryView()
                .tabItem { Label("历史", systemImage: "clock.arrow.circlepath") }
            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape") }
        }
        .tint(Theme.accent)
        .minimizeTabBarOnScroll()
        .preferredColorScheme(scheme)
        .onAppear {
            CrashReporter.shared.markSessionActive(true)
            CrashLogStore.shared.reload()
        }
        .onChange(of: scenePhase) {
            switch scenePhase {
            case .active:
                CrashReporter.shared.markSessionActive(true)
            case .background:
                CrashReporter.shared.markSessionActive(false)
            default:
                break
            }
        }
    }
}
