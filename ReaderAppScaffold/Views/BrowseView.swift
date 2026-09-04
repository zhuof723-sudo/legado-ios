import SwiftUI
import SwiftData
import LegadoRuleEngine

struct BrowseView: View {
    @Query(sort: [SortDescriptor(\BookSourceRecord.bookSourceName)])
    private var allSources: [BookSourceRecord]

    @State private var showSearch = false
    @State private var showSourcePicker = false
    @State private var quickRequest: QuickSearchRequest?
    @State private var refreshSeed = Int(Date().timeIntervalSince1970)
    @State private var refreshNotice = false

    @AppStorage("browse.sourceURL") private var selectedSourceURL = ""
    @AppStorage("browse.rankLayout") private var rankLayout = 0
    @AppStorage("browse.rankVerticalCount") private var verticalCount = 4
    @AppStorage("browse.rankHorizontalCount") private var horizontalCount = 4

    private var enabledSources: [BookSourceRecord] { allSources.filter(\.enabled) }
    private var sourceFilter: String? { selectedSourceURL.isEmpty ? nil : selectedSourceURL }
    private var selectedSourceName: String {
        guard !selectedSourceURL.isEmpty else { return "全部书源" }
        return enabledSources.first(where: { $0.bookSourceUrl == selectedSourceURL })?.bookSourceName ?? "全部书源"
    }
    private var effectiveLayout: Int {
        rankLayout == 2 ? abs(refreshSeed % 2) : rankLayout
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Color(.systemGroupedBackground).ignoresSafeArea()
                Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 28) {
                        topControls
                        searchEntry
                        guessSection
                        rankingSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 110)
                }
                .refreshable { refreshBrowse() }

                if refreshNotice {
                    Text("浏览内容已随机刷新")
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
            .fullScreenCover(isPresented: $showSearch) {
                SearchView(sourceURLFilter: sourceFilter)
            }
            .sheet(isPresented: $showSourcePicker) {
                BrowseSourcePicker(sources: enabledSources, selection: $selectedSourceURL)
                    .presentationDetents([.medium, .large])
            }
            .sheet(item: $quickRequest) { request in
                QuickSearchSheet(keyword: request.keyword, sourceURLFilter: request.sourceURL)
            }
            .onAppear {
                verticalCount = min(max(verticalCount, 2), 10)
                horizontalCount = min(max(horizontalCount, 2), 10)
                if !selectedSourceURL.isEmpty,
                   !enabledSources.contains(where: { $0.bookSourceUrl == selectedSourceURL }) {
                    selectedSourceURL = ""
                }
            }
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
            .accessibilityLabel("刷新浏览")

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
                Button("随机排放", systemImage: "shuffle") { refreshBrowse() }
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
                    .font(.body)
                    .foregroundStyle(.secondary)
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

    private var guessSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("猜你喜欢", actionTitle: "换一批") { refreshBrowse() }
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(guessBooks) { book in
                        Button { openSearch(book.title) } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                PlaceholderCover(title: book.title)
                                    .frame(width: 128, height: 172)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .shadow(color: .black.opacity(0.12), radius: 7, y: 4)
                                Text(book.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text(book.tag)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            .frame(width: 128, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 1)
                .padding(.bottom, 4)
            }
        }
    }

    private var rankingSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("热门榜单", actionTitle: effectiveLayout == 0 ? "横向" : "竖向") {
                rankLayout = effectiveLayout == 0 ? 1 : 0
            }
            if effectiveLayout == 0 {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 16) {
                        ForEach(displayBoards) { board in
                            rankingBoard(board)
                                .frame(width: 326)
                        }
                    }
                    .padding(.horizontal, 1)
                    .padding(.bottom, 8)
                }
            } else {
                LazyVStack(spacing: 16) {
                    ForEach(displayBoards) { board in
                        rankingBoard(board)
                    }
                }
            }
        }
    }

    private func sectionTitle(_ title: String, actionTitle: String, action: @escaping () -> Void) -> some View {
        HStack {
            Text(title).font(.title3.bold())
            Spacer()
            Button(action: action) {
                HStack(spacing: 4) {
                    Text(actionTitle)
                    Image(systemName: "chevron.right")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    private func rankingBoard(_ board: RankingBoard) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(board.title).font(.title3.bold())
                Spacer()
                Button("查看全部") { openSearch(board.searchKeyword) }
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 10)

            ForEach(Array(rankedBooks(board).enumerated()), id: \.element.id) { index, book in
                Button { openSearch(book.title) } label: {
                    HStack(spacing: 12) {
                        Text("\(index + 1)")
                            .font(.headline.bold())
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(rankColor(index), in: RoundedRectangle(cornerRadius: 7))
                        PlaceholderCover(title: book.title)
                            .frame(width: 48, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(book.title)
                                .font(.headline)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Text(book.author)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 9)
                }
                .buttonStyle(.plain)
                if index < rankedBooks(board).count - 1 {
                    Divider().padding(.leading, 42)
                }
            }
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.65), lineWidth: 0.6))
    }

    private var guessBooks: [CuratedBook] {
        Array(randomized(BrowseCatalog.guesses, salt: 11).prefix(horizontalCount))
    }

    private var displayBoards: [RankingBoard] {
        Array(randomized(BrowseCatalog.boards, salt: 29).prefix(horizontalCount))
    }

    private func rankedBooks(_ board: RankingBoard) -> [CuratedBook] {
        Array(randomized(board.books, salt: stableHash(board.id)).prefix(verticalCount))
    }

    private func randomized<T: Identifiable>(_ values: [T], salt: Int) -> [T] where T.ID == String {
        values.sorted {
            stableHash($0.id, salt: salt) < stableHash($1.id, salt: salt)
        }
    }

    private func stableHash(_ value: String, salt: Int = 0) -> Int {
        var hash = UInt64(bitPattern: Int64(refreshSeed &+ salt)) ^ 0xcbf29ce484222325
        for scalar in value.unicodeScalars {
            hash ^= UInt64(scalar.value)
            hash = hash &* 0x100000001b3
        }
        return Int(truncatingIfNeeded: hash)
    }

    private func rankColor(_ index: Int) -> Color {
        switch index {
        case 0: return .red
        case 1: return .orange
        case 2: return Color(red: 0.97, green: 0.65, blue: 0.24)
        default: return .gray.opacity(0.72)
        }
    }

    private func openSearch(_ keyword: String) {
        quickRequest = QuickSearchRequest(keyword: keyword, sourceURL: sourceFilter)
    }

    private func refreshBrowse() {
        refreshSeed = Int.random(in: 1...Int.max / 4)
        refreshNotice = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            refreshNotice = false
        }
    }
}

private struct QuickSearchRequest: Identifiable {
    let keyword: String
    let sourceURL: String?
    var id: String { keyword + "|" + (sourceURL ?? "all") }
}

private struct CuratedBook: Identifiable {
    let title: String
    let author: String
    let tag: String
    var id: String { title + "|" + author }
}

private struct RankingBoard: Identifiable {
    let id: String
    let title: String
    let searchKeyword: String
    let books: [CuratedBook]
}

private enum BrowseCatalog {
    static let guesses: [CuratedBook] = [
        .init(title: "恶雌绑定吃好系统后", author: "青山", tag: "兽世 · 爽文"),
        .init(title: "十八岁全系法师", author: "云海", tag: "全员 · 高武"),
        .init(title: "逼我退队？下次面试", author: "墨雨", tag: "逆袭 · 玄幻"),
        .init(title: "师妹别卷了", author: "青木", tag: "仙侠 · 轻松"),
        .init(title: "我在精神病院学斩神", author: "三九音域", tag: "都市 · 高武"),
        .init(title: "十日终焉", author: "杀虫队队员", tag: "悬疑 · 无限流"),
        .init(title: "深海余烬", author: "远瞳", tag: "科幻 · 异世"),
        .init(title: "宿命之环", author: "爱潜水的乌贼", tag: "奇幻 · 悬疑"),
        .init(title: "大奉打更人", author: "卖报小郎君", tag: "仙侠 · 探案"),
        .init(title: "剑来", author: "烽火戏诸侯", tag: "武侠 · 仙侠")
    ]

    private static let classics: [CuratedBook] = [
        .init(title: "三体", author: "刘慈欣", tag: "科幻"),
        .init(title: "活着", author: "余华", tag: "文学"),
        .init(title: "平凡的世界", author: "路遥", tag: "文学"),
        .init(title: "围城", author: "钱锺书", tag: "经典"),
        .init(title: "白鹿原", author: "陈忠实", tag: "文学"),
        .init(title: "明朝那些事儿", author: "当年明月", tag: "历史"),
        .init(title: "长安的荔枝", author: "马伯庸", tag: "历史"),
        .init(title: "球状闪电", author: "刘慈欣", tag: "科幻"),
        .init(title: "许三观卖血记", author: "余华", tag: "文学"),
        .init(title: "人类简史", author: "尤瓦尔·赫拉利", tag: "历史")
    ]

    private static let webBooks: [CuratedBook] = [
        .init(title: "我不是戏神", author: "三九音域", tag: "都市"),
        .init(title: "十日终焉", author: "杀虫队队员", tag: "悬疑"),
        .init(title: "诡秘之主", author: "爱潜水的乌贼", tag: "奇幻"),
        .init(title: "道诡异仙", author: "狐尾的笔", tag: "玄幻"),
        .init(title: "夜的命名术", author: "会说话的肘子", tag: "都市"),
        .init(title: "大王饶命", author: "会说话的肘子", tag: "都市"),
        .init(title: "牧神记", author: "宅猪", tag: "玄幻"),
        .init(title: "完美世界", author: "辰东", tag: "玄幻"),
        .init(title: "凡人修仙传", author: "忘语", tag: "仙侠"),
        .init(title: "雪中悍刀行", author: "烽火戏诸侯", tag: "武侠")
    ]

    static let boards: [RankingBoard] = [
        .init(id: "peak", title: "巅峰榜单", searchKeyword: "热门", books: webBooks),
        .init(id: "publish", title: "出版榜", searchKeyword: "出版", books: classics),
        .init(id: "new", title: "新书热榜", searchKeyword: "新书", books: guesses),
        .init(id: "complete", title: "完本榜", searchKeyword: "完本", books: Array(webBooks.reversed())),
        .init(id: "science", title: "科幻榜", searchKeyword: "科幻", books: classics),
        .init(id: "mystery", title: "悬疑榜", searchKeyword: "悬疑", books: Array(guesses.reversed())),
        .init(id: "history", title: "历史榜", searchKeyword: "历史", books: Array(classics.reversed())),
        .init(id: "city", title: "都市榜", searchKeyword: "都市", books: webBooks),
        .init(id: "female", title: "女频榜", searchKeyword: "女频", books: guesses),
        .init(id: "reputation", title: "口碑榜", searchKeyword: "高分", books: classics + webBooks)
    ]
}

private struct BrowseSourcePicker: View {
    @Environment(\.dismiss) private var dismiss
    let sources: [BookSourceRecord]
    @Binding var selection: String
    @State private var query = ""

    private var filtered: [BookSourceRecord] {
        sources.filter {
            query.isEmpty || $0.bookSourceName.localizedCaseInsensitiveContains(query)
                || $0.bookSourceUrl.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Button {
                    selection = ""
                    dismiss()
                } label: {
                    sourceRow(name: "全部书源", detail: "跨所有已启用书源搜索", selected: selection.isEmpty)
                }
                ForEach(filtered) { source in
                    Button {
                        selection = source.bookSourceUrl
                        dismiss()
                    } label: {
                        sourceRow(name: source.bookSourceName, detail: source.bookSourceUrl,
                                  selected: selection == source.bookSourceUrl)
                    }
                }
            }
            .listStyle(.plain)
            .searchable(text: $query, prompt: "搜索书源")
            .navigationTitle("切换书源")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }

    private func sourceRow(name: String, detail: String, selected: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(selected ? .blue : .secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(name).foregroundStyle(.primary)
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
}

struct QuickSearchSheet: View {
    let keyword: String
    let sourceURLFilter: String?

    @Environment(\.dismiss) private var dismiss
    @Query private var allSources: [BookSourceRecord]
    @State private var viewModel: SearchViewModel?
    @State private var selected: SelectedBook?

    private struct SelectedBook: Identifiable {
        let result: TaggedSearchResult
        let source: BookSource
        var id: String { result.id }
    }

    private var enabledSources: [BookSourceRecord] {
        allSources.filter {
            $0.enabled && (sourceURLFilter == nil || $0.bookSourceUrl == sourceURLFilter)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if enabledSources.isEmpty {
                    ContentUnavailableView(
                        "没有可用书源",
                        systemImage: "tray",
                        description: Text("请切换到已启用的书源")
                    )
                } else if let viewModel {
                    resultList(viewModel)
                } else {
                    ProgressView("正在搜索「\(keyword)」…")
                }
            }
            .navigationTitle("「\(keyword)」")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .sheet(item: $selected) { item in
                BookDetailView(
                    source: item.source,
                    bookUrl: item.result.bookUrl,
                    name: item.result.name,
                    author: item.result.author,
                    intro: item.result.intro,
                    coverUrl: item.result.coverUrl
                )
            }
            .task {
                guard viewModel == nil else { return }
                let model = SearchViewModel(sources: enabledSources)
                model.keyword = keyword
                viewModel = model
                await model.search()
            }
        }
    }

    private func resultList(_ model: SearchViewModel) -> some View {
        List {
            if model.isSearching {
                ProgressView().frame(maxWidth: .infinity)
            }
            if model.omittedResultCount > 0 {
                Text("结果较多，已展示前 \(model.results.count) 条")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !model.errorMessages.isEmpty {
                Section("部分书源出错") {
                    ForEach(model.errorMessages, id: \.self) {
                        Text($0).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Section {
                ForEach(model.results) { result in
                    Button {
                        guard let record = enabledSources.first(where: { $0.bookSourceUrl == result.sourceUrl }),
                              let source = record.decodeSource() else { return }
                        CrashReporter.shared.breadcrumb(
                            level: "info",
                            tag: "browse-search",
                            message: "点击推荐搜索结果：\(result.name) · \(result.sourceName)"
                        )
                        selected = SelectedBook(result: result, source: source)
                    } label: {
                        HStack(spacing: 12) {
                            SmartCover(url: result.coverUrl, title: result.name)
                                .frame(width: 44, height: 60)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(result.name).font(.headline).foregroundStyle(.primary).lineLimit(1)
                                Text("\(result.author) · \(result.sourceName)")
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                if !result.lastChapter.isEmpty {
                                    Text(result.lastChapter)
                                        .font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("找到 \(model.results.count) 条结果")
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            if !model.isSearching && model.results.isEmpty {
                ContentUnavailableView.search
            }
        }
    }
}
