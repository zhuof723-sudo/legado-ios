import SwiftUI
import UIKit

// MARK: - 翻页动画类型

enum PageAnimationType: Int, CaseIterable, Identifiable {
    case slide = 0        // 滑动翻页（默认，最稳定）
    case cover = 1        // 覆盖翻页
    case simulation = 2   // 仿真翻页
    case scroll = 3       // 滚动翻页
    case none = 4         // 无动画

    var id: Int { rawValue }
    var name: String {
        switch self {
        case .slide: return "滑动"
        case .cover: return "覆盖"
        case .simulation: return "仿真"
        case .scroll: return "滚动"
        case .none: return "无动画"
        }
    }
    var icon: String {
        switch self {
        case .slide: return "rectangle.portrait.and.arrow.right"
        case .cover: return "rectangle.stack"
        case .simulation: return "book.pages"
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
    case monospace = "等宽"

    var id: String { rawValue }

    var fontName: String? {
        switch self {
        case .system: return nil
        case .serif: return "Songti SC"
        case .kai: return "Kaiti SC"
        case .hei: return "Heiti SC"
        case .round: return "Yuanti SC"
        case .monospace: return "Menlo"
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

    // 翻页动画
    @AppStorage("reader.pageAnim") var pageAnim: Int = PageAnimationType.slide.rawValue

    // 字体排版
    @AppStorage("reader.font") var fontName: String = ReaderFont.system.rawValue
    @AppStorage("reader.fontSize") var fontSize: Double = 18
    @AppStorage("reader.bold") var bold: Bool = false
    @AppStorage("reader.lineSpacing") var lineSpacing: Double = 6
    @AppStorage("reader.paragraphSpacing") var paragraphSpacing: Double = 10
    @AppStorage("reader.paragraphIndent") var paragraphIndent: Int = 2

    // 边距
    @AppStorage("reader.paddingH") var paddingH: Double = 20
    @AppStorage("reader.paddingTop") var paddingTop: Double = 50
    @AppStorage("reader.paddingBottom") var paddingBottom: Double = 40

    // 主题
    @AppStorage("reader.themeId") var themeId: String = "beige"
    @AppStorage("reader.nightMode") var nightMode: Bool = false

    // 其他
    @AppStorage("reader.autoReadSpeed") var autoReadSpeed: Double = 3.5

    var currentFont: ReaderFont { ReaderFont(rawValue: fontName) ?? .system }
    var currentPageAnim: PageAnimationType { PageAnimationType(rawValue: pageAnim) ?? .slide }

    var currentTheme: ReaderTheme {
        if nightMode {
            return ReaderTheme.themes.first { $0.id == "night" } ?? ReaderTheme.themes[0]
        }
        return ReaderTheme.themes.first { $0.id == themeId } ?? ReaderTheme.themes[0]
    }

    var swiftUIFont: Font { currentFont.swiftUIFont(size: fontSize, bold: bold) }
    var uiFont: UIFont { currentFont.uiFont(size: fontSize, bold: bold) }

    /// CoreText 分页用的段落对齐方式
    var coreTextAlignment: NSTextAlignment { .justified }

    /// 段落缩进（按字符数计算的像素值）
    var indentPixels: CGFloat { fontSize * CGFloat(max(paragraphIndent, 0)) }
}
