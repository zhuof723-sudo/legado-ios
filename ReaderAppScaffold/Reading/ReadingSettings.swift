import SwiftUI
import UIKit

// MARK: - 翻页方式

/// 翻页方式三档：仿真卷页 / 平移 / 无动画。
enum TurnMode: Int, CaseIterable, Identifiable {
    case curl = 0       // UIPageViewController .pageCurl
    case slide = 1      // UIPageViewController .scroll
    case none = 2       // 瞬时切换

    var id: Int { rawValue }
    var name: String {
        switch self {
        case .curl: return "仿真翻页"
        case .slide: return "平移"
        case .none: return "无动画"
        }
    }
    var icon: String {
        switch self {
        case .curl: return "book.pages"
        case .slide: return "rectangle.portrait.and.arrow.right"
        case .none: return "circle.lefthalf.filled"
        }
    }
}

// MARK: - 字体族

enum ReadingFontFamily: Int, CaseIterable, Identifiable {
    case sans = 0
    case serif = 1
    var id: Int { rawValue }
    var name: String { self == .serif ? "衬线 · 宋体" : "无衬线 · 黑体" }
    var shortName: String { self == .serif ? "宋体" : "黑体" }
}

// MARK: - 阅读主题

struct ReadingTheme: Identifiable, Equatable {
    let id: String
    let name: String
    let background: Color
    let textColor: Color

    static let themes: [ReadingTheme] = [
        ReadingTheme(id: "paper", name: "纸白",
                     background: Color(red: 0.99, green: 0.99, blue: 0.98),
                     textColor: Color(red: 0.13, green: 0.13, blue: 0.14)),
        ReadingTheme(id: "beige", name: "米黄",
                     background: Color(red: 0.96, green: 0.93, blue: 0.86),
                     textColor: Color(red: 0.20, green: 0.17, blue: 0.12)),
        ReadingTheme(id: "green", name: "护眼",
                     background: Color(red: 0.89, green: 0.94, blue: 0.87),
                     textColor: Color(red: 0.16, green: 0.22, blue: 0.16)),
        ReadingTheme(id: "gray", name: "浅灰",
                     background: Color(red: 0.92, green: 0.92, blue: 0.92),
                     textColor: Color(red: 0.18, green: 0.18, blue: 0.18)),
        ReadingTheme(id: "night", name: "夜间",
                     background: Color(red: 0.10, green: 0.10, blue: 0.11),
                     textColor: Color(red: 0.85, green: 0.85, blue: 0.87)),
        ReadingTheme(id: "dark", name: "暗黑",
                     background: Color(red: 0.05, green: 0.05, blue: 0.06),
                     textColor: Color(red: 0.70, green: 0.70, blue: 0.73)),
    ]
}

// MARK: - 阅读偏好设置

/// 阅读偏好：排版、主题、翻页方式的唯一事实来源。
/// 持久化沿用原有 UserDefaults 键，老用户的设置不受影响。
final class ReadingPreferences: ObservableObject {
    static let shared = ReadingPreferences()

    private let defaults: UserDefaults

    @Published var turnMode: Int { didSet { defaults.set(turnMode, forKey: Keys.turnMode) } }
    @Published var fontSize: Double { didSet { defaults.set(fontSize, forKey: Keys.fontSize) } }
    @Published var bold: Bool { didSet { defaults.set(bold, forKey: Keys.bold) } }
    @Published var lineSpacing: Double { didSet { defaults.set(lineSpacing, forKey: Keys.lineSpacing) } }
    @Published var paragraphSpacing: Double { didSet { defaults.set(paragraphSpacing, forKey: Keys.paragraphSpacing) } }
    @Published var paragraphIndent: Int { didSet { defaults.set(paragraphIndent, forKey: Keys.paragraphIndent) } }
    @Published var paddingH: Double { didSet { defaults.set(paddingH, forKey: Keys.paddingH) } }
    @Published var paddingTop: Double { didSet { defaults.set(paddingTop, forKey: Keys.paddingTop) } }
    @Published var paddingBottom: Double { didSet { defaults.set(paddingBottom, forKey: Keys.paddingBottom) } }
    @Published var themeId: String { didSet { defaults.set(themeId, forKey: Keys.themeId) } }
    @Published var nightMode: Bool { didSet { defaults.set(nightMode, forKey: Keys.nightMode) } }
    @Published var autoReadSpeed: Double { didSet { defaults.set(autoReadSpeed, forKey: Keys.autoReadSpeed) } }
    @Published var fontFamily: Int { didSet { defaults.set(fontFamily, forKey: Keys.fontFamily) } }

    private enum Keys {
        static let turnMode = "reader.turnStyle"
        static let fontFamily = "reader.fontFamily"
        static let fontSize = "reader.fontSize"
        static let bold = "reader.bold"
        static let lineSpacing = "reader.lineSpacing"
        static let paragraphSpacing = "reader.paragraphSpacing"
        static let paragraphIndent = "reader.paragraphIndent"
        static let paddingH = "reader.paddingH"
        static let paddingTop = "reader.paddingTop"
        static let paddingBottom = "reader.paddingBottom"
        static let themeId = "reader.themeId"
        static let nightMode = "reader.nightMode"
        static let autoReadSpeed = "reader.autoReadSpeed"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.turnMode = defaults.object(forKey: Keys.turnMode) as? Int ?? TurnMode.slide.rawValue
        self.fontSize = defaults.object(forKey: Keys.fontSize) as? Double ?? 18
        self.bold = defaults.object(forKey: Keys.bold) as? Bool ?? false
        // 默认排版：行距 12pt、段距 14pt、首行缩进 2 字符、左右边距 24。
        self.lineSpacing = defaults.object(forKey: Keys.lineSpacing) as? Double ?? 12
        self.paragraphSpacing = defaults.object(forKey: Keys.paragraphSpacing) as? Double ?? 14
        self.paragraphIndent = defaults.object(forKey: Keys.paragraphIndent) as? Int ?? 2
        self.paddingH = defaults.object(forKey: Keys.paddingH) as? Double ?? 24
        self.paddingTop = defaults.object(forKey: Keys.paddingTop) as? Double ?? 50
        self.paddingBottom = defaults.object(forKey: Keys.paddingBottom) as? Double ?? 40
        self.themeId = defaults.object(forKey: Keys.themeId) as? String ?? "beige"
        self.nightMode = defaults.object(forKey: Keys.nightMode) as? Bool ?? false
        self.autoReadSpeed = defaults.object(forKey: Keys.autoReadSpeed) as? Double ?? 3.5
        // 默认衬线体：贴近 Apple Books 的正文排版（CJK 下自动落到宋体系）。
        self.fontFamily = defaults.object(forKey: Keys.fontFamily) as? Int ?? 1
    }

    var currentTurnMode: TurnMode { TurnMode(rawValue: turnMode) ?? .slide }

    var currentFontFamily: ReadingFontFamily { ReadingFontFamily(rawValue: fontFamily) ?? .serif }

    var currentTheme: ReadingTheme {
        if nightMode {
            return ReadingTheme.themes.first { $0.id == "night" } ?? ReadingTheme.themes[0]
        }
        return ReadingTheme.themes.first { $0.id == themeId } ?? ReadingTheme.themes[0]
    }

    var currentAccent: Color {
        nightMode ? Theme.accent.opacity(0.8) : Theme.accent
    }

    var uiFont: UIFont {
        let base = bold ? UIFont.boldSystemFont(ofSize: fontSize) : UIFont.systemFont(ofSize: fontSize)
        // 衬线体：iOS 的 .serif 设计在 CJK 上自动落到宋体系，无需硬编码字体名。
        guard currentFontFamily == .serif,
              let descriptor = base.fontDescriptor.withDesign(.serif) else { return base }
        return UIFont(descriptor: descriptor, size: 0)
    }

    /// 段落缩进（按字符数换算的像素值）
    var indentPixels: CGFloat { fontSize * CGFloat(max(paragraphIndent, 0)) }
}
