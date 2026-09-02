import SwiftUI
import SwiftData
import LegadoRuleEngine
import UIKit

/// 书源管理（对照 legado 原版功能）：分组筛选 + 搜索 + 批量删除 + 启用/停用 + 置顶/置底 +
/// 长按菜单(测试/编辑/登录/导出/删除) + 多种导入 + 导出全部 + 日志
struct BookSourceListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\BookSourceRecord.customOrder), SortDescriptor(\BookSourceRecord.bookSourceName)])
    private var sources: [BookSourceRecord]

    @State private var searchText = ""
    @State private var groupFilter: String?
    @State private var editing = false
    @State private var selected = Set<String>()
    @State private var confirmDelete = false
    @State private var showLog = false
    @State private var showImport = false
    @State private var showUrlImport = false
    @State private var testingSource: BookSourceRecord?
    @State private var editingSource: BookSourceRecord?
    @State private var loginSource: BookSourceRecord?
    @State private var exportDoc: SourceJSONDocument?
    @State private var showExporter = false
    @State private var exportName = "bookSource.json"

    private var groups: [String] {
        var seen = Set<String>()
        return sources.compactMap { $0.bookSourceGroup }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    private var filtered: [BookSourceRecord] {
        sources.filter { s in
            let matchText = searchText.isEmpty
                || s.bookSourceName.localizedCaseInsensitiveContains(searchText)
                || s.bookSourceUrl.localizedCaseInsensitiveContains(searchText)
            let matchGroup = groupFilter == nil || s.bookSourceGroup == groupFilter
            return matchText && matchGroup
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !groups.isEmpty {
                    groupChips
                }
                if filtered.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(filtered) { record in
                            row(record)
                        }
                        .onDelete(perform: deleteAtOffsets)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("书源管理")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "搜索书源名称 / 地址")
            .toolbar { toolbarContent }
            .safeAreaInset(edge: .bottom) {
                if editing { batchBar }
            }
            .sheet(isPresented: $showImport) { ImportSourceView() }
            .sheet(isPresented: $showUrlImport) { UrlImportView() }
            .sheet(isPresented: $showLog) { NavigationStack { LogView() } }
            .sheet(item: $testingSource) { SourceDebugView(record: $0) }
            .sheet(item: $editingSource) { SourceEditView(record: $0) }
            .sheet(item: $loginSource) { SourceLoginView(record: $0) }
            .fileExporter(isPresented: $showExporter, document: exportDoc, contentType: .json, defaultFilename: exportName) { _ in }
            .confirmationDialog("确定删除选中的 \(selected.count) 个书源？", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("删除 \(selected.count) 个", role: .destructive) { deleteSelected() }
                Button("取消", role: .cancel) {}
            }
        }
    }

    // MARK: - 分组筛选

    private var groupChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("全部", nil)
                ForEach(groups, id: \.self) { g in
                    chip(g, g)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private func chip(_ title: String, _ value: String?) -> some View {
        Button {
            groupFilter = value
        } label: {
            Text(title)
                .font(.footnote)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Capsule().fill(groupFilter == value ? Theme.accent : Color.white))
                .foregroundStyle(groupFilter == value ? .white : .primary.opacity(0.8))
                .overlay(Capsule().stroke(Theme.hairline, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 行

    @ViewBuilder
    private func row(_ record: BookSourceRecord) -> some View {
        HStack(spacing: 12) {
            if editing {
                Button { toggleSelect(record) } label: {
                    Image(systemName: selected.contains(record.bookSourceUrl) ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20))
                        .foregroundStyle(selected.contains(record.bookSourceUrl) ? Theme.accent : .secondary)
                }
                .buttonStyle(.plain)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(record.bookSourceName).font(.headline).foregroundStyle(.primary).lineLimit(1)
                    if let group = record.bookSourceGroup, !group.isEmpty {
                        Text(group)
                            .font(.caption2).foregroundStyle(Theme.accent)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Capsule().fill(Theme.accent.opacity(0.12)))
                    }
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
        .onTapGesture { if editing { toggleSelect(record) } }
        .contextMenu { contextMenu(for: record) }
    }

    @ViewBuilder
    private func contextMenu(for record: BookSourceRecord) -> some View {
        Button { testingSource = record } label: { Label("测试配置", systemImage: "play.circle") }
        Button { editingSource = record } label: { Label("编辑配置", systemImage: "square.and.pencil") }

        if let src = record.decodeSource(), let loginUrl = src.loginUrl, !loginUrl.isEmpty {
            Button { loginSource = record } label: { Label("登录", systemImage: "person.crop.circle") }
        }

        Button { top(record) } label: { Label("置顶", systemImage: "arrow.up.to.line") }
        Button { bottom(record) } label: { Label("置底", systemImage: "arrow.down.to.line") }

        Divider()
        Button { export(record) } label: { Label("导出配置文件", systemImage: "square.and.arrow.up") }
        Button(role: .destructive) {
            context.delete(record)
            try? context.save()
        } label: { Label("删除配置", systemImage: "trash") }
    }

    private var emptyState: some View {
        VStack {
            Spacer()
            VStack(spacing: 14) {
                Image(systemName: "tray")
                    .font(.system(size: 46, weight: .light)).foregroundStyle(.secondary)
                Text(searchText.isEmpty && groupFilter == nil ? "还没有书源" : "没有匹配的书源")
                    .font(.subheadline).foregroundStyle(.secondary)
                if searchText.isEmpty && groupFilter == nil {
                    Button { showImport = true } label: {
                        Label("导入书源 JSON", systemImage: "square.and.arrow.down")
                            .prominentGlassButton().tint(Theme.accent)
                    }
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 工具栏

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { showLog = true } label: {
                Image(systemName: "doc.text.magnifyingglass")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
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
                    Menu {
                        Button { showImport = true } label: { Label("粘贴 JSON 导入", systemImage: "doc.on.clipboard") }
                        Button { showUrlImport = true } label: { Label("从网络地址导入", systemImage: "link") }
                        Divider()
                        Button { exportAll() } label: { Label("导出全部书源", systemImage: "square.and.arrow.up") }
                    } label: {
                        Image(systemName: "plus")
                    }
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
        for i in indexSet { context.delete(filtered[i]) }
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

    private func top(_ r: BookSourceRecord) {
        r.customOrder = (sources.map(\.customOrder).min() ?? 0) - 1
        try? context.save()
    }

    private func bottom(_ r: BookSourceRecord) {
        r.customOrder = (sources.map(\.customOrder).max() ?? 0) + 1
        try? context.save()
    }

    private func export(_ record: BookSourceRecord) {
        exportName = "\(record.bookSourceName.isEmpty ? "bookSource" : record.bookSourceName).json"
        exportDoc = SourceJSONDocument(text: record.rawJSON)
        showExporter = true
    }

    private func exportAll() {
        let arr = sources.map { $0.rawJSON }.joined(separator: ",\n")
        exportDoc = SourceJSONDocument(text: "[\n\(arr)\n]")
        exportName = "bookSources.json"
        showExporter = true
    }
}
