import SwiftUI
import SwiftData
import LegadoRuleEngine

/// 书籍详情页（对照设计稿重新设计）
struct BookDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage("app.themeMode") private var themeMode: String = AppThemeMode.light.rawValue

    let source: BookSource
    let bookUrl: String
    let name: String
    let author: String
    let intro: String
    var coverUrl: String = ""

    @State private var readerVM: ReaderViewModel?
    @State private var openReader = false
    @State private var isStartingReading = false
    @State private var startError: String?
    @State private var expanded = false
    @State private var headerCache = HeaderCacheBox()
    @State private var inShelf = false

    var mode: AppThemeMode {
        AppThemeMode(rawValue: themeMode) ?? .light
    }

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
                VStack(alignment: .leading, spacing: 20) {
                    headerSection
                    bookInfoCard
                    actionButtons
                    if let startError {
                        errorBanner(startError)
                    }
                    progressSection
                    introSection
                    Spacer().frame(height: 40)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 40)
            }
            .background(Theme.bg(for: mode).ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                if readerVM == nil {
                    readerVM = ReaderViewModel(source: source, persistentBookURL: shelfBook?.bookUrl)
                }
                inShelf = shelfBook != nil
            }
            .fullScreenCover(isPresented: $openReader) {
                if let vm = readerVM {
                    ReaderView(
                        viewModel: vm,
                        bookUrl: bookUrl,
                        bookName: name,
                        bookAuthor: author,
                        coverURL: coverUrl
                    )
                }
            }
        }
    }

    // MARK: - 顶部导航

    private var headerSection: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary(for: mode))
                    .frame(width: 36, height: 36)
                    .glassCircle(mode: mode)
            }
            Spacer()
            Menu {
                Button { toggleShelf() } label: {
                    Label(inShelf ? "移出书架" : "加入书架",
                          systemImage: inShelf ? "minus.circle" : "plus.circle")
                }
                Button { } label: {
                    Label("分享", systemImage: "square.and.arrow.up")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary(for: mode))
                    .frame(width: 36, height: 36)
                    .glassCircle(mode: mode)
            }
        }
        .padding(.top, 4)
    }

    // MARK: - 书籍信息卡片

    private var bookInfoCard: some View {
        HStack(alignment: .top, spacing: 16) {
            SmartCover(url: coverUrl, title: name, headers: headers, mode: mode)
                .frame(width: 110, height: 152)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(color: Theme.shadow(for: mode), radius: 8, y: 4)
            VStack(alignment: .leading, spacing: 8) {
                Text(name)
                    .font(.title2.bold())
                    .foregroundStyle(Theme.textPrimary(for: mode))
                    .lineLimit(2)
                Text(author)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary(for: mode))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    ForEach(0..<5, id: \.self) { i in
                        Image(systemName: i < 4 ? "star.fill" : "star")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.accent)
                    }
                    Text("书源图书")
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary(for: mode))
                }
                if totalChapters > 0 {
                    Text("共 \(totalChapters) 章")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary(for: mode))
                }
                Text(source.bookSourceName)
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Theme.accent.opacity(0.12))
                    .foregroundStyle(Theme.accent)
                    .clipShape(Capsule())
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .cardStyle(cornerRadius: 16, mode: mode)
    }

    // MARK: - 操作按钮

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button {
                Task { await startReading() }
            } label: {
                HStack {
                    if isStartingReading {
                        ProgressView().tint(.white)
                    } else {
                        Text(shelfBook?.lastReadAt != nil ? "继续阅读" : "开始阅读")
                            .font(.subheadline.bold())
                        if shelfBook?.lastReadAt != nil {
                            Text("· 第\(min((shelfBook?.lastReadChapterIndex ?? 0) + 1, max(totalChapters, 1)))章")
                                .font(.caption2)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
            }
            .disabled(isStartingReading)
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)

            Button {
                toggleShelf()
            } label: {
                Image(systemName: inShelf ? "checkmark.circle.fill" : "plus.circle")
                    .font(.system(size: 20))
                    .foregroundStyle(inShelf ? Theme.accent : Theme.textSecondary(for: mode))
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(Theme.cardBg(for: mode))
                            .shadow(color: Theme.shadow(for: mode), radius: 4, y: 2)
                    )
            }
        }
    }

    // MARK: - 错误提示

    private func errorBanner(_ message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.footnote)
                .foregroundStyle(Theme.textPrimary(for: mode))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.red.opacity(0.1))
        )
    }

    // MARK: - 阅读进度

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("阅读进度")
                    .font(.subheadline.bold())
                    .foregroundStyle(Theme.textPrimary(for: mode))
                Spacer()
                if totalChapters > 0 {
                    Text("\(Int((progress * 100).rounded()))%")
                        .font(.caption.bold())
                        .foregroundStyle(Theme.accent)
                }
            }
            MiniProgressBar(progress: progress)
            HStack {
                statCell("\(min((shelfBook?.lastReadChapterIndex ?? 0) + 1, max(totalChapters, 1)))", "已读章节")
                Divider().frame(height: 26).background(Theme.hairline(for: mode))
                statCell("\(totalChapters)", "总章节")
                Divider().frame(height: 26).background(Theme.hairline(for: mode))
                statCell(source.bookSourceType == .text ? "文本" : "其他", "类型")
            }
        }
        .padding(16)
        .cardStyle(cornerRadius: 16, mode: mode)
    }

    private func statCell(_ value: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.subheadline.bold())
                .foregroundStyle(Theme.textPrimary(for: mode))
            Text(label)
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary(for: mode))
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 简介

    private var introSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("简介")
                .font(.subheadline.bold())
                .foregroundStyle(Theme.textPrimary(for: mode))
            Text(intro.isEmpty ? "暂无简介" : intro)
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary(for: mode))
                .lineSpacing(4)
                .lineLimit(expanded ? nil : 3)
            if !intro.isEmpty {
                Button(expanded ? "收起" : "展开") { withAnimation { expanded.toggle() } }
                    .font(.caption.bold())
                    .foregroundStyle(Theme.accent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .cardStyle(cornerRadius: 16, mode: mode)
    }

    private var headers: [String: String] {
        if let cached = headerCache.storage[source.bookSourceUrl] { return cached }
        let h = source.parsedHeaderMap()
        headerCache.storage[source.bookSourceUrl] = h
        return h
    }

    // MARK: - 操作

    @MainActor
    private func ensureShelfBook() throws -> ShelfBook {
        if let existing = shelfBook { return existing }
        let book = ShelfBook(
            bookUrl: bookUrl,
            sourceUrl: source.bookSourceUrl,
            name: name,
            author: author,
            intro: intro,
            coverUrl: coverUrl
        )
        context.insert(book)
        try context.save()
        CrashReporter.shared.breadcrumb(level: "info", tag: "shelf", message: "用户手动加入书架：\(name)")
        return book
    }

    @MainActor
    private func toggleShelf() {
        if inShelf {
            // 移出书架
            if let book = shelfBook {
                context.delete(book)
                try? context.save()
                inShelf = false
            }
        } else {
            // 加入书架
            do {
                let _ = try ensureShelfBook()
                readerVM?.enablePersistentCache(bookURL: bookUrl)
                inShelf = true
                startError = nil
            } catch {
                startError = "加入书架失败：\(error.localizedDescription)"
            }
        }
    }

    @MainActor
    private func startReading() async {
        guard !isStartingReading else { return }
        isStartingReading = true
        startError = nil

        do {
            let _ = try ensureShelfBook()
            await readerVM?.loadToc(bookUrl: bookUrl)
            if let book = shelfBook {
                book.totalChapters = readerVM?.chapters.count ?? 0
                try? context.save()
                let idx = min(max(book.lastReadChapterIndex, 0), max((readerVM?.chapters.count ?? 1) - 1, 0))
                await readerVM?.openChapter(at: idx)
            }
            isStartingReading = false
            openReader = true
        } catch {
            isStartingReading = false
            startError = "打开失败：\(error.localizedDescription)"
        }
    }
}
