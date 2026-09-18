import SwiftUI
import UIKit

// MARK: - 阅读主题

struct ReaderPageTheme: Identifiable, Equatable {
    let id: String
    let name: String
    let background: Color
    let text: Color

    static let all: [ReaderPageTheme] = [
        ReaderPageTheme(id: "paper", name: "纸白", background: Color(red: 0.99, green: 0.99, blue: 0.98), text: Color(red: 0.13, green: 0.13, blue: 0.14)),
        ReaderPageTheme(id: "beige", name: "米黄", background: Color(red: 0.96, green: 0.93, blue: 0.86), text: Color(red: 0.20, green: 0.17, blue: 0.12)),
        ReaderPageTheme(id: "green", name: "护眼", background: Color(red: 0.89, green: 0.94, blue: 0.87), text: Color(red: 0.16, green: 0.22, blue: 0.16)),
        ReaderPageTheme(id: "gray", name: "浅灰", background: Color(red: 0.92, green: 0.92, blue: 0.92), text: Color(red: 0.18, green: 0.18, blue: 0.18)),
        ReaderPageTheme(id: "night", name: "夜间", background: Color(red: 0.10, green: 0.10, blue: 0.11), text: Color(red: 0.85, green: 0.85, blue: 0.87)),
        ReaderPageTheme(id: "dark", name: "暗黑", background: Color(red: 0.05, green: 0.05, blue: 0.06), text: Color(red: 0.70, green: 0.70, blue: 0.73))
    ]
}

// MARK: - 阅读样式

/// 阅读页唯一样式状态。翻页方式不再是设置项：所有正文页面固定使用 pageCurl。
final class ReaderPageStyle: ObservableObject {
    static let shared = ReaderPageStyle()

    private let defaults: UserDefaults

    @Published var fontSize: Double { didSet { defaults.set(fontSize, forKey: Keys.fontSize) } }
    @Published var bold: Bool { didSet { defaults.set(bold, forKey: Keys.bold) } }
    @Published var lineSpacing: Double { didSet { defaults.set(lineSpacing, forKey: Keys.lineSpacing) } }
    @Published var paragraphSpacing: Double { didSet { defaults.set(paragraphSpacing, forKey: Keys.paragraphSpacing) } }
    @Published var paragraphIndent: Int { didSet { defaults.set(paragraphIndent, forKey: Keys.paragraphIndent) } }
    @Published var paddingH: Double { didSet { defaults.set(paddingH, forKey: Keys.paddingH) } }
    @Published var paddingTop: Double { didSet { defaults.set(paddingTop, forKey: Keys.paddingTop) } }
    @Published var paddingBottom: Double { didSet { defaults.set(paddingBottom, forKey: Keys.paddingBottom) } }
    @Published var themeID: String { didSet { defaults.set(themeID, forKey: Keys.themeID) } }
    @Published var nightMode: Bool { didSet { defaults.set(nightMode, forKey: Keys.nightMode) } }
    @Published var fontFamily: Int { didSet { defaults.set(fontFamily, forKey: Keys.fontFamily) } }

    private enum Keys {
        static let fontSize = "reader.page.fontSize"
        static let bold = "reader.page.bold"
        static let lineSpacing = "reader.page.lineSpacing"
        static let paragraphSpacing = "reader.page.paragraphSpacing"
        static let paragraphIndent = "reader.page.paragraphIndent"
        static let paddingH = "reader.page.paddingH"
        static let paddingTop = "reader.page.paddingTop"
        static let paddingBottom = "reader.page.paddingBottom"
        static let themeID = "reader.page.themeID"
        static let nightMode = "reader.page.nightMode"
        static let fontFamily = "reader.page.fontFamily"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.fontSize = defaults.object(forKey: Keys.fontSize) as? Double ?? 18
        self.bold = defaults.object(forKey: Keys.bold) as? Bool ?? false
        self.lineSpacing = defaults.object(forKey: Keys.lineSpacing) as? Double ?? 12
        self.paragraphSpacing = defaults.object(forKey: Keys.paragraphSpacing) as? Double ?? 14
        self.paragraphIndent = defaults.object(forKey: Keys.paragraphIndent) as? Int ?? 2
        self.paddingH = defaults.object(forKey: Keys.paddingH) as? Double ?? 24
        self.paddingTop = defaults.object(forKey: Keys.paddingTop) as? Double ?? 50
        self.paddingBottom = defaults.object(forKey: Keys.paddingBottom) as? Double ?? 40
        self.themeID = defaults.object(forKey: Keys.themeID) as? String ?? "beige"
        self.nightMode = defaults.object(forKey: Keys.nightMode) as? Bool ?? false
        self.fontFamily = defaults.object(forKey: Keys.fontFamily) as? Int ?? 1
    }

    var theme: ReaderPageTheme {
        if nightMode { return ReaderPageTheme.all.first { $0.id == "night" } ?? ReaderPageTheme.all[0] }
        return ReaderPageTheme.all.first { $0.id == themeID } ?? ReaderPageTheme.all[0]
    }

    var uiFont: UIFont {
        let base = bold ? UIFont.boldSystemFont(ofSize: fontSize) : UIFont.systemFont(ofSize: fontSize)
        guard fontFamily == 1, let descriptor = base.fontDescriptor.withDesign(.serif) else { return base }
        return UIFont(descriptor: descriptor, size: 0)
    }

    var firstLineIndent: CGFloat { CGFloat(fontSize * Double(max(paragraphIndent, 0))) }
}
