import SwiftUI

/// 全局视觉主题：奶油底色 + 珊瑚红点缀（对照设计稿）
enum Theme {
    static let accent = Color(red: 0.937, green: 0.325, blue: 0.310)      // #EF534F
    static let accentDeep = Color(red: 0.85, green: 0.24, blue: 0.24)
    static let bg = Color(red: 0.965, green: 0.953, blue: 0.933)          // #F6F3EE 奶油底
    static let cardBg = Color.white
    static let hairline = Color.black.opacity(0.06)

    /// 阅读器可选背景色
    static let readerBackgrounds: [Color] = [
        Color(red: 0.99, green: 0.99, blue: 0.98),                        // 纸白
        Color(red: 0.96, green: 0.93, blue: 0.86),                        // 米黄
        Color(red: 0.90, green: 0.94, blue: 0.88),                        // 浅绿
        Color(red: 0.92, green: 0.92, blue: 0.92),                        // 浅灰
        Color(red: 0.10, green: 0.10, blue: 0.11),                        // 夜间
    ]
    static let readerTextColors: [Color] = [
        Color(red: 0.13, green: 0.13, blue: 0.14),
        Color(red: 0.20, green: 0.17, blue: 0.12),
        Color(red: 0.16, green: 0.22, blue: 0.16),
        Color(red: 0.18, green: 0.18, blue: 0.18),
        Color(red: 0.88, green: 0.88, blue: 0.90),
    ]
}

// MARK: - 液态玻璃（iOS 26）兼容封装

extension View {
    /// 卡片/面板玻璃：iOS 26 用 Liquid Glass，低版本退化为材质
    @ViewBuilder
    func glassCard<S: Shape>(_ shape: S, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            if interactive {
                self.glassEffect(.regular.interactive(), in: shape)
            } else {
                self.glassEffect(.regular, in: shape)
            }
        } else {
            self.background(.regular.material, in: shape)
                .overlay(shape.stroke(Theme.hairline, lineWidth: 0.5))
        }
    }

    /// 圆形玻璃（悬浮搜索等）
    @ViewBuilder
    func glassCircle() -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: .circle)
        } else {
            self.background(.regular.material, in: Circle())
                .shadow(color: Color.black.opacity(0.12), radius: 10, y: 4)
        }
    }

    /// 强调按钮（红色主按钮）
    @ViewBuilder
    func prominentGlassButton() -> some View {
        if #available(iOS 26.0, *) {
            self.buttonStyle(.glassProminent)
        } else {
            self.buttonStyle(.borderedProminent)
        }
    }

    /// 普通玻璃按钮
    @ViewBuilder
    func plainGlassButton() -> some View {
        if #available(iOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered)
        }
    }

    /// 底部标签栏随滚动收缩（iOS 26）
    @ViewBuilder
    func minimizeTabBarOnScroll() -> some View {
        if #available(iOS 26.0, *) {
            self.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            self
        }
    }
}

// MARK: - 占位封面（推荐位无网络图时用，颜色由书名稳定哈希决定）

struct PlaceholderCover: View {
    let title: String

    private var palette: [Color] {
        let presets: [[Color]] = [
            [Color(red: 0.98, green: 0.80, blue: 0.44), Color(red: 0.93, green: 0.55, blue: 0.30)],
            [Color(red: 0.55, green: 0.75, blue: 0.95), Color(red: 0.35, green: 0.52, blue: 0.85)],
            [Color(red: 0.60, green: 0.85, blue: 0.70), Color(red: 0.28, green: 0.62, blue: 0.52)],
            [Color(red: 0.85, green: 0.62, blue: 0.90), Color(red: 0.55, green: 0.38, blue: 0.80)],
            [Color(red: 0.95, green: 0.55, blue: 0.55), Color(red: 0.80, green: 0.25, blue: 0.35)],
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

/// 封面视图：有 url 走网络加载，否则用占位
struct SmartCover: View {
    let url: String
    let title: String
    var headers: [String: String] = [:]

    var body: some View {
        Group {
            if url.isEmpty {
                PlaceholderCover(title: title)
            } else {
                CoverImageView(url: url, headers: headers)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - 章节进度条（红色小进度条）

struct MiniProgressBar: View {
    let progress: Double    // 0...1

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
