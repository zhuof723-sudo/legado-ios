import SwiftUI
import SwiftData
import UIKit
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

    /// 配置 UITabBar 外观：iOS 原生毛玻璃效果
    private func configureTabBarAppearance() {
        let tabBarAppearance = UITabBarAppearance()

        // iOS 15+：使用系统原生毛玻璃背景
        tabBarAppearance.configureWithDefaultBackground()

        // 确保滚动到边缘时也保持毛玻璃效果（不变成透明）
        UITabBar.appearance().standardAppearance = tabBarAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance

        // 设置选中颜色
        UITabBar.appearance().tintColor = UIColor(Theme.accent)

        // 未选中颜色
        UITabBar.appearance().unselectedItemTintColor = UIColor.secondaryLabel
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(currentThemeMode == .dark ? .dark : .light)
        }
        .modelContainer(for: [BookSourceRecord.self, ShelfBook.self, LocalBook.self])
    }
}

/// 根视图：四个标签 + 悬浮玻璃搜索按钮（对照设计稿的底部导航）
struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase

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
    }
}
