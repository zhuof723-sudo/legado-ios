import SwiftUI
import SwiftData
import LegadoRuleEngine

public struct SearchView: View {
    @Query(sort: [SortDescriptor(\BookSourceRecord.bookSourceName)])
    private var allSources: [BookSourceRecord]
    @State private var viewModel: SearchViewModel?
    @State private var selectedResult: TaggedSearchResult?

    public init() {}

    private var enabledSources: [BookSourceRecord] { allSources.filter { $0.enabled } }

    /// 每个书源的请求头解析一次就缓存住，避免列表滚动时反复重新 decode JSON。
    /// 用普通class而不是@State直接存字典，是为了避免在body求值过程中给@State赋值
    /// (那样会触发"修改状态触发视图刷新"的问题，甚至死循环)——只mutate引用类型内部数据是安全的。
    @State private var headerCache = HeaderCacheBox()

    private func headers(for result: TaggedSearchResult) -> [String: String] {
        if let cached = headerCache.storage[result.sourceUrl] { return cached }
        let h = allSources.first(where: { $0.bookSourceUrl == result.sourceUrl })?
            .decodeSource()?.parsedHeaderMap() ?? [:]
        headerCache.storage[result.sourceUrl] = h
        return h
    }

    public var body: some View {
        NavigationStack {
            Group {
                if let vm = viewModel {
                    List {
                        if !vm.errorMessages.isEmpty {
                            Section("部分书源出错") {
                                ForEach(vm.errorMessages, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                        ForEach(vm.results) { result in
                            Button { selectedResult = result } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    CoverImageView(url: result.coverUrl, headers: headers(for: result))
                                        .frame(width: 52, height: 72)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(result.name).font(.headline)
                                        Text("\(result.author) · \(result.sourceName)")
                                            .font(.caption).foregroundStyle(.secondary)
                                        if !result.lastChapter.isEmpty {
                                            Text(result.lastChapter).font(.caption2).foregroundStyle(.tertiary)
                                        }
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }

                        if !vm.results.isEmpty, !vm.reachedEnd {
                            HStack {
                                Spacer()
                                if vm.isLoadingMore {
                                    ProgressView()
                                } else {
                                    Button("加载更多") { Task { await vm.loadMore() } }
                                        .font(.footnote)
                                }
                                Spacer()
                            }
                            .onAppear {
                                // 滑到底自动加载下一页，不用非得点按钮
                                Task { await vm.loadMore() }
                            }
                        }
                    }
                    .overlay {
                        if vm.isSearching { ProgressView("搜索中…") }
                        else if vm.results.isEmpty, !vm.keyword.isEmpty {
                            ContentUnavailableView.search
                        }
                    }
                } else {
                    ContentUnavailableView("没有启用的书源", systemImage: "magnifyingglass")
                }
            }
            .navigationTitle("搜索")
            .searchable(text: Binding(
                get: { viewModel?.keyword ?? "" },
                set: { viewModel?.keyword = $0 }
            ))
            .onSubmit(of: .search) {
                Task { await viewModel?.search() }
            }
            .onAppear {
                if viewModel == nil, !enabledSources.isEmpty {
                    viewModel = SearchViewModel(sources: enabledSources)
                }
            }
            .sheet(item: $selectedResult) { result in
                if let record = allSources.first(where: { $0.bookSourceUrl == result.sourceUrl }),
                   let source = record.decodeSource() {
                    BookDetailView(source: source, bookUrl: result.bookUrl, name: result.name, author: result.author, intro: result.intro, coverUrl: result.coverUrl)
                }
            }
        }
    }
}
