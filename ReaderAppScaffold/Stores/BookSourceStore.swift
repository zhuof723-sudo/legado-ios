import Foundation
import SwiftData
import LegadoRuleEngine

@Observable
public final class BookSourceStore {
    private let context: ModelContext
    public private(set) var errorMessage: String?
    public private(set) var skippedCount: Int = 0

    public init(context: ModelContext) {
        self.context = context
    }

    /// 导入书源JSON（单个对象或数组都行），已存在同 bookSourceUrl 的会被覆盖更新。
    /// 返回实际导入（新增或覆盖）的数量；缺少 bookSourceUrl 的条目标记为 skippedCount。
    @discardableResult
    public func importSources(from jsonString: String) -> Int {
        errorMessage = nil
        skippedCount = 0
        do {
            let sources = try BookSourceImporter.parse(jsonString)
            guard !sources.isEmpty else {
                errorMessage = "没有解析出书源"
                return 0
            }
            var imported = 0
            for source in sources {
                let url = source.bookSourceUrl
                guard !url.isEmpty else {
                    skippedCount += 1
                    continue
                }

                let descriptor = FetchDescriptor<BookSourceRecord>(
                    predicate: #Predicate { $0.bookSourceUrl == url }
                )
                if let existing = try context.fetch(descriptor).first {
                    existing.bookSourceName = source.bookSourceName
                    existing.bookSourceGroup = source.bookSourceGroup
                    existing.rawJSON = Self.extractOriginalJSON(for: source, from: jsonString) ?? existing.rawJSON
                    existing.enabled = source.enabled
                } else {
                    let record = BookSourceRecord(
                        source: source,
                        rawJSON: Self.extractOriginalJSON(for: source, from: jsonString) ?? jsonString
                    )
                    context.insert(record)
                }
                imported += 1
            }
            try context.save()
            if imported == 0 {
                errorMessage = "没有有效的书源（缺少 bookSourceUrl 字段）"
            }
            return imported
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

    /// 从导入的原始 JSON 里，取出「对应某个书源」的原始对象文本（保留原始字段与格式），
    /// 避免用 Swift 重编码后丢掉模型外的字段。单个对象原样返回，数组则找到对应元素再序列化。
    private static func extractOriginalJSON(for source: BookSource, from jsonString: String) -> String? {
        guard let data = jsonString.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) else { return nil }

        if let array = obj as? [[String: Any]] {
            if let elem = array.first(where: { ($0["bookSourceUrl"] as? String) == source.bookSourceUrl }),
               let d = try? JSONSerialization.data(withJSONObject: elem, options: [.prettyPrinted]),
               let s = String(data: d, encoding: .utf8) {
                return s
            }
        } else if let dict = obj as? [String: Any],
                  (dict["bookSourceUrl"] as? String) == source.bookSourceUrl {
            return jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }
}
