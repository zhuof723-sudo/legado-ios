import SwiftUI
import UIKit

// MARK: - 翻页方式

/// 翻页方式三档（Apple Books 同款）：仿真卷页 / 平移 / 无动画。
enum PageTurnStyle: Int, CaseIterable, Identifiable {
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

// MARK: - 阅读主题

struct ReaderTheme: Identifiable, Equatable {
    let id: String
    let name: String
    let background: Color
    let textColor: Color

    static let themes: [ReaderTheme] = [
        ReaderTheme(id: "paper", name: "纸白",
                    background: Color(red: 0.99, green: 0.99, blue: 0.98),
                    textColor: Color(red: 0.13, green: 0.13, blue: 0.14)),
        ReaderTheme(id: "beige", name: "米黄",
                    background: Color(red: 0.96, green: 0.93, blue: 0.86),
                    textColor: Color(red: 0.20, green: 0.17, blue: 0.12)),
        ReaderTheme(id: "green", name: "护眼",
                    background: Color(red: 0.89, green: 0.94, blue: 0.87),
                    textColor: Color(red: 0.16, green: 0.22, blue: 0.16)),
        ReaderTheme(id: "gray", name: "浅灰",
                    background: Color(red: 0.92, green: 0.92, blue: 0.92),
                    textColor: Color(red: 0.18, green: 0.18, blue: 0.18)),
        ReaderTheme(id: "night", name: "夜间",
                    background: Color(red: 0.10, green: 0.10, blue: 0.11),
                    textColor: Color(red: 0.85, green: 0.85, blue: 0.87)),
        ReaderTheme(id: "dark", name: "暗黑",
                    background: Color(red: 0.05, green: 0.05, blue: 0.06),
                    textColor: Color(red: 0.70, green: 0.70, blue: 0.73)),
    ]
}

// MARK: - 统一阅读配置

final class ReaderConfig: ObservableObject {
    static let shared = ReaderConfig()

    private let defaults: UserDefaults

    // 用 @Published 替代直接放在 ObservableObject 里的 @AppStorage。
    // 后者不会稳定地向依赖 config 的阅读器视图发送 objectWillChange，
    // 导致改字号、边距或主题后分页和页面样式不刷新。
    @Published var turnStyle: Int { didSet { defaults.set(turnStyle, forKey: Keys.turnStyle) } }
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
    /// 字体族：0=无衬线（黑体），1=衬线（宋体）。对应 Apple Books Aa 面板的字体切换。
    @Published var fontFamily: Int { didSet { defaults.set(fontFamily, forKey: Keys.fontFamily) } }

    private enum Keys {
        static let turnStyle = "reader.turnStyle"
        static let legacyPageAnim = "reader.pageAnim"
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
        // 翻页方式迁移：旧 reader.pageAnim（0=平移 1=滑动覆盖 2=仿真 3=上下滚动 4=无动画）
        // → 新 reader.turnStyle（0=仿真 1=平移 2=无动画）。上下滚动映射为平移，覆盖映射为仿真。
        if let stored = defaults.object(forKey: Keys.turnStyle) as? Int {
            self.turnStyle = stored
        } else {
            let legacy = defaults.integer(forKey: Keys.legacyPageAnim)
            let mapped: PageTurnStyle = legacy == 4 ? .none : (legacy == 1 || legacy == 2 ? .curl : .slide)
            self.turnStyle = mapped.rawValue
            defaults.removeObject(forKey: Keys.legacyPageAnim)
        }
        self.fontSize = defaults.object(forKey: Keys.fontSize) as? Double ?? 18
        self.bold = defaults.object(forKey: Keys.bold) as? Bool ?? false
        // 参考项目默认排版：行距倍数 1.65(字号18 → 11.7pt)、段距 0.8×字号(14.4)、左右边距 24。
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

    var currentTurnStyle: PageTurnStyle { PageTurnStyle(rawValue: turnStyle) ?? .slide }

    /// 字体族枚举
    enum ReaderFontFamily: Int, CaseIterable, Identifiable {
        case sans = 0
        case serif = 1
        var id: Int { rawValue }
        var name: String { self == .serif ? "衬线 · 宋体" : "无衬线 · 黑体" }
        var shortName: String { self == .serif ? "宋体" : "黑体" }
    }

    var currentFontFamily: ReaderFontFamily { ReaderFontFamily(rawValue: fontFamily) ?? .serif }

    var currentTheme: ReaderTheme {
        if nightMode {
            return ReaderTheme.themes.first { $0.id == "night" } ?? ReaderTheme.themes[0]
        }
        return ReaderTheme.themes.first { $0.id == themeId } ?? ReaderTheme.themes[0]
    }

    /// 当前主题的主色调
    var currentAccent: Color {
        nightMode ? Theme.accent.opacity(0.8) : Theme.accent
    }

    var uiFont: UIFont {
        let base = bold ? UIFont.boldSystemFont(ofSize: fontSize) : UIFont.systemFont(ofSize: fontSize)
        // 衬线体：iOS 的 .serif 设计在 CJK 上自动落到宋体系，无需硬编码字体名。
        // withDesign 是 UIFontDescriptor 的 API，size 传 0 表示沿用原字号。
        guard currentFontFamily == .serif,
              let descriptor = base.fontDescriptor.withDesign(.serif) else { return base }
        return UIFont(descriptor: descriptor, size: 0)
    }

    /// 段落缩进（按字符数计算的像素值）
    var indentPixels: CGFloat { fontSize * CGFloat(max(paragraphIndent, 0)) }
}
