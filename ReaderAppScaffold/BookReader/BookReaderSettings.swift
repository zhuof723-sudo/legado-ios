import SwiftUI

struct BookReaderSettingsPage: View {
    @ObservedObject private var style = BookReaderStyle.shared

    var body: some View {
        Form {
            Section("翻页方式") {
                Picker("模式", selection: $style.turnMode) {
                    ForEach(BookReaderTurnMode.allCases) { mode in
                        Label(mode.title, systemImage: mode.icon)
                            .tag(mode.rawValue)
                    }
                }
                Text("滚动模式使用独立连续排版，不复用分页结果。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("字体") {
                Picker("字体", selection: $style.fontFamily) {
                    Text("无衬线").tag(0)
                    Text("衬线").tag(1)
                }

                Stepper(value: $style.fontSize, in: 12...32, step: 1) {
                    settingValueRow("字号", value: "\(Int(style.fontSize))")
                }

                Toggle("加粗", isOn: $style.bold)

                Stepper(value: $style.paragraphIndent, in: 0...4, step: 1) {
                    settingValueRow("首行缩进", value: "\(style.paragraphIndent) 字")
                }
            }

            Section("文字间距") {
                percentageSlider(
                    title: "行距",
                    value: $style.lineSpacingPercent,
                    range: 0...100
                )
                percentageSlider(
                    title: "段距",
                    value: $style.paragraphSpacingPercent,
                    range: 0...100
                )
                percentageSlider(
                    title: "标题间距",
                    value: $style.titleSpacingPercent,
                    range: 0...100
                )
            }

            Section("页面边距") {
                percentageSlider(
                    title: "左右边距",
                    value: $style.paddingHorizontalPercent,
                    range: 4...35
                )
                percentageSlider(
                    title: "上边距",
                    value: $style.paddingTopPercent,
                    range: 4...40
                )
                percentageSlider(
                    title: "下边距",
                    value: $style.paddingBottomPercent,
                    range: 4...35
                )

                Text("百分比会随屏幕尺寸换算为实际边距，在不同机型上保持一致的版心比例。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("主题") {
                Picker("主题", selection: $style.themeID) {
                    ForEach(BookReaderTheme.all) { theme in
                        Text(theme.name).tag(theme.id)
                    }
                }
                Toggle("夜间模式", isOn: $style.nightMode)
            }

            Section {
                Button("恢复默认排版") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        restoreDefaults()
                    }
                }
                .frame(maxWidth: .infinity)
            } footer: {
                Text("默认排版：行距 35%、段距 40%、标题间距 45%、左右边距 22%、上边距 30%、下边距 20%。")
            }
        }
        .navigationTitle("阅读设置")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .background(style.theme.background.ignoresSafeArea())
    }

    private func settingValueRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    private func percentageSlider(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            settingValueRow(title, value: "\(Int(value.wrappedValue.rounded()))%")
            Slider(value: value, in: range, step: 1)
                .tint(.accentColor)
        }
        .padding(.vertical, 2)
    }

    private func restoreDefaults() {
        style.lineSpacingPercent = BookReaderDefaults.lineSpacingPercent
        style.paragraphSpacingPercent = BookReaderDefaults.paragraphSpacingPercent
        style.titleSpacingPercent = BookReaderDefaults.titleSpacingPercent
        style.paddingHorizontalPercent = BookReaderDefaults.paddingHorizontalPercent
        style.paddingTopPercent = BookReaderDefaults.paddingTopPercent
        style.paddingBottomPercent = BookReaderDefaults.paddingBottomPercent
        style.paragraphIndent = 2
    }
}
