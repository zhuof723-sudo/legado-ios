import SwiftUI

/// 阅读设置面板（对照设计稿：翻页方式 / 背景颜色 / 字体大小 / 行距 / 更多设置）
struct ReaderSettingsPanel: View {
    @AppStorage("reader.fontSize") private var fontSize: Double = 18
    @AppStorage("reader.lineSpacingIndex") private var lineSpacingIndex: Int = 1
    @AppStorage("reader.bgIndex") private var bgIndex: Int = 1
    @AppStorage("reader.nightMode") private var nightMode = false
    @AppStorage("reader.eyeCare") private var eyeCare = false
    @AppStorage("reader.autoRead") private var autoRead = false
    @AppStorage("reader.turnMode") private var turnMode: Int = 2

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("设置").font(.title3.bold())

                Group {
                    sectionLabel("翻页方式")
                    Picker("", selection: $turnMode) {
                        Text("覆盖").tag(0)
                        Text("仿真").tag(1)
                        Text("滑动").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .tint(Theme.accent)
                }

                Group {
                    sectionLabel("背景颜色")
                    HStack(spacing: 18) {
                        ForEach(0..<5, id: \.self) { i in
                            Button {
                                if i == 4 { nightMode = true } else { nightMode = false; bgIndex = i }
                            } label: {
                                Circle()
                                    .fill(Theme.readerBackgrounds[i])
                                    .frame(width: 38, height: 38)
                                    .overlay(
                                        Circle().stroke(
                                            isActive(i) ? Theme.accent : Theme.hairline,
                                            lineWidth: isActive(i) ? 2.5 : 0.5
                                        )
                                    )
                                    .overlay(alignment: .topTrailing) {
                                        if isActive(i) {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 9, weight: .bold))
                                                .foregroundStyle(.white)
                                                .padding(3)
                                                .background(Circle().fill(Theme.accent))
                                                .offset(x: 3, y: -3)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer()
                    }
                }

                Group {
                    HStack {
                        sectionLabel("字体大小")
                        Spacer()
                        Text("\(Int(fontSize))").font(.caption.bold()).foregroundStyle(Theme.accent)
                    }
                    HStack(spacing: 12) {
                        Button { fontSize = max(12, fontSize - 1) } label: { Text("A-").font(.footnote.bold()) }
                            .frame(width: 40, height: 32)
                            .background(Capsule().fill(Color(.secondarySystemBackground)))
                        Slider(value: $fontSize, in: 12...32, step: 1).tint(Theme.accent)
                        Button { fontSize = min(32, fontSize + 1) } label: { Text("A+").font(.footnote.bold()) }
                            .frame(width: 40, height: 32)
                            .background(Capsule().fill(Color(.secondarySystemBackground)))
                    }
                }

                Group {
                    sectionLabel("行距")
                    HStack(spacing: 12) {
                        spacingOption(0, icon: "text.alignleft")
                        spacingOption(1, icon: "text.justify.left")
                        spacingOption(2, icon: "text.justify")
                        Spacer()
                    }
                }

                Group {
                    sectionLabel("更多设置")
                    toggleRow("夜间模式", icon: "moon", isOn: $nightMode)
                    toggleRow("护眼模式", icon: "eye", isOn: $eyeCare)
                    toggleRow("自动阅读", icon: "play.circle", isOn: $autoRead)
                }
            }
            .padding(20)
            .padding(.bottom, 24)
        }
        .background(Theme.bg.ignoresSafeArea())
    }

    private func isActive(_ index: Int) -> Bool {
        index == 4 ? nightMode : (!nightMode && bgIndex == index)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text).font(.subheadline.bold())
    }

    private func spacingOption(_ index: Int, icon: String) -> some View {
        Button { lineSpacingIndex = index } label: {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(lineSpacingIndex == index ? Theme.accent : .primary.opacity(0.6))
                .frame(width: 64, height: 34)
                .background(
                    Capsule().fill(lineSpacingIndex == index ? Theme.accent.opacity(0.12) : Color(.secondarySystemBackground))
                )
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

/// 阅读设置独立页（设置 → 阅读设置 复用同一份控件）
struct ReaderSettingsPage: View {
    var body: some View {
        ReaderSettingsPanel()
            .navigationTitle("阅读设置")
            .navigationBarTitleDisplayMode(.inline)
    }
}
