import SwiftUI
import SwiftData
import LegadoRuleEngine

public struct ShelfView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\ShelfBook.lastReadAt, order: .reverse)])
    private var books: [ShelfBook]
    @Query private var allSources: [BookSourceRecord]

    @State private var openBook: ShelfBook?
    @State private var readerVM: ReaderViewModel?
    @State private var headerCache = HeaderCacheBox()

    public init() {}

    public var body: some View {
        NavigationStack {
            List {
                ForEach(books) { book in
                    Button {
                        open(book)
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            CoverImageView(url: book.coverUrl, headers: headers(for: book))
                                .frame(width: 52, height: 72)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(book.name).font(.headline)
                                Text(book.author).font(.caption).foregroundStyle(.secondary)
                                if let title = book.lastReadChapterTitle {
                                    Text("读到: \(title)").font(.caption2).foregroundStyle(.tertiary)
                                }
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { indexSet in
                    for i in indexSet { context.delete(books[i]) }
                    try? context.save()
                }
            }
            .navigationTitle("书架")
            .overlay {
                if books.isEmpty {
                    ContentUnavailableView("书架是空的", systemImage: "books.vertical", description: Text("去搜索页找本书加进来"))
                }
            }
            .navigationDestination(item: $readerVM) { vm in
                ReaderView(viewModel: vm, bookUrl: openBook?.bookUrl ?? "", bookName: openBook?.name ?? "")
            }
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
            await vm.openChapter(at: book.lastReadChapterIndex)
        }
    }
}

extension ReaderViewModel: Identifiable, Hashable {
    public var id: ObjectIdentifier { ObjectIdentifier(self) }
    public static func == (lhs: ReaderViewModel, rhs: ReaderViewModel) -> Bool { lhs === rhs }
    public func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
}
