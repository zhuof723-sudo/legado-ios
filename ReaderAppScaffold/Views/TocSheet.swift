import SwiftUI
import LegadoRuleEngine

/// 目录面板（Apple Books 式）：分段控件切换「目录 / 书签」，
/// 顶部搜索过滤章节，书签点击直接跳回对应章 + 页。
/// 通过闭包与任意阅读驱动解耦（在线书源 / 本地 TXT 共用）。
struct TocSheet: View {
    /// 章节行（调用方把自有章节模型映射进来）
    struct TocEntry: Identifiable {
        let index: Int
        let name: String
        var id: String { "\(index)-\(name)" }
    }

    let bookUrl: String
    let entries: [TocEntry]
    let currentIndex: Int
    /// 点章节（目录 tab）
    var onSelectChapter: (Int) -> Void
    /// 点书签（书签 tab）——由调用方负责切章 + 跳页
    var onSelectBookmark: ((BookBookmark) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var tab: Tab = .toc
    @State private var tocSearch = ""

    private enum Tab: String, CaseIterable, Identifiable {
        case toc = "目录"
        case bookmarks = "书签"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("目录").font(.system(size: 30, weight: .bold))
                    Spacer()
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 18))
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                // Apple Books 式分段控件
                Picker("", selection: $tab) {
                    ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)

                if tab == .toc {
                    searchBar
                }

                Group {
                    switch tab {
                    case .toc:
                        tocList
                    case .bookmarks:
                        bookmarkList
                    }
                }
                .transition(.opacity)
            }
            .background(Theme.bg.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .animation(.easeInOut(duration: 0.15), value: tab)
        }
    }

    // MARK: - 目录

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.textSecondary)
            TextField("搜索章节", text: $tocSearch)
                .font(.subheadline)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .glassCard(Capsule(), interactive: true)
        .padding(.horizontal, 16)
    }

    private var searchedEntries: [TocEntry] {
        guard !tocSearch.isEmpty else { return entries }
        return entries.filter { $0.name.localizedCaseInsensitiveContains(tocSearch) }
    }

    private var tocList: some View {
        List(searchedEntries) { row in
            Button {
                onSelectChapter(row.index)
                dismiss()
            } label: {
                HStack {
                    Text(row.name)
                        .font(.subheadline)
                        .foregroundStyle(row.index == currentIndex ? Theme.accent : Color.primary)
                        .lineLimit(1)
                    Spacer()
                    Text(row.index < currentIndex ? "已读" : "未读")
                        .font(.caption2)
                        .foregroundStyle(row.index < currentIndex ? Theme.textSecondary : Theme.textSecondary.opacity(0.6))
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    // MARK: - 书签

    private var bookmarks: [BookBookmark] {
        BookmarkStore.all(for: bookUrl)
    }

    private var bookmarkList: some View {
        Group {
            if bookmarks.isEmpty {
                ContentUnavailableView(
                    "暂无书签",
                    systemImage: "bookmark",
                    description: Text("阅读时点右上角书签按钮即可收藏当前页")
                )
            } else {
                List(bookmarks) { bookmark in
                    Button {
                        onSelectChapter(bookmark.chapterIndex)
                        onSelectBookmark?(bookmark)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "bookmark.fill")
                                .font(.caption)
                                .foregroundStyle(Theme.accent)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(bookmark.label)
                                    .font(.subheadline)
                                    .lineLimit(1)
                                    .foregroundStyle(bookmark.chapterIndex == currentIndex ? Theme.accent : Color.primary)
                                Text(bookmark.createdAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption2)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            Spacer()
                            Text("第 \(bookmark.pageIndex + 1) 页")
                                .font(.caption2)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }
}
