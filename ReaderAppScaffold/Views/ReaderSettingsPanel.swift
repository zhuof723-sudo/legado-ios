import SwiftUI

/// 阅读设置面板（对齐 legado-E：翻页动画 / 主题 / 字体 / 排版 / 边距）
struct ReaderSettingsPanel: View {
    @StateObject private var config = ReaderConfig.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("排版设置").font(.title3.bold())

                // MARK: - 翻页动画
                Group {
                    sectionLabel("翻页动画")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(PageAnimationType.allCases) { anim in
                                animOption(anim)
                            }
                        }
                    }
                }

                // MARK: - 阅读主题
                Group {
                    sectionLabel("阅读主题")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            ForEach(ReaderTheme.themes) { theme in
                                themeOption(theme)
                            }
                            Spacer()
                        }
                    }
                }

                // MARK: - 字体
                Group {
                    sectionLabel("字体")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(ReaderFont.allCases) { font in
                                fontOption(font)
                            }
                        }
                    }
                }

                // MARK: - 字号
                Group {
                    HStack {
                        sectionLabel("字号")
                        Spacer()
                        Text("\(Int(config.fontSize))").font(.caption.bold()).foregroundStyle(Theme.accent)
                    }
                    HStack(spacing: 12) {
                        Button { config.fontSize = max(12, config.fontSize - 1) } label: { Text("A-").font(.footnote.bold()) }
                            .frame(width: 40, height: 32)
                            .background(Capsule().fill(Color(.secondarySystemBackground)))
                        Slider(value: $config.fontSize, in: 12...32, step: 1).tint(Theme.accent)
                        Button { config.fontSize = min(32, config.fontSize + 1) } label: { Text("A+").font(.footnote.bold()) }
                            .frame(width: 40, height: 32)
                            .background(Capsule().fill(Color(.secondarySystemBackground)))
                    }
                }

                // MARK: - 行距 / 段距
                Group {
                    sectionLabel("行距 / 段距")
                    VStack(spacing: 12) {
                        sliderRow("行距", value: $config.lineSpacing, range: 0...24, step: 1, unit: "pt")
                        sliderRow("段距", value: $config.paragraphSpacing, range: 0...32, step: 1, unit: "pt")
                        sliderRow("字间距", value: $config.letterSpacing, range: 0...4, step: 0.5, unit: "pt")
                    }
                }

                // MARK: - 段落缩进 / 对齐
                Group {
                    sectionLabel("段落缩进 / 对齐")
                    HStack(spacing: 10) {
                        indentOption(0, label: "不缩进")
                        indentOption(1, label: "1字符")
                        indentOption(2, label: "2字符")
                        Spacer()
                    }
                    Picker("", selection: $config.textAlignment) {
                        Text("两端对齐").tag(0)
                        Text("左对齐").tag(1)
                        Text("居中").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .tint(Theme.accent)
                }

                // MARK: - 边距
                Group {
                    sectionLabel("页面边距")
                    VStack(spacing: 12) {
                        sliderRow("左右边距", value: Binding(
                            get: { config.paddingLeft },
                            set: { config.paddingLeft = $0; config.paddingRight = $0 }
                        ), range: 8...40, step: 1, unit: "pt")
                        sliderRow("上边距", value: $config.paddingTop, range: 20...80, step: 1, unit: "pt")
                        sliderRow("下边距", value: $config.paddingBottom, range: 20...80, step: 1, unit: "pt")
                    }
                }

                // MARK: - 更多设置
                Group {
                    sectionLabel("更多设置")
                    toggleRow("加粗字体", icon: "bold", isOn: $config.bold)
                    toggleRow("夜间模式", icon: "moon", isOn: $config.nightMode)
                    toggleRow("护眼模式", icon: "eye", isOn: $config.eyeCare)
                    toggleRow("自动阅读", icon: "play.circle", isOn: Binding(
                        get: { UserDefaults.standard.bool(forKey: "reader.autoRead") },
                        set: { UserDefaults.standard.set($0, forKey: "reader.autoRead") }
                    ))
                }
            }
            .padding(20)
            .padding(.bottom, 24)
        }
        .background(Theme.bg.ignoresSafeArea())
    }

    // MARK: - 组件

    private func sectionLabel(_ text: String) -> some View {
        Text(text).font(.subheadline.bold())
    }

    private func animOption(_ anim: PageAnimationType) -> some View {
        let isActive = config.pageAnim == anim.rawValue
        return Button { config.pageAnim = anim.rawValue } label: {
            VStack(spacing: 4) {
                Image(systemName: anim.icon)
                    .font(.system(size: 16, weight: .medium))
                Text(anim.name).font(.caption2)
            }
            .foregroundStyle(isActive ? Theme.accent : .primary.opacity(0.6))
            .frame(width: 56, height: 50)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isActive ? Theme.accent.opacity(0.12) : Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isActive ? Theme.accent.opacity(0.4) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func themeOption(_ theme: ReaderTheme) -> some View {
        let isActive = config.themeId == theme.id && !config.nightMode
        return Button { config.nightMode = false; config.themeId = theme.id } label: {
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

    private func fontOption(_ font: ReaderFont) -> some View {
        let isActive = config.fontName == font.rawValue
        return Button { config.fontName = font.rawValue } label: {
            Text("字")
                .font(font.swiftUIFont(size: 18, bold: false))
                .foregroundStyle(isActive ? Theme.accent : .primary.opacity(0.7))
                .frame(width: 48, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isActive ? Theme.accent.opacity(0.12) : Color(.secondarySystemBackground))
                )
        }
        .buttonStyle(.plain)
    }

    private func indentOption(_ indent: Int, label: String) -> some View {
        let isActive = config.paragraphIndent == indent
        return Button { config.paragraphIndent = indent } label: {
            Text(label)
                .font(.caption)
                .foregroundStyle(isActive ? Theme.accent : .primary.opacity(0.7))
                .frame(width: 64, height: 32)
                .background(
                    Capsule().fill(isActive ? Theme.accent.opacity(0.12) : Color(.secondarySystemBackground))
                )
        }
        .buttonStyle(.plain)
    }

    private func sliderRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, unit: String) -> some View {
        HStack(spacing: 12) {
            Text(title).font(.caption).foregroundStyle(.primary.opacity(0.7)).frame(width: 60, alignment: .leading)
            Slider(value: value, in: range, step: step).tint(Theme.accent)
            Text("\(Int(value.wrappedValue))\(unit)").font(.caption2).foregroundStyle(Theme.accent).frame(width: 44, alignment: .trailing)
        }
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

/// 阅读设置独立页（设置 → 阅读设置 复用同一份控件）
struct ReaderSettingsPage: View {
    var body: some View {
        ReaderSettingsPanel()
            .navigationTitle("阅读设置")
            .navigationBarTitleDisplayMode(.inline)
    }
}
