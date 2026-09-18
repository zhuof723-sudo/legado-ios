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

final class BookReaderStyle: ObservableObject {
    static let shared = BookReaderStyle()
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
    @Published var turnMode: String { didSet { defaults.set(turnMode, forKey: Keys.turnMode) } }

    private enum Keys {
        static let fontSize = "reader.book.fontSize"
        static let bold = "reader.book.bold"
        static let lineSpacing = "reader.book.lineSpacing"
        static let paragraphSpacing = "reader.book.paragraphSpacing"
        static let paragraphIndent = "reader.book.paragraphIndent"
        static let paddingH = "reader.book.paddingH"
        static let paddingTop = "reader.book.paddingTop"
        static let paddingBottom = "reader.book.paddingBottom"
        static let themeID = "reader.book.themeID"
        static let nightMode = "reader.book.nightMode"
        static let fontFamily = "reader.book.fontFamily"
        static let turnMode = "reader.book.turnMode"
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
        self.themeID = defaults.object(forKey: Keys.themeID) as? String ?? "sepia"
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

    var firstLineIndent: CGFloat { CGFloat(fontSize * Double(max(paragraphIndent, 0))) }
}
