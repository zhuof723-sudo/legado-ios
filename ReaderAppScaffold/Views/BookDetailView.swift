import SwiftUI
import SwiftData
import LegadoRuleEngine

public struct BookDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let source: BookSource
    let bookUrl: String
    let name: String
    let author: String
    let intro: String
    var coverUrl: String = ""

    @State private var readerVM: ReaderViewModel?
    @State private var openReader = false

    public init(source: BookSource, bookUrl: String, name: String, author: String, intro: String, coverUrl: String = "") {
        self.source = source
        self.bookUrl = bookUrl
        self.name = name
        self.author = author
        self.intro = intro
        self.coverUrl = coverUrl
    }

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(alignment: .top, spacing: 12) {
                        CoverImageView(url: coverUrl, headers: source.parsedHeaderMap())
                            .frame(width: 80, height: 112)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(name).font(.title2.bold())
                            Text(author).foregroundStyle(.secondary)
                        }
                    }
                    if !intro.isEmpty { Text(intro).font(.footnote) }
                    Button {
                        addToShelf()
                        openReader = true
                    } label: {
                        Label("加入书架并阅读", systemImage: "book")
                    }
                }

                Section("目录 (\(readerVM?.chapters.count ?? 0))") {
                    if let vm = readerVM {
                        if vm.isLoadingToc {
                            ProgressView()
                        } else {
                            ForEach(Array(vm.chapters.enumerated()), id: \.offset) { idx, chapter in
                                Button(chapter.name) {
                                    addToShelf()
                                    Task { await vm.openChapter(at: idx) }
                                    openReader = true
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("详情")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
            }
            .task {
                let vm = ReaderViewModel(source: source)
                readerVM = vm
                await vm.loadToc(bookUrl: bookUrl)
            }
            .navigationDestination(isPresented: $openReader) {
                if let vm = readerVM {
                    ReaderView(viewModel: vm, bookUrl: bookUrl, bookName: name)
                }
            }
        }
    }

    private func addToShelf() {
        let url = bookUrl
        let descriptor = FetchDescriptor<ShelfBook>(predicate: #Predicate { $0.bookUrl == url })
        if (try? context.fetch(descriptor).first) == nil {
            let book = ShelfBook(bookUrl: bookUrl, sourceUrl: source.bookSourceUrl, name: name, author: author, intro: intro, coverUrl: coverUrl)
            context.insert(book)
            try? context.save()
        }
    }
}
