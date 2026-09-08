import SwiftUI
import LegadoRuleEngine

/// 目录页（对照设计稿）：大标题 + 搜索栏 + 章节列表（左标题右状态）。
struct TocSheet: View {
    let bookUrl: String
    @Bindable var viewModel: ReaderViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var tocSearch = ""

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

                searchBar

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
                            Text(idx < viewModel.currentIndex ? "已读" : "未读")
                                .font(.caption2)
                                .foregroundStyle(idx < viewModel.currentIndex ? Theme.textSecondary : Theme.textSecondary.opacity(0.6))
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)

                HStack {
                    Label("正序", systemImage: "list.bullet")
                        .font(.subheadline)
                        .foregroundStyle(Theme.accent)
                    Spacer()
                    Text("共 \(viewModel.chapters.count) 章")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .background(Theme.bg.ignoresSafeArea())
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

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.textSecondary)
            TextField("搜索章节", text: $tocSearch)
                .font(.subheadline)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            Capsule()
                .fill(Theme.secondaryBg)
                .overlay(Capsule().stroke(Theme.hairline, lineWidth: 0.5))
        )
        .padding(.horizontal, 16)
    }
}
