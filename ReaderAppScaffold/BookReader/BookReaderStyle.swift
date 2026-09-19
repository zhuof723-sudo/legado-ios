import SwiftUI
import UIKit

struct BookReaderTheme: Identifiable, Equatable {
    let id: String
    let name: String
    let background: Color
    let text: Color

    static let all: [BookReaderTheme] = [
        BookReaderTheme(id: "paper", name: "纸白", background: Color(red: 0.99, green: 0.99, blue: 0.98), text: Color(red: 0.13, green: 0.13, blue: 0.14)),
        BookReaderTheme(id: "sepia", name: "米黄", background: Color(red: 0.96, green: 0.93, blue: 0.86), text: Color(red: 0.20, green: 0.17, blue: 0.12)),
        BookReaderTheme(id: "green", name: "护眼", background: Color(red: 0.89, green: 0.94, blue: 0.87), text: Color(red: 0.16, green: 0.22, blue: 0.16)),
        BookReaderTheme(id: "night", name: "夜间", background: Color(red: 0.10, green: 0.10, blue: 0.11), text: Color(red: 0.85, green: 0.85, blue: 0.87)),
        BookReaderTheme(id: "dark", name: "暗黑", background: Color(red: 0.05, green: 0.05, blue: 0.06), text: Color(red: 0.70, green: 0.70, blue: 0.73))
    ]
}

enum BookReaderTurnMode: String, CaseIterable, Identifiable {
    case slide = "slide"
    case scroll = "scroll"
    case curl = "curl"
    case fade = "fade"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .slide: return "滑动"
        case .scroll: return "滚动"
        case .curl: return "仿真"
        case .fade: return "淡入淡出"
        }
    }
    var icon: String {
        switch self {
        case .slide: return "arrow.left.arrow.right"
        case .scroll: return "arrow.up.and.down"
        case .curl: return "book.pages"
        case .fade: return "circle.dashed"
        }
    }
}

/// 目标排版的默认值（对齐设计稿第一张）：行距 35%、段距 40%、
/// 左右边距 22%、上边距 30%、下边距 20%、标题间距 45%。
enum BookReaderDefaults {
    static let lineSpacingPercent = 35.0
    static let paragraphSpacingPercent = 40.0
    static let paddingHorizontalPercent = 22.0
    static let paddingTopPercent = 30.0
    static let paddingBottomPercent = 20.0
    static let titleSpacingPercent = 45.0
    /// 百分比 → 点的基准（字号 18pt 时行距 ≈ 12pt，与 Apple Books 观感一致）。
    static let spacingBase = 34.0
}

final class BookReaderStyle: ObservableObject {
    static let shared = BookReaderStyle()
    private let defaults: UserDefaults

    @Published var fontSize: Double { didSet { defaults.set(fontSize, forKey: Keys.fontSize) } }
    @Published var bold: Bool { didSet { defaults.set(bold, forKey: Keys.bold) } }
    @Published var lineSpacingPercent: Double { didSet { defaults.set(lineSpacingPercent, forKey: Keys.lineSpacingPercent) } }
    @Published var paragraphSpacingPercent: Double { didSet { defaults.set(paragraphSpacingPercent, forKey: Keys.paragraphSpacingPercent) } }
    @Published var paddingHorizontalPercent: Double { didSet { defaults.set(paddingHorizontalPercent, forKey: Keys.paddingHorizontalPercent) } }
    @Published var paddingTopPercent: Double { didSet { defaults.set(paddingTopPercent, forKey: Keys.paddingTopPercent) } }
    @Published var paddingBottomPercent: Double { didSet { defaults.set(paddingBottomPercent, forKey: Keys.paddingBottomPercent) } }
    @Published var titleSpacingPercent: Double { didSet { defaults.set(titleSpacingPercent, forKey: Keys.titleSpacingPercent) } }
    @Published var paragraphIndent: Int { didSet { defaults.set(paragraphIndent, forKey: Keys.paragraphIndent) } }
    @Published var themeID: String { didSet { defaults.set(themeID, forKey: Keys.themeID) } }
    @Published var nightMode: Bool { didSet { defaults.set(nightMode, forKey: Keys.nightMode) } }
    @Published var fontFamily: Int { didSet { defaults.set(fontFamily, forKey: Keys.fontFamily) } }
    @Published var turnMode: String { didSet { defaults.set(turnMode, forKey: Keys.turnMode) } }

    private enum Keys {
        static let fontSize = "reader.book2.fontSize"
        static let bold = "reader.book2.bold"
        static let lineSpacingPercent = "reader.book2.lineSpacingPercent"
        static let paragraphSpacingPercent = "reader.book2.paragraphSpacingPercent"
        static let paddingHorizontalPercent = "reader.book2.paddingHorizontalPercent"
        static let paddingTopPercent = "reader.book2.paddingTopPercent"
        static let paddingBottomPercent = "reader.book2.paddingBottomPercent"
        static let titleSpacingPercent = "reader.book2.titleSpacingPercent"
        static let paragraphIndent = "reader.book2.paragraphIndent"
        static let themeID = "reader.book2.themeID"
        static let nightMode = "reader.book2.nightMode"
        static let fontFamily = "reader.book2.fontFamily"
        static let turnMode = "reader.book2.turnMode"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.fontSize = defaults.object(forKey: Keys.fontSize) as? Double ?? 19
        self.bold = defaults.object(forKey: Keys.bold) as? Bool ?? false
        self.lineSpacingPercent = defaults.object(forKey: Keys.lineSpacingPercent) as? Double ?? BookReaderDefaults.lineSpacingPercent
        self.paragraphSpacingPercent = defaults.object(forKey: Keys.paragraphSpacingPercent) as? Double ?? BookReaderDefaults.paragraphSpacingPercent
        self.paddingHorizontalPercent = defaults.object(forKey: Keys.paddingHorizontalPercent) as? Double ?? BookReaderDefaults.paddingHorizontalPercent
        self.paddingTopPercent = defaults.object(forKey: Keys.paddingTopPercent) as? Double ?? BookReaderDefaults.paddingTopPercent
        self.paddingBottomPercent = defaults.object(forKey: Keys.paddingBottomPercent) as? Double ?? BookReaderDefaults.paddingBottomPercent
        self.titleSpacingPercent = defaults.object(forKey: Keys.titleSpacingPercent) as? Double ?? BookReaderDefaults.titleSpacingPercent
        self.paragraphIndent = defaults.object(forKey: Keys.paragraphIndent) as? Int ?? 2
        self.themeID = defaults.object(forKey: Keys.themeID) as? String ?? "green"
        self.nightMode = defaults.object(forKey: Keys.nightMode) as? Bool ?? false
        self.fontFamily = defaults.object(forKey: Keys.fontFamily) as? Int ?? 1
        self.turnMode = defaults.object(forKey: Keys.turnMode) as? String ?? BookReaderTurnMode.curl.rawValue
    }

    var theme: BookReaderTheme {
        if nightMode { return BookReaderTheme.all.first { $0.id == "night" } ?? BookReaderTheme.all[0] }
        return BookReaderTheme.all.first { $0.id == themeID } ?? BookReaderTheme.all[0]
    }

    var mode: BookReaderTurnMode { BookReaderTurnMode(rawValue: turnMode) ?? .curl }

    var font: UIFont {
        let base = bold ? UIFont.boldSystemFont(ofSize: fontSize) : UIFont.systemFont(ofSize: fontSize)
        guard fontFamily == 1, let descriptor = base.fontDescriptor.withDesign(.serif) else { return base }
        return UIFont(descriptor: descriptor, size: 0)
    }

    // MARK: - 百分比 → 点值

    /// 行距、段距、标题间距按字号缩放：字号越大，同一百分比给出的绝对间距越大。
    private var base: Double { fontSize * 1.8 }

    var lineSpacing: Double { base * lineSpacingPercent / 100 }
    var paragraphSpacing: Double { base * paragraphSpacingPercent / 100 }
    var titleSpacing: Double { base * titleSpacingPercent / 100 }

    /// 边距按屏幕宽度缩放，保证不同机型版心比例一致。
    var paddingH: Double { Self.screenWidth * paddingHorizontalPercent / 100 }
    var paddingTop: Double { Self.screenHeight * paddingTopPercent / 100 }
    var paddingBottom: Double { Self.screenHeight * paddingBottomPercent / 100 }

    var firstLineIndent: CGFloat { CGFloat(fontSize * Double(max(paragraphIndent, 0))) }

    private static var screenWidth: Double {
        Double(UIScreen.main.bounds.width > 0 ? UIScreen.main.bounds.width : 390)
    }
    private static var screenHeight: Double {
        Double(UIScreen.main.bounds.height > 0 ? UIScreen.main.bounds.height : 844)
    }
}