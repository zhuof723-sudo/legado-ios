import SwiftUI
import SwiftData
import Observation
import LegadoRuleEngine

private struct BrowseBook: Identifiable {
    let sourceURL: String
    let sourceName: String
    let name: String
    let author: String
    let intro: String
    let kind: String
    let lastChapter: String
    let bookURL: String
    let coverURL: String

    var id: String { sourceURL + "|" + bookURL + "|" + name + "|" + author }
}

private enum BrowseBoardPhase: Equatable {
    case idle, loading, loaded, failed
}

private struct BrowseBoard: Identifiable {
    let kind: ExploreKindInfo
    var books: [BrowseBook] = []
    var phase: BrowseBoardPhase = .idle
    var errorMessage: String?
    var id: String { kind.id }
}

private struct BrowseSelection: Identifiable {
    let book: BrowseBook
    let source: BookSource
    var id: String { book.id }
}

@MainActor
@Observable
private final class BrowseExploreModel {
    var boards: [BrowseBoard] = []
    var isLoading = false
    var errorMessage: String?

    private var selectedSource: BookSource?
    private var generation = UUID()
    private var queue: [String] = []
    private var isPumping = false

    func load(source: BookSource, boardLimit: Int, seed: Int) async {
        generation = UUID()
        selectedSource = source
        queue.removeAll()
        isPumping = false
        isLoading = true
        errorMessage = nil
        boards = []
        defer { isLoading = false }

        let runtime = BookSourceRuntime(source)
        let rawKinds = runtime.exploreKinds().filter {
            $0.type.lowercased() == "url" && !$0.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        var seenKinds = Set<String>()
        let uniqueKinds = rawKinds.filter { seenKinds.insert($0.id).inserted }
        guard !uniqueKinds.isEmpty else {
            errorMessage = source.exploreUrl?.isEmpty == false
                ? "该书源的发现分类未能解析，请在测试配置中检查 exploreUrl。"
                : "该书源没有配置发现地址。"
            return
        }

        let ordered = randomized(uniqueKinds, seed: seed)
        boards = ordered.prefix(min(max(boardLimit, 2), 10)).map { BrowseBoard(kind: $0) }
    }

    func loadSection(_ id: String) {
        guard let index = boards.firstIndex(where: { $0.id == id }) else { return }
        guard boards[index].phase == .idle || boards[index].phase == .failed else { return }
        guard !queue.contains(id) else { return }
        boards[index].phase = .idle
        boards[index].errorMessage = nil
        queue.append(id)
        pumpQueue()
    }

    func retrySection(_ id: String) {
        guard let index = boards.firstIndex(where: { $0.id == id }) else { return }
        boards[index].phase = .idle
        boards[index].errorMessage = nil
        loadSection(id)
    }

    private func pumpQueue() {
        guard !isPumping, let id = queue.first,
              let source = selectedSource,
              let index = boards.firstIndex(where: { $0.id == id }) else { return }
        isPumping = true
        boards[index].phase = .loading
        let kind = boards[index].kind
        let token = generation

        Task { [weak self] in
            guard let self else { return }
            do {
                let runtime = BookSourceRuntime(source)
                let values = try await runtime.explore(kind, resultLimit: 24)
                guard !Task.isCancelled, self.generation == token, self.queue.first == id else { return }
                let books = values.map {
                    BrowseBook(
                        sourceURL: source.bookSourceUrl,
                        sourceName: source.bookSourceName,
                        name: $0.name,
                        author: $0.author,
                        intro: $0.intro,
                        kind: $0.kind,
                        lastChapter: $0.lastChapter,
                        bookURL: $0.bookUrl,
                        coverURL: $0.coverUrl
                    )
                }
                self.finish(id: id, books: books, error: nil)
            } catch {
                guard self.generation == token, self.queue.first == id else { return }
                self.finish(id: id, books: [], error: error.localizedDescription)
            }
        }
    }

    private func finish(id: String, books: [BrowseBook], error: String?) {
        if queue.first == id { queue.removeFirst() }
        if let index = boards.firstIndex(where: { $0.id == id }) {
            boards[index].books = books
            boards[index].phase = error == nil ? .loaded : .failed
            boards[index].errorMessage = error
        }
        isPumping = false
        pumpQueue()
    }

    private func randomized(_ values: [ExploreKindInfo], seed: Int) -> [ExploreKindInfo] {
        values.sorted { score($0.id, seed: seed) < score($1.id, seed: seed) }
    }

    private func score(_ value: String, seed: Int) -> UInt64 {
        var hash = UInt64(bitPattern: Int64(seed)) ^ 0xcbf29ce484222325
        for scalar in value.unicodeScalars {
            hash ^= UInt64(scalar.value)
            hash = hash &* 0x100000001b3
        }
        return hash
    }
}

struct BrowseView: View {
    @Query(sort: [SortDescriptor(\BookSourceRecord.bookSourceName)])
    private var allSources: [BookSourceRecord]

    @State private var model = BrowseExploreModel()
    @State private var showSearch = false
    @State private var showSourcePicker = false
    @State private var selectedBook: BrowseSelection?
    @State private var selectedBoard: BrowseBoard?
    @State private var refreshSeed = Int(Date().timeIntervalSince1970)
    @State private var refreshNotice = false

    @AppStorage("browse.sourceURL") private var selectedSourceURL = ""
    @AppStorage("browse.rankLayout") private var rankLayout = 0
    @AppStorage("browse.rankVerticalCount") private var verticalCount = 4
    @AppStorage("browse.rankHorizontalCount") private var horizontalCount = 4

    private var enabledSources: [BookSourceRecord] { allSources.filter(\.enabled) }
    private var activeRecord: BookSourceRecord? {
        enabledSources.first(where: { $0.bookSourceUrl == selectedSourceURL })
    }
    private var activeSource: BookSource? { activeRecord?.decodeSource() }
    private var selectedSourceName: String { activeRecord?.bookSourceName ?? "切换书源" }
    private var effectiveLayout: Int { rankLayout == 2 ? abs(refreshSeed % 2) : rankLayout }
    private var taskKey: String {
        "\(selectedSourceURL)|\(refreshSeed)|\(horizontalCount)"
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Color(.systemGroupedBackground).ignoresSafeArea()
                Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 26) {
                        topControls
                        searchEntry
                        if model.isLoading && model.boards.isEmpty {
                            loadingView
                        } else if let error = model.errorMessage, model.boards.isEmpty {
                            errorView(error)
                        } else {
                            if let featured = model.boards.first { featuredSection(featured) }
                            boardSection
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 110)
                }
                .refreshable { refreshBrowse() }

                if refreshNotice {
                    Text("正在刷新书源发现")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.black.opacity(0.76), in: Capsule())
                        .padding(.bottom, 82)
                        .transition(.opacity)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .task(id: taskKey) { await loadExplore() }
            .fullScreenCover(isPresented: $showSearch) {
                SearchView(sourceURLFilter: selectedSourceURL.isEmpty ? nil : selectedSourceURL)
            }
            .sheet(isPresented: $showSourcePicker) {
                BrowseSourcePicker(sources: enabledSources, selection: $selectedSourceURL)
                    .presentationDetents([.medium, .large])
            }
            .sheet(item: $selectedBook) { selection in
                BookDetailView(
                    source: selection.source,
                    bookUrl: selection.book.bookURL,
                    name: selection.book.name,
                    author: selection.book.author,
                    intro: selection.book.intro,
                    coverUrl: selection.book.coverURL
                )
            }
            .sheet(item: $selectedBoard) { board in
                BrowseBoardSheet(board: board, source: activeSource, onSelect: openBook)
            }
            .onAppear { ensureSourceSelection() }
        }
    }

    private var topControls: some View {
        HStack(spacing: 10) {
            Button { showSourcePicker = true } label: {
                HStack(spacing: 7) {
                    Image(systemName: "books.vertical")
                    Text(selectedSourceName).lineLimit(1)
                    Image(systemName: "chevron.down").font(.caption2)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 14)
                .frame(height: 46)
                .background(.thinMaterial, in: Capsule())
            }
            .buttonStyle(.plain)

            Button { refreshBrowse() } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.blue)
                    .frame(width: 46, height: 46)
                    .background(.thinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(activeSource == nil)
            .accessibilityLabel("刷新发现")

            Spacer(minLength: 4)

            Menu {
                Picker("榜单排列方式", selection: $rankLayout) {
                    Label("横向滑动", systemImage: "rectangle.3.group").tag(0)
                    Label("竖向排列", systemImage: "list.bullet.rectangle").tag(1)
                    Label("随机排列", systemImage: "shuffle").tag(2)
                }
                Picker("竖排展示数", selection: $verticalCount) {
                    ForEach(2...10, id: \.self) { Text("\($0) 本").tag($0) }
                }
                Picker("横滑榜单数", selection: $horizontalCount) {
                    ForEach(2...10, id: \.self) { Text("\($0) 个").tag($0) }
                }
                Divider()
                Button("随机刷新发现", systemImage: "shuffle") { refreshBrowse() }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(.blue)
                    .frame(width: 52, height: 52)
                    .background(.thinMaterial, in: Circle())
            }
        }
    }

    private var searchEntry: some View {
        Button { showSearch = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.primary)
                Text("搜索书名、作者、网址或关键字")
                    .font(.body).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 18)
            .frame(height: 58)
            .background(.thinMaterial, in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.7), lineWidth: 0.6))
            .shadow(color: .black.opacity(0.08), radius: 10, y: 5)
        }
        .buttonStyle(.plain)
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("正在加载 \(selectedSourceName) 的发现榜单…")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 70)
    }

    private func errorView(_ message: String) -> some View {
        ContentUnavailableView {
            Label("发现页暂无内容", systemImage: "safari")
        } description: {
            Text(message)
        } actions: {
            HStack {
                Button("切换书源") { showSourcePicker = true }
                Button("重新加载") { refreshBrowse() }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }

    private func featuredSection(_ board: BrowseBoard) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle(board.kind.title, trailing: board.books.isEmpty ? "" : "查看全部") {
                if !board.books.isEmpty { selectedBoard = board }
            }
            Group {
                switch board.phase {
                case .loaded where !board.books.isEmpty:
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(alignment: .top, spacing: 14) {
                            ForEach(board.books) { book in
                                Button { openBook(book) } label: {
                                    VStack(alignment: .leading, spacing: 7) {
                                        SmartCover(url: book.coverURL, title: book.name, headers: coverHeaders)
                                            .frame(width: 128, height: 172)
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                            .shadow(color: .black.opacity(0.12), radius: 7, y: 4)
                                        Text(book.name)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.primary).lineLimit(1)
                                        Text(book.kind.isEmpty ? book.author : book.kind)
                                            .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                    }
                                    .frame(width: 128, alignment: .leading)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 1)
                        .padding(.bottom, 4)
                    }
                case .failed:
                    sectionFailure(board)
                case .loaded:
                    sectionEmpty
                case .idle, .loading:
                    featuredLoading
                }
            }
        }
        .task { model.loadSection(board.id) }
    }

    private var boardSection: some View {
        let rankedBoards = Array(model.boards.dropFirst())
        return VStack(alignment: .leading, spacing: 14) {
            if !rankedBoards.isEmpty {
                sectionTitle("发现榜单", trailing: effectiveLayout == 0 ? "横向" : "竖向") {
                    rankLayout = effectiveLayout == 0 ? 1 : 0
                }
                if effectiveLayout == 0 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(alignment: .top, spacing: 16) {
                            ForEach(rankedBoards) { board in
                                boardView(board).frame(width: 326)
                            }
                        }
                        .padding(.horizontal, 1)
                        .padding(.bottom, 8)
                    }
                } else {
                    LazyVStack(spacing: 16) {
                        ForEach(rankedBoards) { board in boardView(board) }
                    }
                }
            }
        }
    }

    private func boardView(_ board: BrowseBoard) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(board.kind.title).font(.title3.bold()).lineLimit(1)
                Spacer()
                if !board.books.isEmpty {
                    Button("查看全部") { selectedBoard = board }
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 10)

            switch board.phase {
            case .loaded where !board.books.isEmpty:
                loadedRankRows(board)
            case .failed:
                sectionFailure(board)
            case .loaded:
                sectionEmpty
            case .idle, .loading:
                rankedLoading
            }
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.65), lineWidth: 0.6))
        .task { model.loadSection(board.id) }
    }

    private func loadedRankRows(_ board: BrowseBoard) -> some View {
        let visible = Array(board.books.prefix(min(max(verticalCount, 2), 10)))
        return VStack(spacing: 0) {
            ForEach(Array(visible.enumerated()), id: \.element.id) { index, book in
                Button { openBook(book) } label: {
                    HStack(spacing: 12) {
                        Text("\(index + 1)")
                            .font(.headline.bold()).foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(rankColor(index), in: RoundedRectangle(cornerRadius: 7))
                        SmartCover(url: book.coverURL, title: book.name, headers: coverHeaders)
                            .frame(width: 48, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(book.name).font(.headline).foregroundStyle(.primary).lineLimit(1)
                            Text(book.author).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                            if !book.intro.isEmpty {
                                Text(book.intro).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 9)
                }
                .buttonStyle(.plain)
                if index < visible.count - 1 { Divider().padding(.leading, 42) }
            }
        }
    }

    private var featuredLoading: some View {
        HStack(spacing: 14) {
            ForEach(0..<3, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 8) {
                    RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.12)).frame(width: 128, height: 172)
                    RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.12)).frame(width: 100, height: 14)
                }
            }
        }
        .redacted(reason: .placeholder)
        .overlay { ProgressView() }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
    }

    private var rankedLoading: some View {
        VStack(spacing: 12) {
            ForEach(0..<min(max(verticalCount, 2), 4), id: \.self) { _ in
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 7).fill(Color.secondary.opacity(0.12)).frame(width: 30, height: 30)
                    RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.12)).frame(width: 48, height: 64)
                    VStack(alignment: .leading, spacing: 8) {
                        RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.12)).frame(height: 14)
                        RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.10)).frame(width: 100, height: 11)
                    }
                }
            }
        }
        .redacted(reason: .placeholder)
        .overlay { ProgressView() }
    }

    private var sectionEmpty: some View {
        Text("该分类暂无书籍")
            .font(.footnote).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
    }

    private func sectionFailure(_ board: BrowseBoard) -> some View {
        VStack(spacing: 8) {
            Text(board.errorMessage ?? "加载失败")
                .font(.caption).foregroundStyle(.secondary).lineLimit(2)
            Button("重试") { model.retrySection(board.id) }
                .font(.footnote.weight(.semibold))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    private func sectionTitle(_ title: String, trailing: String, action: @escaping () -> Void) -> some View {
        HStack {
            Text(title).font(.title3.bold())
            Spacer()
            if !trailing.isEmpty {
                Button(action: action) {
                    HStack(spacing: 4) {
                        Text(trailing)
                        Image(systemName: "chevron.right")
                    }
                    .font(.subheadline).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var coverHeaders: [String: String] {
        activeSource?.parsedHeaderMap() ?? [:]
    }

    private func ensureSourceSelection() {
        verticalCount = min(max(verticalCount, 2), 10)
        horizontalCount = min(max(horizontalCount, 2), 10)
        if !selectedSourceURL.isEmpty, activeSource?.exploreUrl?.isEmpty == false { return }
        if let firstExplore = enabledSources.first(where: { $0.decodeSource()?.exploreUrl?.isEmpty == false }) {
            selectedSourceURL = firstExplore.bookSourceUrl
        } else {
            selectedSourceURL = enabledSources.first?.bookSourceUrl ?? ""
        }
    }

    private func loadExplore() async {
        ensureSourceSelection()
        guard let source = activeSource else {
            model.boards = []
            model.errorMessage = "请先启用并选择一个书源。"
            return
        }
        await model.load(source: source, boardLimit: horizontalCount, seed: refreshSeed)
    }

    private func refreshBrowse() {
        refreshSeed = Int.random(in: 1...Int.max / 4)
        refreshNotice = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { refreshNotice = false }
    }

    private func openBook(_ book: BrowseBook) {
        guard let source = activeSource else { return }
        CrashReporter.shared.breadcrumb(
            level: "info",
            tag: "browse-explore",
            message: "点击发现书籍：\(book.name) · \(book.sourceName) · \(String(book.bookURL.prefix(500)))"
        )
        selectedBook = BrowseSelection(book: book, source: source)
    }

    private func rankColor(_ index: Int) -> Color {
        switch index {
        case 0: return .red
        case 1: return .orange
        case 2: return Color(red: 0.98, green: 0.72, blue: 0.08)
        default: return .gray.opacity(0.72)
        }
    }
}

private struct BrowseSourcePicker: View {
    @Environment(\.dismiss) private var dismiss
    let sources: [BookSourceRecord]
    @Binding var selection: String
    @State private var query = ""

    private var filtered: [BookSourceRecord] {
        sources.filter {
            let source = $0.decodeSource()
            let hasExplore = source?.exploreUrl?.isEmpty == false
            let matches = query.isEmpty || $0.bookSourceName.localizedCaseInsensitiveContains(query)
                || $0.bookSourceUrl.localizedCaseInsensitiveContains(query)
            return hasExplore && matches
        }
    }

    var body: some View {
        NavigationStack {
            List(filtered) { source in
                Button {
                    selection = source.bookSourceUrl
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: selection == source.bookSourceUrl ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selection == source.bookSourceUrl ? .blue : .secondary)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(source.bookSourceName).foregroundStyle(.primary)
                            Text(source.bookSourceUrl)
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
            }
            .overlay {
                if filtered.isEmpty {
                    ContentUnavailableView(
                        "没有发现书源",
                        systemImage: "safari",
                        description: Text("只有配置 exploreUrl 且已启用的书源会显示在这里。")
                    )
                }
            }
            .listStyle(.plain)
            .searchable(text: $query, prompt: "搜索发现书源")
            .navigationTitle("切换书源")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}

private struct BrowseBoardSheet: View {
    @Environment(\.dismiss) private var dismiss
    let board: BrowseBoard
    let source: BookSource?
    let onSelect: (BrowseBook) -> Void

    var body: some View {
        NavigationStack {
            List(board.books) { book in
                Button {
                    dismiss()
                    DispatchQueue.main.async { onSelect(book) }
                } label: {
                    HStack(spacing: 12) {
                        SmartCover(url: book.coverURL, title: book.name, headers: source?.parsedHeaderMap() ?? [:])
                            .frame(width: 48, height: 66)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(book.name).font(.headline).foregroundStyle(.primary).lineLimit(1)
                            Text(book.author).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                            if !book.intro.isEmpty {
                                Text(book.intro).font(.caption2).foregroundStyle(.tertiary).lineLimit(2)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
            .navigationTitle(board.kind.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}
