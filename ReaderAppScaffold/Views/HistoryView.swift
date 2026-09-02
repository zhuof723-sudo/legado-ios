import SwiftUI
import SwiftData
import LegadoRuleEngine

/// 历史页：按 今天/昨天/更早 分组展示阅读记录（对照设计稿）
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

    private var groups: [(title: String, items: [ShelfBook])] {
        let calendar = Calendar.current
        var today: [ShelfBook] = [], yesterday: [ShelfBook] = [], earlier: [ShelfBook] = []
        for book in filtered {
            guard let date = book.lastReadAt else { continue }
            if calendar.isDateInToday(date) {
                today.append(book)
            } else if calendar.isDateInYesterday(date) {
                yesterday.append(book)
            } else {
                earlier.append(book)
            }
        }
        var result: [(String, [ShelfBook])] = []
        if !today.isEmpty { result.append(("今天", today)) }
        if !yesterday.isEmpty { result.append(("昨天", yesterday)) }
        if !earlier.isEmpty { result.append(("更早", earlier)) }
        return result
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    historySearchBar
                    if groups.isEmpty {
                        emptyState
                    } else {
                        ForEach(groups, id: \.title) { group in
                            VStack(alignment: .leading, spacing: 10) {
                                Text(group.title).font(.headline)
                                ForEach(group.items) { book in
                                    row(book)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 90)
            }
            .background(Theme.bg.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $readerVM) { vm in
                ReaderView(viewModel: vm, bookUrl: openBook?.bookUrl ?? "", bookName: openBook?.name ?? "")
            }
        }
    }

    private var header: some View {
        HStack {
            Text("历史").font(.system(size: 30, weight: .bold))
            Spacer()
            Image(systemName: "ellipsis")
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color.white))
        }
        .padding(.top, 6)
    }

    private var historySearchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("在历史记录中查找", text: $searchText)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Capsule().fill(Color.white))
        .overlay(Capsule().stroke(Theme.hairline, lineWidth: 0.5))
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer().frame(height: 90)
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 46, weight: .light))
                .foregroundStyle(.secondary)
            Text("暂无阅读记录").font(.headline).foregroundStyle(.secondary)
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
        if Calendar.current.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        return date.formatted(.dateTime.month().day())
    }

    private func row(_ book: ShelfBook) -> some View {
        Button { open(book) } label: {
            HStack(spacing: 12) {
                SmartCover(url: book.coverUrl, title: book.name, headers: headers(for: book))
                    .frame(width: 44, height: 60)
                VStack(alignment: .leading, spacing: 5) {
                    Text(book.name).font(.subheadline.bold()).foregroundStyle(.primary).lineLimit(1)
                    Text(book.author).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    HStack(spacing: 8) {
                        Text("阅读至: 第 \(min(book.lastReadChapterIndex + 1, max(book.totalChapters, 1))) 章")
                            .font(.caption2).foregroundStyle(.secondary)
                        MiniProgressBar(progress: progress(of: book))
                            .frame(width: 70)
                        Text("\(Int((progress(of: book) * 100).rounded()))%")
                            .font(.caption2).foregroundStyle(Theme.accent)
                    }
                }
                Spacer()
                Text(timeText(book.lastReadAt))
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.white))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline, lineWidth: 0.5))
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
        let vm = ReaderViewModel(source: source)
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
