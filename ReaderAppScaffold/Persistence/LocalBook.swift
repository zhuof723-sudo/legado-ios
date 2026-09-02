import Foundation
import SwiftData

/// 本地导入的 TXT 书籍：正文按章节拆分后以 JSON 存进 chaptersData
@Model
final class LocalBook {
    @Attribute(.unique) var id: String
    var name: String
    var author: String
    var chaptersData: String
    var createdAt: Date

    init(name: String, author: String, chaptersData: String) {
        self.id = UUID().uuidString
        self.name = name
        self.author = author
        self.chaptersData = chaptersData
        self.createdAt = Date()
    }
}
