import SwiftUI
import UIKit

// MARK: - 行距预设（Apple Books Aa 面板三档）

enum ReaderLineSpacingPreset: Int, CaseIterable, Identifiable {
    case compact = 0
    case standard = 1
    case relaxed = 2

    var id: Int { rawValue }
    var name: String { ["紧凑", "标准", "宽松"][rawValue] }
    /// 映射到 ReaderConfig.lineSpacing（pt）
    var lineSpacing: Double { [6, 12, 20][rawValue] }
    /// 从当前行距值反查最近档位，用于面板选中态。
    static func nearest(to value: Double) -> ReaderLineSpacingPreset {
        allCases.min { abs($0.lineSpacing - value) < abs($1.lineSpacing - value) } ?? .standard
    }
}

// MARK: - Aa 排版面板

/// Apple Books 式 Aa 面板：字体（衬线/无衬线）、字号、行距、主题、亮度、
/// 翻页动画与常用开关，全部集中在一张紧凑面板里。
struct ReaderAaPanel: View {
    @ObservedObject private var config = ReaderConfig.shared
    @AppStorage("reader.autoRead") private var autoRead = false
    @Environment(\.dismiss) private var dismiss

    private var brightnessBinding: Binding<Double> {
        Binding(
            get: { Double(UIScreen.main.brightness) },
            set: { UIScreen.main.brightness = CGFloat($0) }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    Text("排版").font(.title3.bold())
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }

                // MARK: - 字体
                VStack(alignment: .leading, spacing: 10) {
                    Text("字体").font(.subheadline.bold())
                    HStack(spacing: 10) {
                        fontOption(.sans)
                        fontOption(.serif)
                    }
                }

                // MARK: - 字号
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("字号").font(.subheadline.bold())
                        Spacer()
                        Text("\(Int(config.fontSize))").font(.caption.bold()).foregroundStyle(Theme.accent)
                    }
                    HStack(spacing: 14) {
                        Text("A").font(.system(size: 13, weight: .medium))
                        Slider(value: $config.fontSize, in: 12...32, step: 1).tint(Theme.accent)
                        Text("A").font(.system(size: 24, weight: .medium))
                    }
                }

                // MARK: - 行距
                VStack(alignment: .leading, spacing: 10) {
                    Text("行距").font(.subheadline.bold())
                    HStack(spacing: 10) {
                        ForEach(ReaderLineSpacingPreset.allCases) { preset in
                            presetOption(preset)
                        }
                    }
                }

                // MARK: - 主题
                VStack(alignment: .leading, spacing: 10) {
                    Text("主题").font(.subheadline.bold())
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            ForEach(ReaderTheme.themes) { theme in
                                themeOption(theme)
                            }
                            Spacer()
                        }
                    }
                }

                // MARK: - 亮度
                VStack(alignment: .leading, spacing: 10) {
                    Text("亮度").font(.subheadline.bold())
                    HStack(spacing: 12) {
                        Image(systemName: "sun.min").font(.caption).foregroundStyle(.secondary)
                        Slider(value: brightnessBinding, in: 0.05...1).tint(Theme.accent)
                        Image(systemName: "sun.max.fill").font(.caption).foregroundStyle(.secondary)
                    }
                }

                // MARK: - 翻页动画
                VStack(alignment: .leading, spacing: 10) {
                    Text("翻页动画").font(.subheadline.bold())
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(PageTurnStyle.allCases) { anim in
                                animOption(anim)
                            }
                        }
                    }
                }

                // MARK: - 更多
                VStack(alignment: .leading, spacing: 8) {
                    Text("更多").font(.subheadline.bold())
                    toggleRow("加粗字体", icon: "bold", isOn: $config.bold)
                    toggleRow("夜间模式", icon: "moon", isOn: $config.nightMode)
                    toggleRow("自动阅读", icon: "play.circle", isOn: $autoRead)
                }
            }
            .padding(20)
            .padding(.bottom, 24)
        }
        .background(Theme.bg.ignoresSafeArea())
    }

    // MARK: - 组件

    private func fontOption(_ family: ReaderConfig.ReaderFontFamily) -> some View {
        let isActive = config.currentFontFamily == family
        return Button {
            config.fontFamily = family.rawValue
        } label: {
            VStack(spacing: 4) {
                Text("Aa")
                    .font(.system(size: 18, weight: .medium, design: family == .serif ? .serif : .default))
                Text(family.shortName)
                    .font(.caption2)
            }
            .foregroundStyle(isActive ? Theme.accent : .primary.opacity(0.6))
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .glassCard(RoundedRectangle(cornerRadius: 12), interactive: true)
        }
        .buttonStyle(.plain)
    }

    private func presetOption(_ preset: ReaderLineSpacingPreset) -> some View {
        let isActive = ReaderLineSpacingPreset.nearest(to: config.lineSpacing) == preset
        return Button {
            config.lineSpacing = preset.lineSpacing
        } label: {
            Text(preset.name)
                .font(.caption)
                .foregroundStyle(isActive ? Theme.accent : .primary.opacity(0.7))
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .glassCard(Capsule(), interactive: true)
        }
        .buttonStyle(.plain)
    }

    private func themeOption(_ theme: ReaderTheme) -> some View {
        let isActive = config.themeId == theme.id && !config.nightMode
        return Button {
            config.nightMode = false
            config.themeId = theme.id
        } label: {
            ZStack {
                Circle()
                    .fill(theme.background)
                    .frame(width: 40, height: 40)
                    .overlay(
                        Circle().stroke(isActive ? Theme.accent : Theme.hairline,
                                        lineWidth: isActive ? 2.5 : 0.5)
                    )
                if isActive {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.accent)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func animOption(_ anim: PageTurnStyle) -> some View {
        let isActive = config.turnStyle == anim.rawValue
        return Button { config.turnStyle = anim.rawValue } label: {
            VStack(spacing: 4) {
                Image(systemName: anim.icon)
                    .font(.system(size: 16, weight: .medium))
                Text(anim.name)
                    .font(.caption2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(isActive ? Theme.accent : .primary.opacity(0.6))
            .frame(width: 64, height: 50)
            .glassCard(RoundedRectangle(cornerRadius: 10), interactive: true)
        }
        .buttonStyle(.plain)
    }

    private func toggleRow(_ title: String, icon: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Label(title, systemImage: icon)
                .font(.subheadline)
                .foregroundStyle(.primary.opacity(0.85))
            Spacer()
            Toggle("", isOn: isOn).labelsHidden().tint(Theme.accent)
        }
        .padding(.vertical, 4)
    }
}