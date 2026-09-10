import SwiftUI
import UIKit

// MARK: - 翻页动画类型

enum PageAnimationType: Int, CaseIterable, Identifiable {
    // 存储值约定：0=平移；1=滑动（覆盖式，旧覆盖值重新启用）；
    // 2=仿真；3=上下滚动；4=无动画（旧“淡入淡出”即占此值，语义回归无动画）。
    case pageCurl = 2      // UIPageViewController(.pageCurl, doubleSided)
    case cover = 1         // 新页从右侧滑入覆盖旧页（跟手）
    case pageScroll = 0    // UIPageViewController(.scroll)
    case freeScroll = 3    // UIScrollView 竖向连续滚动
    case none = 4          // 无动画，瞬时切换

    var id: Int { rawValue }
    var name: String {
        switch self {
        case .pageCurl: return "仿真"
        case .cover: return "滑动"
        case .pageScroll: return "平移"
        case .freeScroll: return "上下滚动"
        case .none: return "无动画"
        }
    }
    var icon: String {
        switch self {
        case .pageCurl: return "book.pages"
        case .cover: return "rectangle.portrait.righthalf.filled"
        case .pageScroll: return "rectangle.portrait.and.arrow.right"
        case .freeScroll: return "arrow.up.and.down"
        case .none: return "circle.lefthalf.filled"
        }
    }
    /// 设置面板中的展示顺序：仿真，滑动，平移，上下滚动，无动画。
    static var preferredOrder: [PageAnimationType] {
        [.pageCurl, .cover, .pageScroll, .freeScroll, .none]
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
    @Published var pageAnim: Int { didSet { defaults.set(pageAnim, forKey: Keys.pageAnim) } }
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

    private enum Keys {
        static let pageAnim = "reader.pageAnim"
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
        self.pageAnim = defaults.object(forKey: Keys.pageAnim) as? Int ?? PageAnimationType.pageScroll.rawValue
        self.fontSize = defaults.object(forKey: Keys.fontSize) as? Double ?? 18
        self.bold = defaults.object(forKey: Keys.bold) as? Bool ?? false
        self.lineSpacing = defaults.object(forKey: Keys.lineSpacing) as? Double ?? 6
        self.paragraphSpacing = defaults.object(forKey: Keys.paragraphSpacing) as? Double ?? 10
        self.paragraphIndent = defaults.object(forKey: Keys.paragraphIndent) as? Int ?? 2
        self.paddingH = defaults.object(forKey: Keys.paddingH) as? Double ?? 20
        self.paddingTop = defaults.object(forKey: Keys.paddingTop) as? Double ?? 50
        self.paddingBottom = defaults.object(forKey: Keys.paddingBottom) as? Double ?? 40
        self.themeId = defaults.object(forKey: Keys.themeId) as? String ?? "beige"
        self.nightMode = defaults.object(forKey: Keys.nightMode) as? Bool ?? false
        self.autoReadSpeed = defaults.object(forKey: Keys.autoReadSpeed) as? Double ?? 3.5
    }

    var currentPageAnim: PageAnimationType { PageAnimationType(rawValue: pageAnim) ?? .pageScroll }

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

    var swiftUIFont: Font {
        .system(size: fontSize, weight: bold ? .bold : .regular)
    }

    var uiFont: UIFont {
        bold ? UIFont.boldSystemFont(ofSize: fontSize) : UIFont.systemFont(ofSize: fontSize)
    }

    /// CoreText 分页用的段落对齐方式
    var coreTextAlignment: NSTextAlignment { .justified }

    /// 段落缩进（按字符数计算的像素值）
    var indentPixels: CGFloat { fontSize * CGFloat(max(paragraphIndent, 0)) }
}
