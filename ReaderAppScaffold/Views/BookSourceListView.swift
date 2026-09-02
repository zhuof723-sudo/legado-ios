import SwiftUI
import SwiftData

public struct BookSourceListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\BookSourceRecord.customOrder), SortDescriptor(\BookSourceRecord.bookSourceName)])
    private var sources: [BookSourceRecord]
    @State private var showImport = false

    public init() {}

    public var body: some View {
        NavigationStack {
            List {
                ForEach(sources) { record in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(record.bookSourceName).font(.headline)
                            if let group = record.bookSourceGroup, !group.isEmpty {
                                Text(group).font(.caption).foregroundStyle(.secondary)
                            }
                            Text(record.bookSourceUrl)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { record.enabled },
                            set: { record.enabled = $0; try? context.save() }
                        ))
                        .labelsHidden()
                    }
                }
                .onDelete { indexSet in
                    for i in indexSet { context.delete(sources[i]) }
                    try? context.save()
                }
            }
            .navigationTitle("书源管理")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showImport = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showImport) {
                ImportSourceView()
            }
            .overlay {
                if sources.isEmpty {
                    ContentUnavailableView(
                        "还没有书源", systemImage: "tray",
                        description: Text("点右上角 + 导入一个书源JSON")
                    )
                }
            }
        }
    }
}
