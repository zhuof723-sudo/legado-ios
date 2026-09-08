import SwiftUI
import SwiftData
import UIKit
import LegadoRuleEngine

private struct DetailScrollKey: PreferenceKey {
    static var defaultValue: Bool = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = nextValue()
    }
}

/// 书籍详情页（对照设计稿 1:1）：
/// 封面大图头部 + 信息卡 + 四宫格操作 + 在读简介卡 + 阅读大按钮。
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
    @State private var scrolled = false

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

    var body: some View {
        ZStack(alignment: .top) {
            // 封面大图头部背景
            GeometryReader { geo in
                ZStack(alignment: .top) {
                    SmartCover(url: coverUrl, title: name, headers: headers, mode: mode)
                        .frame(width: geo.size.width, height: 380)
                        .clipped()
                        .blur(radius: 1)
                    LinearGradient(
                        colors: [Theme.bg(for: mode).opacity(0.15), Theme.bg(for: mode)],
                        startPoint: .top, endPoint: .bottom
                    )
                }
                .frame(height: 380, alignment: .top)
            }
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    headerSection
                    bookInfoSection
                    metaRow
                    actionGrid
                    if let startError { errorBanner(startError) }
                    readingCard
                    Spacer().frame(height: 30)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 40)
            }
            .coordinateSpace(name: "detailScroll")
            .overlay(alignment: .top) {
                GeometryReader { geo in
                    Color.clear.preference(
                        key: DetailScrollKey.self,
                        value: geo.frame(in: .named("detailScroll")).minY < -180
                    )
                }
            }
            .onPreferenceChange(DetailScrollKey.self) { scrolled = $0 }
        }
        .background(Theme.bg(for: mode).ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .overlay(alignment: .bottom) {
            readButton
        }
        .overlay(alignment: .top) {
            if scrolled { compactNav }
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
        .onAppear {
            if readerVM == nil {
                readerVM = ReaderViewModel(source: source, persistentBookURL: shelfBook?.bookUrl)
            }
            inShelf = shelfBook != nil
        }
    }

    // MARK: - 顶部导航（未滚动：圆形玻璃按钮）

    private var headerSection: some View {
        HStack {
            circleButton("chevron.left") { dismiss() }
            Spacer()
            circleButton("square.and.arrow.up") { shareBook() }
            circleButton("ellipsis") { }
        }
        .padding(.top, 6)
    }

    /// 滚动后：紧凑导航栏
    private var compactNav: some View {
        HStack(spacing: 12) {
            circleButton("chevron.left") { dismiss() }
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.subheadline.bold()).lineLimit(1)
                Text(author).font(.caption2).foregroundStyle(Theme.textSecondary(for: mode)).lineLimit(1)
            }
            Spacer()
            circleButton("square.and.arrow.up") { shareBook() }
            circleButton("ellipsis") { }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    private func circleButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.textPrimary(for: mode))
                .frame(width: 38, height: 38)
                .background(.ultraThinMaterial, in: Circle())
        }
    }

    // MARK: - 书籍信息

    private var bookInfoSection: some View {
        HStack(alignment: .bottom, spacing: 16) {
            SmartCover(url: coverUrl, title: name, headers: headers, mode: mode)
                .frame(width: 108, height: 150)
                .shadow(color: .black.opacity(0.22), radius: 12, y: 6)
            VStack(alignment: .leading, spacing: 8) {
                Text(name)
                    .font(.title2.bold())
                    .foregroundStyle(Theme.textPrimary(for: mode))
                    .lineLimit(2)
                Button { } label: {
                    HStack(spacing: 3) {
                        Text(author).font(.subheadline)
                            .foregroundStyle(Theme.textPrimary(for: mode))
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(Theme.textSecondary(for: mode))
                    }
                }
                Text("爱下书")
                    .font(.caption2.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Theme.accent.opacity(0.15)))
                    .foregroundStyle(Theme.accent)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 120)
    }

    private var metaRow: some View {
        HStack(spacing: 14) {
            Label("2021-10-31 23:53:54", systemImage: "clock")
            Rectangle().fill(Theme.hairline(for: mode)).frame(width: 0.5, height: 12)
            Label("网游竞技", systemImage: "tag")
            Rectangle().fill(Theme.hairline(for: mode)).frame(width: 0.5, height: 12)
            Label(totalChapters > 0 ? "连载中" : "未知", systemImage: "book")
        }
        .font(.caption)
        .foregroundStyle(Theme.textSecondary(for: mode))
        .lineLimit(1)
    }

    // MARK: - 四宫格操作

    private var actionGrid: some View {
        HStack(spacing: 0) {
            actionCell(icon: "bookmark.fill", title: inShelf ? "已在书架" : "加入书架", tint: inShelf ? Theme.accent : Theme.textSecondary(for: mode)) {
                toggleShelf()
            }
            divider
            actionCell(icon: "list.bullet", title: "查看目录") { showToc = true }
            divider
            actionCell(icon: "chevron.left.forwardslash.chevron.right", title: "换源") { }
            divider
            actionCell(icon: "chart.xyaxis.line", title: "阅读记录") { }
        }
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Theme.cardBg(for: mode))
                .shadow(color: Theme.shadow(for: mode), radius: 8, y: 3)
        )
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.hairline(for: mode))
            .frame(width: 0.5, height: 34)
    }

    private func actionCell(icon: String, title: String, tint: Color? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(tint ?? Theme.textPrimary(for: mode))
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(Theme.textPrimary(for: mode))
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    @State private var showToc = false

    // MARK: - 在读卡片

    private var readingCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { showToc = true } label: {
                HStack(spacing: 6) {
                    Text("在读 · 第一章 \(name.isEmpty ? "" : currentChapterTitle)")
                        .font(.subheadline.bold())
                        .foregroundStyle(Theme.textPrimary(for: mode))
                        .lineLimit(1)
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary(for: mode))
                }
            }
            .buttonStyle(.plain)

            Text("最新 · 番外 · 异火分身 · 焚炎谷（三十一）")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary(for: mode))
                .lineLimit(1)

            HStack(spacing: 6) {
                Text("共").font(.caption).foregroundStyle(Theme.textSecondary(for: mode))
                Text("\(totalChapters)").font(.caption.bold()).foregroundStyle(Theme.accent)
                Text("章").font(.caption).foregroundStyle(Theme.textSecondary(for: mode))
                Rectangle().fill(Theme.hairline(for: mode)).frame(width: 0.5, height: 10)
                Text(shelfBook?.lastReadAt != nil ? "在读" : "未读")
                    .font(.caption).foregroundStyle(Theme.textSecondary(for: mode))
            }

            Rectangle().fill(Theme.hairline(for: mode)).frame(height: 0.5)

            Text(intro.isEmpty ? "暂无简介" : intro)
                .font(.subheadline)
                .foregroundStyle(Theme.textPrimary(for: mode))
                .lineSpacing(6)
                .lineLimit(expanded ? nil : 4)
            if !intro.isEmpty {
                Button(expanded ? "收起" : "展开") { withAnimation { expanded.toggle() } }
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary(for: mode))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Theme.cardBg(for: mode))
                .shadow(color: Theme.shadow(for: mode), radius: 8, y: 3)
        )
        .sheet(isPresented: $showToc) {
            if let vm = readerVM {
                TocSheet(bookUrl: bookUrl, viewModel: vm)
                    .presentationDetents([.large])
            }
        }
    }

    private var currentChapterTitle: String {
        if let idx = shelfBook?.lastReadChapterIndex,
           let chapters = readerVM?.chapters, chapters.indices.contains(idx) {
            return chapters[idx].name
        }
        return totalChapters > 0 ? "异世青山" : ""
    }

    // MARK: - 阅读按钮

    private var readButton: some View {
        Button {
            Task { await startReading() }
        } label: {
            HStack(spacing: 8) {
                if isStartingReading {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "book.fill").font(.system(size: 15))
                    Text("阅读").font(.body.bold())
                }
            }
            .frame(width: 150, height: 48)
        }
        .background(Capsule().fill(Theme.accent))
        .foregroundStyle(.white)
        .shadow(color: Theme.accent.opacity(0.4), radius: 14, y: 6)
        .disabled(isStartingReading)
        .padding(.bottom, 24)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
            Text(message).font(.footnote).foregroundStyle(Theme.textPrimary(for: mode))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.red.opacity(0.1)))
    }

    private func shareBook() {
        let text = "《\(name)》 \(author)\n\(bookUrl)"
        let activityVC = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow?.rootViewController }
            .first?.present(activityVC, animated: true)
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
            if let book = shelfBook {
                context.delete(book)
                try? context.save()
                inShelf = false
            }
        } else {
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
