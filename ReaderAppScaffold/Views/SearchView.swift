import SwiftUI
import SwiftData
import LegadoRuleEngine

/// 全局搜索页（对照设计稿）：大标题 + 搜索栏 + 热门搜索 + 搜索历史 + 跨书源结果。
struct SearchView: View {
    let sourceURLFilter: String?
    let embeddedInTab: Bool

    @Environment(\.dismiss) private var dismiss
    @AppStorage("search.history") private var historyRaw: String = ""
    @Query(sort: [SortDescriptor(\BookSourceRecord.bookSourceName)])
    private var allSources: [BookSourceRecord]

    @State private var viewModel: SearchViewModel?
    @State private var keyword = ""
    @State private var selectedResult: TaggedSearchResult?
    @State private var headerCache = HeaderCacheBox()

    private var hotKeywords: [String] { ["斗破苍穹", "凡人修仙传", "诛仙", "万古神帝", "遮天", "完美世界"] }

    private var history: [String] {
        historyRaw.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }

    private var enabledSources: [BookSourceRecord] {
        allSources.filter {
            $0.enabled && (sourceURLFilter == nil || $0.bookSourceUrl == sourceURLFilter)
        }
    }

    init(sourceURLFilter: String? = nil, embeddedInTab: Bool = false) {
        self.sourceURLFilter = sourceURLFilter
        self.embeddedInTab = embeddedInTab
    }

    private func headers(for result: TaggedSearchResult) -> [String: String] {
        if let cached = headerCache.storage[result.sourceUrl] { return cached }
        let h = allSources.first(where: { $0.bookSourceUrl == result.sourceUrl })?
            .decodeSource()?.parsedHeaderMap() ?? [:]
        headerCache.storage[result.sourceUrl] = h
        return h
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if !embeddedInTab {
                        HStack {
                            Text("搜索").font(.system(size: 32, weight: .bold))
                            Spacer()
                            Button {
                                if let vm = viewModel { vm.keyword = ""; keyword = "" }
                            } label: {
                                Image(systemName: "qrcode.viewfinder")
                                    .font(.system(size: 19))
                                    .foregroundStyle(.primary)
                            }
                        }
                        .padding(.top, 4)
                    }
                    searchBar
                    if let vm = viewModel, vm.isSearching || !vm.results.isEmpty {
                        resultSection(vm)
                    } else {
                        hotSection
                        historySection
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 90)
            }
            .background(Theme.bg.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .toolbar {
                if !embeddedInTab {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("关闭") { dismiss() }
                    }
                }
            }
            .sheet(item: $selectedResult) { result in
                if let record = enabledSources.first(where: { $0.bookSourceUrl == result.sourceUrl }),
                   let source = record.decodeSource() {
                    BookDetailView(source: source, bookUrl: result.bookUrl, name: result.name,
                                   author: result.author, intro: result.intro, coverUrl: result.coverUrl)
                }
            }
            .onAppear {
                if viewModel == nil, !enabledSources.isEmpty {
                    viewModel = SearchViewModel(sources: enabledSources)
                }
            }
        }
    }

    // MARK: - 搜索栏

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.textSecondary)
            TextField("搜索书名、作者、网站关键词", text: $keyword)
                .font(.subheadline)
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                .onSubmit { startSearch() }
            if !keyword.isEmpty {
                Button { keyword = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            Capsule()
                .fill(Theme.secondaryBg)
                .overlay(Capsule().stroke(Theme.hairline, lineWidth: 0.5))
        )
    }

    // MARK: - 热门搜索

    private var hotSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("热门搜索").font(.title3.bold())
            FlowTags(tags: hotKeywords) { tag in
                keyword = tag
                startSearch()
            }
        }
    }

    // MARK: - 搜索历史

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("搜索历史").font(.title3.bold())
                Spacer()
                if !history.isEmpty {
                    Button("清空") { historyRaw = "" }
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            if history.isEmpty {
                Text("暂无搜索历史").font(.footnote).foregroundStyle(Theme.textSecondary)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(history.enumerated()), id: \.offset) { _, item in
                        Button {
                            keyword = item
                            startSearch()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "clock")
                                    .font(.caption)
                                    .foregroundStyle(Theme.textSecondary)
                                Text(item).font(.subheadline).foregroundStyle(.primary)
                                Spacer()
                            }
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                        if item != history.last {
                            Rectangle().fill(Theme.hairline).frame(height: 0.5)
                        }
                    }
                }
            }
        }
    }

    // MARK: - 搜索结果

    @ViewBuilder
    private func resultSection(_ vm: SearchViewModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("搜索结果").font(.title3.bold())
                Spacer()
                Text("\(vm.results.count) 条")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
            }
            if vm.isSearching {
                HStack { Spacer(); ProgressView(); Spacer() }.padding(.vertical, 16)
            }
            if !vm.errorMessages.isEmpty {
                Text("部分书源出错，已跳过")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
            }
            ForEach(vm.results) { result in
                resultRow(result)
            }
            if !vm.results.isEmpty, !vm.reachedEnd {
                HStack {
                    Spacer()
                    if vm.isLoadingMore {
                        ProgressView()
                    } else {
                        Button("加载更多") { Task { await vm.loadMore() } }
                            .font(.footnote).foregroundStyle(Theme.accent)
                    }
                    Spacer()
                }
                .padding(.vertical, 8)
                .onAppear { Task { await vm.loadMore() } }
            }
            if !vm.isSearching, vm.results.isEmpty, !keyword.isEmpty {
                Text("没有找到相关书籍")
                    .font(.footnote).foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 24)
            }
        }
    }

    private func resultRow(_ result: TaggedSearchResult) -> some View {
        Button {
            CrashReporter.shared.breadcrumb(
                level: "info",
                tag: "search-ui",
                message: "点击书籍：\(result.name) · \(result.sourceName) · \(String(result.bookUrl.prefix(500)))"
            )
            pushHistory(result.name)
            selectedResult = result
        } label: {
            HStack(alignment: .top, spacing: 12) {
                SmartCover(url: result.coverUrl, title: result.name, headers: headers(for: result))
                    .frame(width: 52, height: 72)
                VStack(alignment: .leading, spacing: 5) {
                    Text(result.name).font(.subheadline.bold()).foregroundStyle(.primary).lineLimit(1)
                    Text("\(result.author) · \(result.sourceName)")
                        .font(.caption).foregroundStyle(Theme.textSecondary).lineLimit(1)
                    if !result.intro.isEmpty {
                        Text(result.intro).font(.caption2).foregroundStyle(Theme.textSecondary).lineLimit(2)
                    }
                }
                Spacer()
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

    // MARK: - 行为

    private func startSearch() {
        let key = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        pushHistory(key)
        guard let vm = viewModel else { return }
        vm.keyword = key
        Task { await vm.search() }
    }

    private func pushHistory(_ key: String) {
        var items = history.filter { $0 != key }
        items.insert(key, at: 0)
        if items.count > 10 { items = Array(items.prefix(10)) }
        historyRaw = items.joined(separator: "\n")
    }
}

// MARK: - 热门标签流式布局

private struct FlowTags: View {
    let tags: [String]
    let onTap: (String) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 10)], alignment: .leading, spacing: 10) {
            ForEach(tags, id: \.self) { tag in
                Button {
                    onTap(tag)
                } label: {
                    Text(tag)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .frame(maxWidth: .infinity)
                        .background(
                            Capsule()
                                .fill(Theme.secondaryBg)
                                .overlay(Capsule().stroke(Theme.hairline, lineWidth: 0.5))
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}
