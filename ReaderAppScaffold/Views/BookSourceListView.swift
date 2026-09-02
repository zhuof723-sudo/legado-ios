import SwiftUI
import SwiftData

/// 书源管理：列表 + 搜索 + 批量删除 + 全部启用/停用（修复导入不显示 & 新增批量删除）
struct BookSourceListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\BookSourceRecord.customOrder), SortDescriptor(\BookSourceRecord.bookSourceName)])
    private var sources: [BookSourceRecord]

    @State private var showImport = false
    @State private var editing = false
    @State private var selected = Set<String>()
    @State private var searchText = ""
    @State private var confirmDelete = false

    private var filtered: [BookSourceRecord] {
        guard !searchText.isEmpty else { return sources }
        return sources.filter {
            $0.bookSourceName.localizedCaseInsensitiveContains(searchText)
                || $0.bookSourceUrl.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if filtered.isEmpty {
                    emptyState
                } else {
                    ForEach(filtered) { record in
                        row(record)
                    }
                    .onDelete(perform: deleteAtOffsets)
                }
            }
            .listStyle(.plain)
            .navigationTitle("书源管理")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "搜索书源名称 / 地址")
            .toolbar {
                toolbarContent
            }
            .safeAreaInset(edge: .bottom) {
                if editing {
                    batchBar
                }
            }
            .sheet(isPresented: $showImport) {
                ImportSourceView()
            }
            .confirmationDialog("确定删除选中的 \(selected.count) 个书源？", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("删除 \(selected.count) 个", role: .destructive) { deleteSelected() }
                Button("取消", role: .cancel) {}
            }
        }
    }

    // MARK: - 行

    @ViewBuilder
    private func row(_ record: BookSourceRecord) -> some View {
        HStack(spacing: 12) {
            if editing {
                Button {
                    toggleSelect(record)
                } label: {
                    Image(systemName: selected.contains(record.bookSourceUrl) ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20))
                        .foregroundStyle(selected.contains(record.bookSourceUrl) ? Theme.accent : .secondary)
                }
                .buttonStyle(.plain)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(record.bookSourceName).font(.headline).foregroundStyle(.primary)
                if let group = record.bookSourceGroup, !group.isEmpty {
                    Text(group).font(.caption).foregroundStyle(.secondary)
                }
                Text(record.bookSourceUrl)
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if !editing {
                Toggle("", isOn: Binding(
                    get: { record.enabled },
                    set: { record.enabled = $0; try? context.save() }
                ))
                .labelsHidden()
                .tint(Theme.accent)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if editing { toggleSelect(record) }
        }
    }

    private var emptyState: some View {
        Section {
            VStack(spacing: 14) {
                Image(systemName: "tray")
                    .font(.system(size: 46, weight: .light))
                    .foregroundStyle(.secondary)
                Text(searchText.isEmpty ? "还没有书源" : "没有匹配的书源")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if searchText.isEmpty {
                    Button {
                        showImport = true
                    } label: {
                        Label("导入书源 JSON", systemImage: "square.and.arrow.down")
                            .prominentGlassButton()
                            .tint(Theme.accent)
                    }
                    Text("支持粘贴书源 JSON，或从文件导入")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
            .listRowBackground(Color.clear)
        }
    }

    // MARK: - 工具栏

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            if editing {
                Button("完成") {
                    editing = false
                    selected.removeAll()
                }
            } else {
                HStack(spacing: 14) {
                    if !sources.isEmpty {
                        Button("编辑") { editing = true }
                    }
                    Button { showImport = true } label: { Image(systemName: "plus") }
                }
            }
        }
        ToolbarItem(placement: .bottomBar) {
            if !editing, !sources.isEmpty {
                Text("共 \(sources.count) 个 · 已启用 \(sources.filter(\.enabled).count) 个")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - 批量操作条

    private var batchBar: some View {
        HStack(spacing: 12) {
            Button(selected.count == filtered.count ? "取消全选" : "全选") {
                if selected.count == filtered.count {
                    selected.removeAll()
                } else {
                    selected = Set(filtered.map(\.bookSourceUrl))
                }
            }
            Spacer()
            Menu {
                Button { setAllEnabled(true) } label: { Label("全部启用", systemImage: "checkmark.circle") }
                Button { setAllEnabled(false) } label: { Label("全部停用", systemImage: "circle.slash") }
            } label: {
                Label("批量设置", systemImage: "slider.horizontal.3")
            }
            Button(role: .destructive) {
                if !selected.isEmpty { confirmDelete = true }
            } label: {
                Label("删除\(selected.isEmpty ? "" : "(\(selected.count))")", systemImage: "trash")
            }
            .disabled(selected.isEmpty)
            .tint(.red)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial)
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 0.5) }
    }

    // MARK: - 操作

    private func toggleSelect(_ record: BookSourceRecord) {
        if selected.contains(record.bookSourceUrl) {
            selected.remove(record.bookSourceUrl)
        } else {
            selected.insert(record.bookSourceUrl)
        }
    }

    private func deleteAtOffsets(_ indexSet: IndexSet) {
        for i in indexSet { context.delete(sources[i]) }
        try? context.save()
    }

    private func deleteSelected() {
        let targets = sources.filter { selected.contains($0.bookSourceUrl) }
        for r in targets { context.delete(r) }
        try? context.save()
        selected.removeAll()
        editing = false
    }

    private func setAllEnabled(_ enabled: Bool) {
        for r in sources { r.enabled = enabled }
        try? context.save()
    }
}
