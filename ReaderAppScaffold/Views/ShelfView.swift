import SwiftUI
import SwiftData
import LegadoRuleEngine

/// 书架页：顶部搜索 + 最近阅读卡片 + 书架网格（对照设计稿）
struct ShelfView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\ShelfBook.lastReadAt, order: .reverse)])
    private var books: [ShelfBook]
    @Query private var allSources: [BookSourceRecord]

    @State private var readerVM: ReaderViewModel?
    @State private var openBook: ShelfBook?
    @State private var headerCache = HeaderCacheBox()
    @State private var searchText = ""
    @State private var showImport = false
    @State private var showSourceList = false
    @State private var sortByRecent = true

    private var recentBook: ShelfBook? {
        books.first { $0.lastReadAt != nil }
    }

    private var sortedBooks: [ShelfBook] {
        sortByRecent ? books : books.sorted { $0.addedAt > $1.addedAt }
    }

    private var filtered: [ShelfBook] {
        guard !searchText.isEmpty else { return sortedBooks }
        return sortedBooks.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
                || $0.author.localizedCaseInsensitiveContains(searchText)
        }
    }

    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    searchBar
                    if books.isEmpty {
                        emptyState
                    } else {
                        if let recent = recentBook {
                            recentCard(recent)
                        }
                        shelfGrid
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
            .sheet(isPresented: $showImport) { ImportSourceView() }
            .sheet(isPresented: $showSourceList) { BookSourceListView() }
        }
    }

    // MARK: - 顶部

    private var header: some View {
        HStack {
            Text("书架").font(.system(size: 30, weight: .bold))
            Spacer()
            Menu {
                Button { showSourceList = true } label: { Label("书源管理", systemImage: "tray.full") }
                Button { showImport = true } label: { Label("导入书源", systemImage: "square.and.arrow.down") }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.white))
            }
        }
        .padding(.top, 6)
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("在书架查找", text: $searchText)
                .textInputAutocapitalization(.never)
            if !searchText.isEmpty {
                Button { searchText = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Capsule().fill(Color.white))
        .overlay(Capsule().stroke(Theme.hairline, lineWidth: 0.5))
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer().frame(height: 80)
            Image(systemName: "books.vertical")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(Theme.accent.opacity(0.85))
                .frame(width: 110, height: 110)
                .background(RoundedRectangle(cornerRadius: 28).fill(Color.white))
            Text("书架为空").font(.title3.bold())
            Text("从浏览页找书，或先导入一个书源").font(.footnote).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button { showImport = true } label: { Label("导入书源", systemImage: "square.and.arrow.down") }
                    .prominentGlassButton()
                    .tint(Theme.accent)
            }
            Spacer().frame(height: 120)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 最近阅读

    private func progress(of book: ShelfBook) -> Double {
        guard book.totalChapters > 0 else { return 0 }
        return Double(min(book.lastReadChapterIndex + 1, book.totalChapters)) / Double(book.totalChapters)
    }

    private func recentCard(_ book: ShelfBook) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("最近阅读").font(.headline)
            Button { open(book) } label: {
                HStack(alignment: .top, spacing: 12) {
                    SmartCover(url: book.coverUrl, title: book.name, headers: headers(for: book))
                        .frame(width: 52, height: 72)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(book.name).font(.subheadline.bold()).foregroundStyle(.primary).lineLimit(1)
                        Text(book.author).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        Text("第 \(min(book.lastReadChapterIndex + 1, max(book.totalChapters, 1))) 章 / \(max(book.totalChapters, 1)) 章")
                            .font(.caption2).foregroundStyle(.secondary)
                        MiniProgressBar(progress: progress(of: book))
                    }
                    Spacer()
                    Text("\(Int((progress(of: book) * 100).rounded()))%")
                        .font(.caption.bold()).foregroundStyle(Theme.accent)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color.white))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.hairline, lineWidth: 0.5))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - 我的书架

    private var shelfGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("我的书架").font(.headline)
                Spacer()
                Menu {
                    Button("按最近阅读") { sortByRecent = true }
                    Button("按加入时间") { sortByRecent = false }
                } label: {
                    Label(sortByRecent ? "按最近阅读" : "按加入时间", systemImage: "chevron.down")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if filtered.isEmpty {
                Text("没有找到「\(searchText)」相关书籍").font(.footnote).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center).padding(.top, 24)
            } else {
                LazyVGrid(columns: columns, spacing: 18) {
                    ForEach(filtered) { book in
                        gridCell(book)
                    }
                }
            }
        }
    }

    private func gridCell(_ book: ShelfBook) -> some View {
        Button { open(book) } label: {
            VStack(alignment: .leading, spacing: 6) {
                SmartCover(url: book.coverUrl, title: book.name, headers: headers(for: book))
                    .frame(width: 96, height: 128)
                    .shadow(color: .black.opacity(0.10), radius: 6, y: 3)
                Text(book.name).font(.caption.bold()).lineLimit(1).foregroundStyle(.primary)
                Text(book.author).font(.caption2).lineLimit(1).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                context.delete(book)
                try? context.save()
            } label: { Label("移出书架", systemImage: "trash") }
        }
    }

    // MARK: - 打开书籍

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
