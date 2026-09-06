import SwiftUI
import LegadoRuleEngine

/// 目录/书签 弹层（对照设计稿：分段标签 + 章节列表 + 当前章高亮）
struct TocSheet: View {
    let bookUrl: String
    @Bindable var viewModel: ReaderViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var tab = 0            // 0目录 1书签
    @State private var tocSearch = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $tab) {
                    Text("目录").tag(0)
                    Text("书签").tag(1)
                }
                .pickerStyle(.segmented)
                .tint(Theme.accent)
                .padding(.horizontal, 16)
                .padding(.top, 8)

                if tab == 0 {
                    tocList
                } else {
                    bookmarkList
                }
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("目录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }

    private struct ChapterRow: Identifiable {
        let index: Int
        let chapter: ChapterInfo
        var id: String { chapter.url }
    }

    private var searchedChapters: [ChapterRow] {
        let all = Array(viewModel.chapters.enumerated())
        let filtered = tocSearch.isEmpty
            ? all
            : all.filter { $0.element.name.localizedCaseInsensitiveContains(tocSearch) }
        return filtered.map { ChapterRow(index: $0.offset, chapter: $0.element) }
    }

    private var tocList: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜索章节", text: $tocSearch)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .glassCard(Capsule(), interactive: true)
            .overlay(Capsule().stroke(Theme.hairline, lineWidth: 0.5))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            List(searchedChapters) { row in
                let idx = row.index
                let chapter = row.chapter
                Button {
                    Task {
                        await viewModel.openChapter(at: idx)
                        dismiss()
                    }
                } label: {
                    HStack {
                        Text(chapter.name)
                            .font(.subheadline)
                            .foregroundStyle(idx == viewModel.currentIndex ? Theme.accent : Color.primary)
                            .lineLimit(1)
                        Spacer()
                        Text("\(idx + 1)/\(viewModel.chapters.count)")
                            .font(.caption2)
                            .foregroundStyle(idx == viewModel.currentIndex ? Theme.accent : Color(.tertiaryLabel))
                        if idx == viewModel.currentIndex {
                            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(Theme.accent)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private var bookmarkList: some View {
        let bookmarks = BookmarkStore.all(for: bookUrl)
        return Group {
            if bookmarks.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "bookmark")
                        .font(.system(size: 40, weight: .light))
                        .foregroundStyle(.secondary)
                    Text("暂无书签").font(.subheadline).foregroundStyle(.secondary)
                    Button {
                        addBookmark()
                    } label: {
                        Label("为当前章添加书签", systemImage: "plus")
                            .prominentGlassButton()
                            .tint(Theme.accent)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List {
                    Section {
                        ForEach(bookmarks) { bm in
                            Button {
                                Task {
                                    await viewModel.openChapter(at: bm.chapterIndex)
                                    dismiss()
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(bm.label).font(.subheadline).foregroundStyle(.primary).lineLimit(2)
                                    Text("第 \(bm.chapterIndex + 1) 章 · \(bm.createdAt.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .onDelete { indexSet in
                            let all = BookmarkStore.all(for: bookUrl)
                            for i in indexSet { BookmarkStore.remove(all[i]) }
                        }
                    } header: {
                        Button {
                            addBookmark()
                        } label: {
                            Label("添加当前章书签", systemImage: "plus.circle")
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
        }
    }

    private func addBookmark() {
        let label = viewModel.currentChapterTitle ?? "书签"
        BookmarkStore.add(BookBookmark(
            bookUrl: bookUrl,
            chapterIndex: viewModel.currentIndex,
            pageIndex: 0,
            label: label,
            createdAt: Date()
        ))
    }
}
