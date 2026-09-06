import SwiftUI

// MARK: - 主题模式枚举

enum AppThemeMode: String, CaseIterable, Identifiable {
    case light = "light"
    case dark = "dark"

    var id: String { rawValue }

    var name: String {
        switch self {
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }

    var icon: String {
        switch self {
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }
}

// MARK: - 全局视觉主题

enum Theme {
    // 主色调：珊瑚粉
    static let accent = Color(red: 0.910, green: 0.604, blue: 0.604)      // #E89A9A
    static let accentDeep = Color(red: 0.820, green: 0.490, blue: 0.490)  // #D17D7D

    // 根据模式动态返回颜色
    static func bg(for mode: AppThemeMode) -> Color {
        switch mode {
        case .light: return Color(red: 0.965, green: 0.945, blue: 0.965)  // #F6F1F6 柔粉底
        case .dark: return Color(red: 0.12, green: 0.12, blue: 0.14)      // 深灰底
        }
    }

    static func cardBg(for mode: AppThemeMode) -> Color {
        switch mode {
        case .light: return Color.white
        case .dark: return Color(red: 0.18, green: 0.18, blue: 0.20)
        }
    }

    static func textPrimary(for mode: AppThemeMode) -> Color {
        switch mode {
        case .light: return Color(red: 0.13, green: 0.13, blue: 0.14)
        case .dark: return Color(red: 0.92, green: 0.92, blue: 0.94)
        }
    }

    static func textSecondary(for mode: AppThemeMode) -> Color {
        switch mode {
        case .light: return Color(red: 0.50, green: 0.50, blue: 0.52)
        case .dark: return Color(red: 0.65, green: 0.65, blue: 0.68)
        }
    }

    static func hairline(for mode: AppThemeMode) -> Color {
        switch mode {
        case .light: return Color(red: 0.910, green: 0.604, blue: 0.604).opacity(0.12)
        case .dark: return Color.white.opacity(0.08)
        }
    }

    static func shadow(for mode: AppThemeMode) -> Color {
        switch mode {
        case .light: return Color(red: 0.910, green: 0.604, blue: 0.604).opacity(0.10)
        case .dark: return Color.black.opacity(0.30)
        }
    }

    // 默认浅色主题的颜色（向后兼容）
    static let bg = bg(for: .light)
    static let cardBg = cardBg(for: .light)
    static let hairline = hairline(for: .light)
    static let shadow = shadow(for: .light)

    /// 阅读器可选背景色
    static let readerBackgrounds: [Color] = [
        Color(red: 0.99, green: 0.99, blue: 0.98),
        Color(red: 0.96, green: 0.93, blue: 0.86),
        Color(red: 0.90, green: 0.94, blue: 0.88),
        Color(red: 0.92, green: 0.92, blue: 0.92),
        Color(red: 0.10, green: 0.10, blue: 0.11),
    ]
    static let readerTextColors: [Color] = [
        Color(red: 0.13, green: 0.13, blue: 0.14),
        Color(red: 0.20, green: 0.17, blue: 0.12),
        Color(red: 0.16, green: 0.22, blue: 0.16),
        Color(red: 0.18, green: 0.18, blue: 0.18),
        Color(red: 0.88, green: 0.88, blue: 0.90),
    ]
}

// MARK: - 卡片样式兼容封装

extension View {
    /// 标准卡片样式
    @ViewBuilder
    func cardStyle(cornerRadius: CGFloat = 14, mode: AppThemeMode = .light) -> some View {
        self.background(
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Theme.cardBg(for: mode))
                .shadow(color: Theme.shadow(for: mode), radius: 6, y: 2)
        )
    }

    /// 卡片/面板玻璃
    @ViewBuilder
    func glassCard<S: Shape>(_ shape: S, interactive: Bool = false, mode: AppThemeMode = .light) -> some View {
        self.background(.ultraThinMaterial, in: shape)
            .overlay(shape.stroke(Theme.hairline(for: mode), lineWidth: 0.5))
    }

    /// 圆形玻璃（悬浮搜索等）
    @ViewBuilder
    func glassCircle(mode: AppThemeMode = .light) -> some View {
        self.background(.ultraThinMaterial, in: Circle())
            .shadow(color: Theme.shadow(for: mode), radius: 10, y: 4)
    }

    /// 强调按钮（红色主按钮）
    @ViewBuilder
    func prominentGlassButton() -> some View {
        self.buttonStyle(.borderedProminent)
    }

    /// 普通玻璃按钮
    @ViewBuilder
    func plainGlassButton() -> some View {
        self.buttonStyle(.bordered)
    }

    /// 底部标签栏随滚动收缩
    @ViewBuilder
    func minimizeTabBarOnScroll() -> some View {
        self
    }
}

// MARK: - 占位封面

struct PlaceholderCover: View {
    let title: String
    var mode: AppThemeMode = .light

    private var palette: [Color] {
        let presets: [[Color]] = [
            [Color(red: 0.98, green: 0.80, blue: 0.44), Color(red: 0.93, green: 0.55, blue: 0.30)],
            [Color(red: 0.55, green: 0.75, blue: 0.95), Color(red: 0.35, green: 0.52, blue: 0.85)],
            [Color(red: 0.60, green: 0.85, blue: 0.70), Color(red: 0.28, green: 0.62, blue: 0.52)],
            [Color(red: 0.85, green: 0.62, blue: 0.90), Color(red: 0.55, green: 0.38, blue: 0.80)],
            [Theme.accent, Theme.accentDeep],
        ]
        let h = title.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return presets[h % presets.count]
    }

    private var initials: String {
        String(title.prefix(2))
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: palette, startPoint: .topLeading, endPoint: .bottomTrailing)
            Text(initials)
                .font(.system(size: 22, weight: .bold, design: .serif))
                .foregroundStyle(Color.white.opacity(0.95))
                .shadow(color: Color.black.opacity(0.2), radius: 2, y: 1)
        }
    }
}

/// 封面视图
struct SmartCover: View {
    let url: String
    let title: String
    var headers: [String: String] = [:]
    var mode: AppThemeMode = .light

    var body: some View {
        Group {
            if url.isEmpty {
                PlaceholderCover(title: title, mode: mode)
            } else {
                CoverImageView(url: url, headers: headers)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - 章节进度条

struct MiniProgressBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.accent.opacity(0.15))
                Capsule()
                    .fill(Theme.accent)
                    .frame(width: max(4, geo.size.width * min(max(progress, 0), 1)))
            }
        }
        .frame(height: 4)
    }
}
