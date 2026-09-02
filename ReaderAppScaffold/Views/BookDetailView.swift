import SwiftUI
import SwiftData
import LegadoRuleEngine

/// 书籍详情页（对照设计稿：封面信息卡 + 继续阅读 + 进度卡 + 简介）
struct BookDetailView: View {
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
    @State private var expanded = false
    @State private var headerCache = HeaderCacheBox()

    init(source: BookSource, bookUrl: String, name: String, author: String,
         intro: String, coverUrl: String = "") {
        self.source = source
        self.bookUrl = bookUrl
        self.name = name
        self.author = author
        self.intro = intro
        self.coverUrl = coverUrl
    }

    private var shelfBook: ShelfBook? {
        let url = bookUrl
        let descriptor = FetchDescriptor<ShelfBook>(predicate: #Predicate { $0.bookUrl == url })
        return try? context.fetch(descriptor).first
    }

    private var totalChapters: Int {
        readerVM?.chapters.count ?? shelfBook?.totalChapters ?? 0
    }

    private var progress: Double {
        guard totalChapters > 0 else { return 0 }
        let idx = shelfBook?.lastReadChapterIndex ?? 0
        return Double(min(idx + 1, totalChapters)) / Double(totalChapters)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    topBar
                    headerCard
                    actionButtons
                    progressCard
                    introSection
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 40)
            }
            .background(Theme.bg.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .task {
                guard readerVM == nil else { return }
                let vm = ReaderViewModel(source: source)
                readerVM = vm
                await vm.loadToc(bookUrl: bookUrl)
                if let book = shelfBook {
                    book.totalChapters = vm.chapters.count
                    try? context.save()
                }
            }
            .navigationDestination(isPresented: $openReader) {
                if let vm = readerVM {
                    ReaderView(viewModel: vm, bookUrl: bookUrl, bookName: name)
                }
            }
        }
    }

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.white))
            }
            Spacer()
            Image(systemName: "ellipsis")
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color.white))
        }
        .padding(.top, 4)
    }

    private var headerCard: some View {
        HStack(alignment: .top, spacing: 14) {
            SmartCover(url: coverUrl, title: name, headers: headers)
                .frame(width: 104, height: 144)
                .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
            VStack(alignment: .leading, spacing: 7) {
                Text(name).font(.title3.bold()).lineLimit(2)
                Text(author).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                Label(source.bookSourceName, systemImage: "tray.full")
                    .font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                if totalChapters > 0 {
                    Label("共 \(totalChapters) 章", systemImage: "list.bullet")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                HStack(spacing: 3) {
                    ForEach(0..<5, id: \.self) { i in
                        Image(systemName: "star.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.accent.opacity(i < 4 ? 1 : 0.35))
                    }
                    Text("书源图书").font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button {
                addToShelf()
                openReader = true
            } label: {
                VStack(spacing: 2) {
                    Text(shelfBook?.lastReadAt != nil ? "继续阅读" : "开始阅读")
                        .font(.subheadline.bold())
                    if let book = shelfBook, totalChapters > 0 {
                        Text("第 \(min(book.lastReadChapterIndex + 1, totalChapters)) 章 / \(totalChapters) 章")
                            .font(.caption2)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
            }
            .prominentGlassButton()
            .tint(Theme.accent)
            .foregroundStyle(.white)

            Button {
                addToShelf()
            } label: {
                Label(shelfBook != nil ? "已在书架" : "加入书架", systemImage: shelfBook != nil ? "checkmark" : "book")
                    .font(.subheadline.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
            }
            .plainGlassButton()
            .tint(.primary)
        }
    }

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("阅读进度").font(.subheadline.bold())
                Spacer()
                Text("\(Int((progress * 100).rounded()))%")
                    .font(.caption.bold()).foregroundStyle(Theme.accent)
            }
            MiniProgressBar(progress: progress)
            HStack {
                statCell("\(min((shelfBook?.lastReadChapterIndex ?? 0) + 1, max(totalChapters, 1)))", "已读章节")
                Divider().frame(height: 26)
                statCell("\(totalChapters)", "总章节")
                Divider().frame(height: 26)
                statCell(source.bookSourceType == .text ? "文本" : "其他", "类型")
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.hairline, lineWidth: 0.5))
    }

    private func statCell(_ value: String, _ label: String) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.subheadline.bold()).foregroundStyle(.primary)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var introSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("简介").font(.subheadline.bold())
            Text(intro.isEmpty ? "暂无简介" : intro)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineSpacing(4)
                .lineLimit(expanded ? nil : 3)
            if !intro.isEmpty {
                Button(expanded ? "收起" : "展开") { expanded.toggle() }
                    .font(.caption.bold())
                    .foregroundStyle(Theme.accent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.hairline, lineWidth: 0.5))
    }

    private var headers: [String: String] {
        if let cached = headerCache.storage[source.bookSourceUrl] { return cached }
        let h = source.parsedHeaderMap()
        headerCache.storage[source.bookSourceUrl] = h
        return h
    }

    private func addToShelf() {
        if shelfBook == nil {
            let book = ShelfBook(
                bookUrl: bookUrl, sourceUrl: source.bookSourceUrl,
                name: name, author: author, intro: intro, coverUrl: coverUrl
            )
            context.insert(book)
        }
        try? context.save()
    }
}
