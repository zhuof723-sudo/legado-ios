import SwiftUI
import SwiftData
import LegadoRuleEngine

/// 阅读历史页（对照设计稿）：大标题 + 记录行（封面 / 标题 / 阅读至 N 章 + 进度 / 时间）。
struct HistoryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\ShelfBook.lastReadAt, order: .reverse)])
    private var books: [ShelfBook]
    @Query private var allSources: [BookSourceRecord]

    @State private var readerVM: ReaderViewModel?
    @State private var openBook: ShelfBook?
    @State private var searchText = ""
    @State private var headerCache = HeaderCacheBox()

    private var filtered: [ShelfBook] {
        books.filter { $0.lastReadAt != nil }
            .filter { searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Text("阅读历史").font(.system(size: 32, weight: .bold))
                        Spacer()
                    }
                    .padding(.top, 4)

                    historySearchBar

                    if filtered.isEmpty {
                        emptyState
                    } else {
                        VStack(spacing: 0) {
                            ForEach(filtered.indices, id: \.self) { index in
                                let book = filtered[index]
                                row(book)
                                if index != filtered.count - 1 {
                                    Rectangle().fill(Theme.hairline).frame(height: 0.5)
                                        .padding(.leading, 68)
                                }
                            }
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Theme.cardBg)
                                .shadow(color: Theme.shadow, radius: 8, y: 3)
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 90)
            }
            .background(Theme.bg.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .fullScreenCover(item: $readerVM) { vm in
                ReaderView(
                    viewModel: vm,
                    bookUrl: openBook?.bookUrl ?? "",
                    bookName: openBook?.name ?? "",
                    bookAuthor: openBook?.author ?? "",
                    coverURL: openBook?.coverUrl ?? ""
                )
            }
        }
    }

    private var historySearchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.textSecondary)
            TextField("搜索历史记录", text: $searchText)
                .font(.subheadline)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            Capsule()
                .fill(Theme.secondaryBg)
                .overlay(Capsule().stroke(Theme.hairline, lineWidth: 0.5))
        )
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer().frame(height: 90)
            Image(systemName: "clock")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Theme.textSecondary)
            Text("暂无阅读记录").font(.headline).foregroundStyle(Theme.textSecondary)
            Spacer().frame(height: 120)
        }
        .frame(maxWidth: .infinity)
    }

    private func progress(of book: ShelfBook) -> Double {
        guard book.totalChapters > 0 else { return 0 }
        return Double(min(book.lastReadChapterIndex + 1, book.totalChapters)) / Double(book.totalChapters)
    }

    private func timeText(_ date: Date?) -> String {
        guard let date else { return "" }
        let formatter = DateFormatter()
        if Calendar.current.isDateInToday(date) {
            formatter.dateFormat = "今天 HH:mm"
        } else if Calendar.current.isDateInYesterday(date) {
            formatter.dateFormat = "昨天 HH:mm"
        } else {
            formatter.dateFormat = "MM-dd HH:mm"
        }
        return formatter.string(from: date)
    }

    private func row(_ book: ShelfBook) -> some View {
        Button { open(book) } label: {
            HStack(spacing: 12) {
                SmartCover(url: book.coverUrl, title: book.name, headers: headers(for: book))
                    .frame(width: 46, height: 62)
                VStack(alignment: .leading, spacing: 6) {
                    Text(book.name)
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    HStack(spacing: 8) {
                        Text("阅读至: 第 \(min(book.lastReadChapterIndex + 1, max(book.totalChapters, 1))) 章")
                            .font(.caption2)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                        MiniProgressBar(progress: progress(of: book))
                            .frame(maxWidth: 70)
                        Text("\(Int((progress(of: book) * 100).rounded()))%")
                            .font(.caption2.bold())
                            .foregroundStyle(Theme.textSecondary)
                            .monospacedDigit()
                    }
                    Text(timeText(book.lastReadAt))
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary.opacity(0.7))
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                book.lastReadAt = nil
                try? context.save()
            } label: { Label("删除该记录", systemImage: "trash") }
        }
    }

    private func headers(for book: ShelfBook) -> [String: String] {
        if let cached = headerCache.storage[book.sourceUrl] { return cached }
        let h = allSources.first(where: { $0.bookSourceUrl == book.sourceUrl })?
            .decodeSource()?.parsedHeaderMap() ?? [:]
        headerCache.storage[book.sourceUrl] = h
        return h
    }

    private func open(_ book: ShelfBook) {
        guard let record = allSources.first(where: { $0.bookSourceUrl == book.sourceUrl }),
              let source = record.decodeSource() else { return }
        openBook = book
        let vm = ReaderViewModel(source: source, persistentBookURL: book.bookUrl)
        readerVM = vm
        Task {
            await vm.loadToc(bookUrl: book.bookUrl)
            book.totalChapters = vm.chapters.count
            try? context.save()
            let idx = min(max(book.lastReadChapterIndex, 0), max(vm.chapters.count - 1, 0))
            await vm.openChapter(at: idx)
        }
    }
}
