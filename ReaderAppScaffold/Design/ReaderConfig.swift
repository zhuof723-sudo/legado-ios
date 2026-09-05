import SwiftUI
import UIKit

// MARK: - 翻页动画类型（对齐 legado-E PageAnim）

enum PageAnimationType: Int, CaseIterable, Identifiable {
    case simulation = 0   // 仿真翻页
    case slide = 1        // 滑动翻页
    case cover = 2        // 覆盖翻页
    case scroll = 3       // 滚动翻页
    case none = 4         // 无动画

    var id: Int { rawValue }

    var name: String {
        switch self {
        case .simulation: return "仿真"
        case .slide: return "滑动"
        case .cover: return "覆盖"
        case .scroll: return "滚动"
        case .none: return "无动画"
        }
    }

    var icon: String {
        switch self {
        case .simulation: return "book.pages"
        case .slide: return "rectangle.portrait.and.arrow.right"
        case .cover: return "rectangle.stack"
        case .scroll: return "arrow.up.and.down"
        case .none: return "pause"
        }
    }
}

// MARK: - 字体类型

enum ReaderFont: String, CaseIterable, Identifiable {
    case system = "系统默认"
    case serif = "宋体"
    case kai = "楷体"
    case hei = "黑体"
    case round = "圆体"

    var id: String { rawValue }

    var fontName: String? {
        switch self {
        case .system: return nil
        case .serif: return "Songti SC"
        case .kai: return "Kaiti SC"
        case .hei: return "Heiti SC"
        case .round: return "Yuanti SC"
        }
    }

    func uiFont(size: CGFloat, bold: Bool) -> UIFont {
        if let fontName = fontName {
            let descriptor = UIFontDescriptor(name: fontName, size: size)
                .withSymbolicTraits(bold ? .traitBold : [])
            return UIFont(descriptor: descriptor ?? UIFontDescriptor(name: fontName, size: size), size: size)
        }
        return bold ? UIFont.boldSystemFont(ofSize: size) : UIFont.systemFont(ofSize: size)
    }

    func swiftUIFont(size: CGFloat, bold: Bool) -> Font {
        if let fontName = fontName {
            return Font.custom(fontName, size: size).weight(bold ? .bold : .regular)
        }
        return .system(size: size, weight: bold ? .bold : .regular)
    }
}

// MARK: - 阅读主题

struct ReaderTheme: Identifiable, Equatable {
    let id: String
    let name: String
    let background: Color
    let textColor: Color
    let accentColor: Color

    static let themes: [ReaderTheme] = [
        ReaderTheme(id: "paper", name: "纸白",
                    background: Color(red: 0.99, green: 0.99, blue: 0.98),
                    textColor: Color(red: 0.13, green: 0.13, blue: 0.14),
                    accentColor: Color(red: 0.60, green: 0.40, blue: 0.20)),
        ReaderTheme(id: "beige", name: "米黄",
                    background: Color(red: 0.96, green: 0.93, blue: 0.86),
                    textColor: Color(red: 0.20, green: 0.17, blue: 0.12),
                    accentColor: Color(red: 0.65, green: 0.45, blue: 0.20)),
        ReaderTheme(id: "green", name: "浅绿",
                    background: Color(red: 0.90, green: 0.94, blue: 0.88),
                    textColor: Color(red: 0.16, green: 0.22, blue: 0.16),
                    accentColor: Color(red: 0.30, green: 0.50, blue: 0.30)),
        ReaderTheme(id: "gray", name: "浅灰",
                    background: Color(red: 0.92, green: 0.92, blue: 0.92),
                    textColor: Color(red: 0.18, green: 0.18, blue: 0.18),
                    accentColor: Color(red: 0.40, green: 0.40, blue: 0.40)),
        ReaderTheme(id: "pink", name: "粉色",
                    background: Color(red: 0.97, green: 0.92, blue: 0.93),
                    textColor: Color(red: 0.22, green: 0.15, blue: 0.17),
                    accentColor: Color(red: 0.75, green: 0.40, blue: 0.50)),
        ReaderTheme(id: "blue", name: "浅蓝",
                    background: Color(red: 0.90, green: 0.93, blue: 0.97),
                    textColor: Color(red: 0.15, green: 0.18, blue: 0.25),
                    accentColor: Color(red: 0.30, green: 0.45, blue: 0.70)),
        ReaderTheme(id: "night", name: "夜间",
                    background: Color(red: 0.10, green: 0.10, blue: 0.11),
                    textColor: Color(red: 0.88, green: 0.88, blue: 0.90),
                    accentColor: Color(red: 0.60, green: 0.60, blue: 0.70)),
        ReaderTheme(id: "dark", name: "暗黑",
                    background: Color(red: 0.05, green: 0.05, blue: 0.06),
                    textColor: Color(red: 0.75, green: 0.75, blue: 0.78),
                    accentColor: Color(red: 0.50, green: 0.50, blue: 0.55)),
    ]
}

// MARK: - 统一阅读配置（对齐 legado-E ReadBookConfig）

final class ReaderConfig: ObservableObject {
    static let shared = ReaderConfig()

    // 翻页动画
    @AppStorage("reader.pageAnim") var pageAnim: Int = PageAnimationType.slide.rawValue

    // 字体排版
    @AppStorage("reader.font") var fontName: String = ReaderFont.system.rawValue
    @AppStorage("reader.fontSize") var fontSize: Double = 18
    @AppStorage("reader.bold") var bold: Bool = false
    @AppStorage("reader.lineSpacing") var lineSpacing: Double = 8
    @AppStorage("reader.paragraphSpacing") var paragraphSpacing: Double = 12
    @AppStorage("reader.letterSpacing") var letterSpacing: Double = 0
    @AppStorage("reader.paragraphIndent") var paragraphIndent: Int = 2  // 缩进字符数，0=不缩进
    @AppStorage("reader.textAlignment") var textAlignment: Int = 0  // 0=两端对齐 1=左对齐 2=居中

    // 边距
    @AppStorage("reader.paddingLeft") var paddingLeft: Double = 20
    @AppStorage("reader.paddingRight") var paddingRight: Double = 20
    @AppStorage("reader.paddingTop") var paddingTop: Double = 56
    @AppStorage("reader.paddingBottom") var paddingBottom: Double = 44

    // 主题
    @AppStorage("reader.themeId") var themeId: String = "beige"
    @AppStorage("reader.nightMode") var nightMode: Bool = false
    @AppStorage("reader.eyeCare") var eyeCare: Bool = false

    // 其他
    @AppStorage("reader.autoReadSpeed") var autoReadSpeed: Double = 3.5
    @AppStorage("reader.immersive") var immersive: Bool = true

    var currentFont: ReaderFont {
        ReaderFont(rawValue: fontName) ?? .system
    }

    var currentPageAnim: PageAnimationType {
        PageAnimationType(rawValue: pageAnim) ?? .slide
    }

    var currentTheme: ReaderTheme {
        if nightMode {
            return ReaderTheme.themes.first { $0.id == "night" } ?? ReaderTheme.themes[0]
        }
        return ReaderTheme.themes.first { $0.id == themeId } ?? ReaderTheme.themes[0]
    }

    var swiftUIFont: Font {
        currentFont.swiftUIFont(size: fontSize, bold: bold)
    }

    var uiFont: UIFont {
        currentFont.uiFont(size: fontSize, bold: bold)
    }

    var textAlignmentValue: TextAlignment {
        switch textAlignment {
        case 1: return .leading
        case 2: return .center
        default: return .leading  // SwiftUI Text 不支持 justified，分页时用 CoreText 的 .justified
        }
    }

    /// CoreText 分页用的段落对齐方式
    var coreTextAlignment: NSTextAlignment {
        switch textAlignment {
        case 1: return .left
        case 2: return .center
        default: return .justified
        }
    }

    /// 段落缩进前缀（按字符数计算）
    var indentPrefix: String {
        guard paragraphIndent > 0 else { return "" }
        return String(repeating: "\u{3000}", count: paragraphIndent)
    }
}
