import SwiftUI
import SwiftData
import LegadoRuleEngine

/// 书架页（对照设计稿 1:1）：
/// 大标题 + 圆形操作按钮、搜索胶囊、推荐横幅、最近阅读卡片、我的书架网格。
struct ShelfView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\ShelfBook.lastReadAt, order: .reverse)])
    private var books: [ShelfBook]
    @Query private var allSources: [BookSourceRecord]
    @Query(sort: [SortDescriptor(\LocalBook.createdAt, order: .reverse)])
    private var localBooks: [LocalBook]

    @State private var readerVM: ReaderViewModel?
    @State private var openBook: ShelfBook?
    @State private var openLocal: LocalBook?
    @State private var headerCache = HeaderCacheBox()
    @State private var searchText = ""
    @State private var showImport = false
    @State private var showSourceList = false
    @State private var showTxtImport = false
    @State private var sortByRecent = true

    private var recentBook: ShelfBook? {
        books.first { $0.lastReadAt != nil } ?? books.first
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

    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    searchBar
                    heroBanner
                    if books.isEmpty && localBooks.isEmpty {
                        emptyState
                    } else {
                        if let recent = recentBook {
                            recentCard(recent)
                        }
                        if !localBooks.isEmpty {
                            localSection
                        }
                        if !books.isEmpty {
                            shelfSection
                        }
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
            .sheet(isPresented: $showImport) { ImportSourceView() }
            .sheet(isPresented: $showSourceList) { BookSourceListView() }
            .sheet(isPresented: $showTxtImport) { TxtImportView() }
            .fullScreenCover(item: $openLocal) { book in
                LocalReaderView(book: book)
            }
        }
    }

    // MARK: - 顶部标题

    private var header: some View {
        HStack(spacing: 12) {
            Text("书架")
                .font(.system(size: 32, weight: .bold))
            Spacer()
            Menu {
                Button { showImport = true } label: { Label("导入书源", systemImage: "square.and.arrow.down") }
                Button { showTxtImport = true } label: { Label("导入 TXT", systemImage: "doc.text") }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Theme.secondaryBg))
            }
            Menu {
                Button { showSourceList = true } label: { Label("书源管理", systemImage: "tray.full") }
                Button(sortByRecent ? "按加入时间排序" : "按最近阅读排序") { sortByRecent.toggle() }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Theme.secondaryBg))
            }
        }
        .padding(.top, 4)
    }

    // MARK: - 搜索框

    private var searchBar: some View {
        NavigationLink {
            SearchView(embeddedInTab: false)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Theme.textSecondary)
                Text("搜索书名、作者、书源...")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                Capsule()
                    .fill(Theme.secondaryBg)
                    .overlay(Capsule().stroke(Theme.hairline, lineWidth: 0.5))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 推荐横幅

    private var heroBanner: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.85, green: 0.90, blue: 0.96),
                            Color(red: 0.93, green: 0.95, blue: 0.98),
                            Color(red: 0.97, green: 0.98, blue: 0.99)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            // 远山与云的抽象层次
            GeometryReader { geo in
                Circle()
                    .fill(Color.white.opacity(0.45))
                    .frame(width: geo.size.width * 0.7, height: geo.size.width * 0.5)
                    .offset(x: geo.size.width * 0.45, y: -geo.size.width * 0.18)
                Ellipse()
                    .fill(Color(red: 0.72, green: 0.80, blue: 0.90).opacity(0.55))
                    .frame(width: geo.size.width * 0.9, height: geo.size.height * 0.9)
                    .offset(x: geo.size.width * 0.35, y: geo.size.height * 0.45)
                Ellipse()
                    .fill(Color(red: 0.62, green: 0.72, blue: 0.85).opacity(0.45))
                    .frame(width: geo.size.width * 0.8, height: geo.size.height * 1.1)
                    .offset(x: -geo.size.width * 0.15, y: geo.size.height * 0.62)
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("阅读，遇见更好的自己")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color(red: 0.16, green: 0.23, blue: 0.38))
                Text("— 热门推荐 —")
                    .font(.caption)
                    .foregroundStyle(Color(red: 0.35, green: 0.42, blue: 0.55))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(.leading, 20)
        }
        .frame(height: 150)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer().frame(height: 60)
            Image(systemName: "book.fill")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Theme.accent)
                .frame(width: 100, height: 100)
                .background(Circle().fill(Theme.secondaryBg))
            Text("书架为空").font(.title3.bold())
            Text("从发现页找书，或先导入一个书源").font(.footnote).foregroundStyle(Theme.textSecondary)
            HStack(spacing: 12) {
                Button { showImport = true } label: {
                    Label("导入书源", systemImage: "square.and.arrow.down")
                        .font(.subheadline.bold())
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(Capsule().fill(Theme.accent))
                        .foregroundStyle(.white)
                }
                Button { showTxtImport = true } label: {
                    Label("导入 TXT", systemImage: "doc.text")
                        .font(.subheadline.bold())
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(Capsule().fill(Theme.secondaryBg))
                }
            }
            .tint(Theme.accent)
            Spacer().frame(height: 80)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 最近阅读

    private func progress(of book: ShelfBook) -> Double {
        guard book.totalChapters > 0 else { return 0 }
        return Double(min(book.lastReadChapterIndex + 1, book.totalChapters)) / Double(book.totalChapters)
    }

    private func recentCard(_ book: ShelfBook) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("最近阅读")
                .font(.title3.bold())
            Button { open(book) } label: {
                HStack(alignment: .top, spacing: 14) {
                    SmartCover(url: book.coverUrl, title: book.name, headers: headers(for: book))
                        .frame(width: 56, height: 76)
                        .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(book.name)
                            .font(.subheadline.bold())
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text("第 \(min(book.lastReadChapterIndex + 1, max(book.totalChapters, 1))) 章 · \(book.author)")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                        HStack(spacing: 10) {
                            MiniProgressBar(progress: progress(of: book))
                            Text("\(Int((progress(of: book) * 100).rounded()))%")
                                .font(.caption.bold())
                                .foregroundStyle(.primary)
                                .monospacedDigit()
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Theme.cardBg)
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline, lineWidth: 0.5))
                )
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Theme.cardBg)
                .shadow(color: Theme.shadow, radius: 10, y: 4)
        )
    }

    // MARK: - 本地书籍

    private var localSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("本地书籍").font(.title3.bold())
            ForEach(localBooks) { book in
                Button { openLocal = book } label: {
                    HStack(spacing: 12) {
                        PlaceholderCover(title: book.name)
                            .frame(width: 40, height: 54)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(book.name).font(.subheadline.bold()).foregroundStyle(.primary).lineLimit(1)
                            Text("\(book.author) · \(TxtParser.decode(book.chaptersData).count) 章")
                                .font(.caption).foregroundStyle(Theme.textSecondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption2).foregroundStyle(Theme.textSecondary)
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Theme.cardBg)
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline, lineWidth: 0.5))
                    )
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button(role: .destructive) {
                        context.delete(book)
                        try? context.save()
                    } label: { Label("删除", systemImage: "trash") }
                }
            }
        }
    }

    // MARK: - 我的书架

    private var shelfSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("我的书架").font(.title3.bold())
                Spacer()
                Button { sortByRecent.toggle() } label: {
                    Text("编辑").font(.subheadline).foregroundStyle(Theme.accent)
                }
            }
            if filtered.isEmpty {
                Text("没有找到「\(searchText)」相关书籍")
                    .font(.footnote).foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 24)
            } else {
                LazyVGrid(columns: columns, spacing: 20) {
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
                    .aspectRatio(0.72, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
                Text(book.name)
                    .font(.caption.bold())
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                if progress(of: book) > 0.001 {
                    Text("\(Int((progress(of: book) * 100).rounded()))%")
                        .font(.caption2.bold())
                        .foregroundStyle(Theme.accent)
                } else {
                    Text("更新至 \(max(book.totalChapters, 0)) 章")
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
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
