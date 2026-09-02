import SwiftUI

/// 运行日志查看器：展示引擎的请求/解析过程，帮助排查"搜得到但打不开"
struct LogView: View {
    @State private var filter: LogLevel? = nil

    private func color(for level: LogLevel) -> Color {
        switch level {
        case .info: return .secondary
        case .warn: return .orange
        case .error: return .red
        }
    }

    var body: some View {
        let all = LogStore.shared.entries
        let entries = filter.map { f in all.filter { $0.level == f } } ?? all
        List(entries) { e in
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text("\(e.level.symbol) \(e.tag)")
                        .font(.caption.bold())
                        .foregroundStyle(color(for: e.level))
                    Spacer()
                    Text(e.time, format: .dateTime.hour().minute().second())
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                Text(e.message)
                    .font(.caption)
                    .textSelection(.enabled)
                    .foregroundStyle(.primary.opacity(0.85))
            }
            .padding(.vertical, 2)
        }
        .listStyle(.plain)
        .navigationTitle("运行日志")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("全部") { filter = nil }
                    ForEach(LogLevel.allCases, id: \.self) { l in
                        Button(l.rawValue) { filter = l }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
            }
            ToolbarItem(placement: .bottomBar) {
                HStack {
                    Text("共 \(LogStore.shared.entries.count) 条")
                        .font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    Button("清空") { LogStore.shared.clear() }
                        .font(.caption)
                }
            }
        }
        .overlay {
            if entries.isEmpty {
                ContentUnavailableView("暂无日志", systemImage: "doc.text.magnifyingglass",
                                       description: Text("执行一次搜索/打开书籍后这里会记录请求与解析过程"))
            }
        }
    }
}
