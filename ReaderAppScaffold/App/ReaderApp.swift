import SwiftUI
import SwiftData
import LegadoRuleEngine

@main
struct ReaderApp: App {
    init() {
        EngineLogger.sink = { lvl, tag, msg in
            let level: LogLevel = lvl == .error ? .error : (lvl == .warn ? .warn : .info)
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
    @State private var showSearch = false
    @State private var readerIsActive = false
    @AppStorage("app.appearance") private var appearance = 0

    private var scheme: ColorScheme? {
        switch appearance {
        case 1: return .light
        case 2: return .dark
        default: return nil
        }
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            TabView {
                ShelfView()
                    .tabItem { Label("书架", systemImage: "books.vertical") }
                BrowseView()
                    .tabItem { Label("浏览", systemImage: "square.grid.2x2") }
                HistoryView()
                    .tabItem { Label("历史", systemImage: "clock.arrow.circlepath") }
                SettingsView()
                    .tabItem { Label("设置", systemImage: "gearshape") }
            }
            .tint(Theme.accent)
            .minimizeTabBarOnScroll()
            .onPreferenceChange(ReaderActivePreferenceKey.self) { readerIsActive = $0 }

            if !readerIsActive {
                searchFab
            }
        }
        .preferredColorScheme(scheme)
        .fullScreenCover(isPresented: $showSearch) {
            SearchView()
        }
    }

    private var searchFab: some View {
        Button {
            showSearch = true
        } label: {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 54, height: 54)
                .background(Circle().fill(.white.opacity(0.85)))
        }
        .glassCircle()
        .padding(.trailing, 16)
        .padding(.bottom, 60)
        .accessibilityLabel("搜索")
    }
}
