import SwiftUI
import SwiftData
import LegadoRuleEngine

/// 浏览页（书城风格）：搜索入口 + 热门推荐横幅 + 分类 + 为你推荐。
/// 本应用是书源驱动，没有线上书城；推荐位是本地精选经典，点击后
/// 用你启用的书源跨源搜索真实资源。
struct BrowseView: View {
    @Query private var allSources: [BookSourceRecord]

    @State private var showSearch = false
    @State private var quickKeyword: String?
    @State private var selectedCategory = "为你推荐"

    private var enabledCount: Int { allSources.filter(\.enabled).count }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    searchEntry
                    banner
                    categoryChips
                    recommendList
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 90)
            }
            .background(Theme.bg.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .fullScreenCover(isPresented: $showSearch) { SearchView() }
            .sheet(item: Binding(
                get: { quickKeyword.map { QuickSearchRequest(keyword: $0) } },
                set: { quickKeyword = $0?.keyword }
            )) { req in
                QuickSearchSheet(keyword: req.keyword)
            }
        }
    }

    // MARK: - 搜索入口

    private var searchEntry: some View {
        Button { showSearch = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                Text("搜索书籍 / 作者")
                    .font(.subheadline).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Capsule().fill(Color.white))
            .overlay(Capsule().stroke(Theme.hairline, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .padding(.top, 6)
    }

    // MARK: - 横幅

    private var banner: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [Theme.accent.opacity(0.85), Theme.accentDeep.opacity(0.9)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .overlay(
                Image(systemName: "books.vertical.fill")
                    .font(.system(size: 90))
                    .foregroundStyle(.white.opacity(0.16))
                    .offset(x: 110, y: -12)
            )
            VStack(alignment: .leading, spacing: 6) {
                Text("热门推荐").font(.title3.bold()).foregroundStyle(.white)
                Text(enabledCount > 0 ? "已启用 \(enabledCount) 个书源，点一本开始找书" : "先去设置里导入并启用书源")
                    .font(.caption).foregroundStyle(.white.opacity(0.9))
                Button {
                    quickKeyword = RecommendBook.defaultFirst
                } label: {
                    Text("去看看")
                        .font(.footnote.bold())
                        .padding(.horizontal, 14).padding(.vertical, 6)
                        .background(Capsule().fill(.white))
                        .foregroundStyle(Theme.accentDeep)
                }
                .padding(.top, 4)
            }
            .padding(16)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .frame(height: 150)
        .frame(maxWidth: .infinity)
    }

    // MARK: - 分类

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 18) {
                ForEach(RecommendBook.categories, id: \.self) { cat in
                    Button {
                        selectedCategory = cat
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: RecommendBook.icon(for: cat))
                                .font(.system(size: 20, weight: .medium))
                                .foregroundStyle(selectedCategory == cat ? Theme.accent : .primary.opacity(0.7))
                                .frame(width: 46, height: 46)
                                .background(
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(selectedCategory == cat ? Theme.accent.opacity(0.12) : Color.white)
                                )
                            Text(cat).font(.caption2)
                                .foregroundStyle(selectedCategory == cat ? Theme.accent : .secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - 推荐列表

    private var recommendList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(selectedCategory == "为你推荐" ? "为你推荐" : selectedCategory)
                    .font(.headline)
                Spacer()
                Text("点击用书源搜索").font(.caption2).foregroundStyle(.secondary)
            }
            ForEach(RecommendBook.items(in: selectedCategory)) { book in
                Button {
                    quickKeyword = book.title
                } label: {
                    HStack(spacing: 12) {
                        PlaceholderCover(title: book.title)
                            .frame(width: 46, height: 62)
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(book.title).font(.subheadline.bold()).foregroundStyle(.primary).lineLimit(1)
                            Text(book.author).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(book.tag).font(.caption2).foregroundStyle(Theme.accent)
                        Image(systemName: "chevron.right")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.white))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline, lineWidth: 0.5))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct QuickSearchRequest: Identifiable {
    let keyword: String
    var id: String { keyword }
}

// MARK: - 精选数据

struct RecommendBook: Identifiable {
    let title: String
    let author: String
    let category: String
    let tag: String

    var id: String { title }

    static let categories = ["为你推荐", "新书", "完本", "排行榜", "会员"]
    static let defaultFirst = "三体"

    static func icon(for cat: String) -> String {
        switch cat {
        case "为你推荐": return "sparkles"
        case "新书": return "sparkle"
        case "完本": return "checkmark.seal"
        case "排行榜": return "chart.bar"
        case "会员": return "crown"
        default: return "square.grid.2x2"
        }
    }

    static func items(in category: String) -> [RecommendBook] {
        let all: [RecommendBook] = [
            .init(title: "三体", author: "刘慈欣", category: "排行榜", tag: "科幻巨著"),
            .init(title: "活着", author: "余华", category: "排行榜", tag: "人生必读"),
            .init(title: "百年孤独", author: "加西亚·马尔克斯", category: "会员", tag: "魔幻现实"),
            .init(title: "明朝那些事儿", author: "当年明月", category: "完本", tag: "超人气历史"),
            .init(title: "平凡的世界", author: "路遥", category: "完本", tag: "茅盾文学奖"),
            .init(title: "人类简史", author: "尤瓦尔·赫拉利", category: "会员", tag: "现象级畅销"),
            .init(title: "白鹿原", author: "陈忠实", category: "完本", tag: "民族秘史"),
            .init(title: "球状闪电", author: "刘慈欣", category: "新书", tag: "硬核科幻"),
            .init(title: "长安的荔枝", author: "马伯庸", category: "新书", tag: "口碑新作"),
            .init(title: "克拉拉与太阳", author: "石黑一雄", category: "新书", tag: "诺奖作家"),
            .init(title: "围城", author: "钱锺书", category: "为你推荐", tag: "经典讽刺"),
            .init(title: "许三观卖血记", author: "余华", category: "为你推荐", tag: "温情之作"),
        ]
        if category == "为你推荐" { return all }
        return all.filter { $0.category == category }
    }
}

// MARK: - 快速跨源搜索（点推荐后弹出的真实搜索）

struct QuickSearchSheet: View {
    let keyword: String
    @Environment(\.dismiss) private var dismiss
    @Query private var allSources: [BookSourceRecord]
    @State private var vm: SearchViewModel?
    @State private var selected: SelectedBook?

    struct SelectedBook: Identifiable {
        let result: TaggedSearchResult
        let source: BookSource
        var id: String { result.id }
    }

    private var enabledSources: [BookSourceRecord] { allSources.filter(\.enabled) }

    var body: some View {
        NavigationStack {
            Group {
                if enabledSources.isEmpty {
                    ContentUnavailableView("还没有启用的书源", systemImage: "tray",
                                           description: Text("先到 设置 → 书源管理 导入并启用书源"))
                } else if let vm {
                    resultList(vm)
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
            .sheet(item: $selected) { sel in
                BookDetailView(source: sel.source, bookUrl: sel.result.bookUrl,
                               name: sel.result.name, author: sel.result.author,
                               intro: sel.result.intro, coverUrl: sel.result.coverUrl)
            }
            .task {
                guard vm == nil else { return }
                let m = SearchViewModel(sources: enabledSources)
                m.keyword = keyword
                vm = m
                await m.search()
            }
        }
    }

    @ViewBuilder
    private func resultList(_ vm: SearchViewModel) -> some View {
        List {
            if vm.isSearching { ProgressView().frame(maxWidth: .infinity) }
            if !vm.errorMessages.isEmpty {
                Section("部分书源出错") {
                    ForEach(vm.errorMessages, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                }
            }
            Section {
                ForEach(vm.results) { result in
                    Button {
                        if let record = enabledSources.first(where: { $0.bookSourceUrl == result.sourceUrl }),
                           let source = record.decodeSource() {
                            selected = SelectedBook(result: result, source: source)
                        }
                    } label: {
                        HStack(spacing: 12) {
                            SmartCover(url: result.coverUrl, title: result.name)
                                .frame(width: 42, height: 58)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(result.name).font(.subheadline.bold()).foregroundStyle(.primary).lineLimit(1)
                                Text("\(result.author) · \(result.sourceName)")
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                if !result.lastChapter.isEmpty {
                                    Text(result.lastChapter).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                                }
                            }
                            Spacer()
                        }
                    }
                }
            } header: {
                Text("找到 \(vm.results.count) 条结果")
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            if !vm.isSearching && vm.results.isEmpty {
                ContentUnavailableView.search
            }
        }
    }
}
