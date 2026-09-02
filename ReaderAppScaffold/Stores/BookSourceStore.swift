import Foundation
import SwiftData
import LegadoRuleEngine

@Observable
public final class BookSourceStore {
    private let context: ModelContext
    public private(set) var errorMessage: String?

    public init(context: ModelContext) {
        self.context = context
    }

    /// 导入书源JSON（单个对象或数组都行），已存在同 bookSourceUrl 的会被覆盖更新
    @discardableResult
    public func importSources(from jsonString: String) -> Int {
        errorMessage = nil
        do {
            let sources = try BookSourceImporter.parse(jsonString)
            guard !sources.isEmpty else {
                errorMessage = "没有解析出书源"
                return 0
            }
            for source in sources {
                let url = source.bookSourceUrl
                guard !url.isEmpty else { continue }

                let descriptor = FetchDescriptor<BookSourceRecord>(
                    predicate: #Predicate { $0.bookSourceUrl == url }
                )
                if let existing = try context.fetch(descriptor).first {
                    existing.bookSourceName = source.bookSourceName
                    existing.bookSourceGroup = source.bookSourceGroup
                    existing.rawJSON = Self.encodeSingle(source) ?? existing.rawJSON
                    existing.enabled = source.enabled
                } else {
                    let record = BookSourceRecord(
                        source: source,
                        rawJSON: Self.encodeSingle(source) ?? jsonString
                    )
                    context.insert(record)
                }
            }
            try context.save()
            return sources.count
        } catch {
            errorMessage = "导入失败: \(error.localizedDescription)"
            return 0
        }
    }

    public func setEnabled(_ record: BookSourceRecord, _ enabled: Bool) {
        record.enabled = enabled
        try? context.save()
    }

    public func delete(_ record: BookSourceRecord) {
        context.delete(record)
        try? context.save()
    }

    public func fetchAll() -> [BookSourceRecord] {
        let descriptor = FetchDescriptor<BookSourceRecord>(
            sortBy: [SortDescriptor(\.customOrder), SortDescriptor(\.bookSourceName)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    public func fetchEnabled() -> [BookSourceRecord] {
        fetchAll().filter { $0.enabled }
    }

    private static func encodeSingle(_ source: BookSource) -> String? {
        guard let data = try? JSONEncoder().encode(source) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
