import SwiftUI
import SwiftData
import LegadoRuleEngine

/// 全局搜索页：跨书源并发搜索（从悬浮玻璃搜索按钮进入）
struct SearchView: View {
    let sourceURLFilter: String?

    @Environment(\.dismiss) private var dismiss
    @Query(sort: [SortDescriptor(\BookSourceRecord.bookSourceName)])
    private var allSources: [BookSourceRecord]

    @State private var viewModel: SearchViewModel?
    @State private var selectedResult: TaggedSearchResult?
    @State private var headerCache = HeaderCacheBox()

    init(sourceURLFilter: String? = nil) {
        self.sourceURLFilter = sourceURLFilter
    }

    private var enabledSources: [BookSourceRecord] {
        allSources.filter {
            $0.enabled && (sourceURLFilter == nil || $0.bookSourceUrl == sourceURLFilter)
        }
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
            Group {
                if let vm = viewModel {
                    resultList(vm)
                } else {
                    noSourcesView
                }
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("搜索")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .searchable(
                text: Binding(
                    get: { viewModel?.keyword ?? "" },
                    set: { viewModel?.keyword = $0 }
                ),
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "搜索书籍 / 作者"
            )
            .onSubmit(of: .search) {
                Task { await viewModel?.search() }
            }
            .onAppear {
                if viewModel == nil, !enabledSources.isEmpty {
                    viewModel = SearchViewModel(sources: enabledSources)
                }
            }
            .sheet(item: $selectedResult) { result in
                if let record = enabledSources.first(where: { $0.bookSourceUrl == result.sourceUrl }),
                   let source = record.decodeSource() {
                    BookDetailView(source: source, bookUrl: result.bookUrl, name: result.name,
                                   author: result.author, intro: result.intro, coverUrl: result.coverUrl)
                }
            }
        }
    }

    private var noSourcesView: some View {
        ContentUnavailableView("没有启用的书源", systemImage: "magnifyingglass",
                               description: Text("先到 设置 → 书源管理 导入并启用书源"))
    }

    @ViewBuilder
    private func resultList(_ vm: SearchViewModel) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if vm.isSearching {
                    HStack { Spacer(); ProgressView("搜索中…"); Spacer() }.padding(.top, 30)
                }
                if !vm.errorMessages.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("部分书源出错").font(.caption.bold()).foregroundStyle(.secondary)
                        ForEach(vm.errorMessages, id: \.self) {
                            Text($0).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.7)))
                }
                if vm.omittedResultCount > 0 {
                    Label(
                        "结果过多，已安全展示 \(vm.results.count) 条，省略 \(vm.omittedResultCount) 条",
                        systemImage: "rectangle.stack.badge.minus"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
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
                if !vm.isSearching, vm.results.isEmpty, !vm.keyword.isEmpty {
                    ContentUnavailableView.search
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 30)
        }
    }

    private func resultRow(_ result: TaggedSearchResult) -> some View {
        Button {
            CrashReporter.shared.breadcrumb(
                level: "info",
                tag: "search-ui",
                message: "点击书籍：\(result.name) · \(result.sourceName) · \(String(result.bookUrl.prefix(500)))"
            )
            selectedResult = result
        } label: {
            HStack(alignment: .top, spacing: 12) {
                SmartCover(url: result.coverUrl, title: result.name, headers: headers(for: result))
                    .frame(width: 52, height: 72)
                VStack(alignment: .leading, spacing: 5) {
                    Text(result.name).font(.subheadline.bold()).foregroundStyle(.primary).lineLimit(1)
                    Text("\(result.author) · \(result.sourceName)")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    if !result.intro.isEmpty {
                        Text(result.intro).font(.caption2).foregroundStyle(.tertiary).lineLimit(2)
                    }
                    if !result.lastChapter.isEmpty {
                        Text(result.lastChapter).font(.caption2).foregroundStyle(Theme.accent.opacity(0.8)).lineLimit(1)
                    }
                }
                Spacer()
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.white))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }
}
