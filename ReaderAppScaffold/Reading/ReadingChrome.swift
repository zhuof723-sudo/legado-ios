import SwiftUI

// MARK: - 点击分区

enum TapZoneAction {
    case previousPage
    case nextPage
    case toggleControls
}

/// 左右翻页热区 + 中间唤出控制层。左右各 24%（至少 72pt）。
enum TapZones {
    static func classify(x: CGFloat, width: CGFloat) -> TapZoneAction {
        let edge = max(72, width * 0.24)
        if x <= edge { return .previousPage }
        if x >= width - edge { return .nextPage }
        return .toggleControls
    }
}

// MARK: - 圆形玻璃按钮

/// 控制层里的圆形玻璃按钮。`tint` 非空时用它着色（如书签已点亮 / TTS 播放中）。
struct ChromeButton: View {
    let icon: String
    var tint: Color? = nil
    var accent: Color
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint ?? accent)
                .frame(width: 36, height: 36)
                .glassCircle()
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 顶部控制条（返回 · 书名 · 搜索 / 书签）

/// 顶栏：左返回，中间书名（点按直接开目录），右侧搜索与书签。
struct ReadingTopBar: View {
    let title: String
    let accent: Color
    let isBookmarked: Bool
    /// PDF 等无全文搜索的阅读器可隐藏搜索按钮
    var showSearch = true
    var onBack: () -> Void
    var onTitle: () -> Void
    var onSearch: () -> Void
    var onBookmark: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            ChromeButton(icon: "chevron.left", accent: accent, action: onBack)
            Button(action: onTitle) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(accent)
                    .lineLimit(1)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            Spacer(minLength: 6)
            if showSearch {
                ChromeButton(icon: "magnifyingglass", accent: accent, action: onSearch)
            }
            ChromeButton(
                icon: isBookmarked ? "bookmark.fill" : "bookmark",
                tint: isBookmarked ? Theme.accent : nil,
                accent: accent,
                action: onBookmark
            )
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .glassCard(RoundedRectangle(cornerRadius: 20), interactive: true)
        .shadow(color: .black.opacity(0.10), radius: 12, y: 4)
    }
}

// MARK: - 底部控制条（目录 · 页码 · 朗读 / 排版）

/// 底栏：左侧目录，中间页码，右侧朗读与排版。
struct ReadingBottomBar: View {
    let pageText: String
    let accent: Color
    var isSpeaking = false
    var onContents: () -> Void
    var onTts: () -> Void
    var onAppearance: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            ChromeButton(icon: "list.bullet", accent: accent, action: onContents)
            Spacer(minLength: 6)
            Text(pageText)
                .font(.footnote.weight(.medium))
                .foregroundStyle(accent)
                .lineLimit(1)
            Spacer(minLength: 6)
            ChromeButton(
                icon: isSpeaking ? "headphones.circle.fill" : "headphones",
                tint: isSpeaking ? Theme.accent : nil,
                accent: accent,
                action: onTts
            )
            ChromeButton(icon: "textformat.size", accent: accent, action: onAppearance)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .glassCard(RoundedRectangle(cornerRadius: 20), interactive: true)
        .shadow(color: .black.opacity(0.10), radius: 12, y: 4)
    }
}

// MARK: - 全书进度细线

/// 贴底的一条细进度线：始终可见、不挡内容、不拦截触摸。
/// progress 为全书进度 0...1，由调用方按"章序号 + 页内占比"折算。
struct ProgressHairline: View {
    let progress: Double
    var accent: Color = Theme.accent

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                accent.opacity(0.15)
                accent.opacity(0.9)
                    .frame(width: max(2, geo.size.width * min(max(progress, 0), 1)))
            }
        }
        .frame(height: 2)
        .allowsHitTesting(false)
    }
}
