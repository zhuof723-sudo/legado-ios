import SwiftUI
import SwiftData

/// App 入口参考写法。实际接入时把这个文件里的内容合并到你 Xcode 项目自动生成的
/// `XxxApp.swift`（带 @main 的那个）里，不要让两个 @main 同时存在。
public struct ReaderRootView: View {
    public init() {}

    public var body: some View {
        TabView {
            ShelfView()
                .tabItem { Label("书架", systemImage: "books.vertical") }
            SearchView()
                .tabItem { Label("搜索", systemImage: "magnifyingglass") }
            BookSourceListView()
                .tabItem { Label("书源", systemImage: "tray.full") }
        }
    }
}

@main
struct ReaderApp: App {
    var body: some Scene {
        WindowGroup {
            ReaderRootView()
        }
        .modelContainer(for: [BookSourceRecord.self, ShelfBook.self])
    }
}
