import SwiftUI

struct BookReaderSettingsPage: View {
    @ObservedObject private var style = BookReaderStyle.shared

    var body: some View {
        Form {
            Section("翻页方式") {
                Picker("模式", selection: $style.turnMode) {
                    ForEach(BookReaderTurnMode.allCases) { mode in
                        Label(mode.title, systemImage: mode.icon).tag(mode.rawValue)
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
                    HStack {
                        Text("字号")
                        Spacer()
                        Text("\(Int(style.fontSize))")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                Toggle("加粗", isOn: $style.bold)
            }

            Section("排版") {
                Stepper(value: $style.lineSpacing, in: 4...24, step: 1) {
                    HStack {
                        Text("行距")
                        Spacer()
                        Text("\(Int(style.lineSpacing))").foregroundStyle(.secondary)
                    }
                }
                Stepper(value: $style.paragraphSpacing, in: 0...32, step: 1) {
                    HStack {
                        Text("段距")
                        Spacer()
                        Text("\(Int(style.paragraphSpacing))").foregroundStyle(.secondary)
                    }
                }
                Stepper(value: $style.paragraphIndent, in: 0...4, step: 1) {
                    HStack {
                        Text("首行缩进")
                        Spacer()
                        Text("\(style.paragraphIndent) 字").foregroundStyle(.secondary)
                    }
                }
            }

            Section("边距") {
                Stepper(value: $style.paddingH, in: 12...56, step: 2) {
                    HStack { Text("左右边距"); Spacer(); Text("\(Int(style.paddingH))").foregroundStyle(.secondary) }
                }
                Stepper(value: $style.paddingTop, in: 20...90, step: 2) {
                    HStack { Text("上边距"); Spacer(); Text("\(Int(style.paddingTop))").foregroundStyle(.secondary) }
                }
                Stepper(value: $style.paddingBottom, in: 20...80, step: 2) {
                    HStack { Text("下边距"); Spacer(); Text("\(Int(style.paddingBottom))").foregroundStyle(.secondary) }
                }
            }

            Section("主题") {
                Picker("主题", selection: $style.themeID) {
                    ForEach(BookReaderTheme.all) { theme in Text(theme.name).tag(theme.id) }
                }
                Toggle("夜间模式", isOn: $style.nightMode)
            }
        }
        .navigationTitle("阅读设置")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .background(style.theme.background.ignoresSafeArea())
    }
}
