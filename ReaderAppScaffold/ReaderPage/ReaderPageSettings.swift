import SwiftUI
import UIKit

struct ReaderPageSettingsPage: View {
    @ObservedObject private var style = ReaderPageStyle.shared

    var body: some View {
        Form {
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
                        Text("\(Int(style.lineSpacing))")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                Stepper(value: $style.paragraphSpacing, in: 0...32, step: 1) {
                    HStack {
                        Text("段距")
                        Spacer()
                        Text("\(Int(style.paragraphSpacing))")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                Stepper(value: $style.paragraphIndent, in: 0...4, step: 1) {
                    HStack {
                        Text("首行缩进")
                        Spacer()
                        Text("\(style.paragraphIndent) 字")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("边距") {
                Stepper(value: $style.paddingH, in: 12...56, step: 2) {
                    HStack {
                        Text("左右边距")
                        Spacer()
                        Text("\(Int(style.paddingH))")
                            .foregroundStyle(.secondary)
                    }
                }
                Stepper(value: $style.paddingTop, in: 20...90, step: 2) {
                    HStack {
                        Text("上边距")
                        Spacer()
                        Text("\(Int(style.paddingTop))")
                            .foregroundStyle(.secondary)
                    }
                }
                Stepper(value: $style.paddingBottom, in: 20...80, step: 2) {
                    HStack {
                        Text("下边距")
                        Spacer()
                        Text("\(Int(style.paddingBottom))")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("主题") {
                Picker("主题", selection: $style.themeID) {
                    ForEach(ReaderPageTheme.all) { theme in
                        Text(theme.name).tag(theme.id)
                    }
                }
                Toggle("夜间模式", isOn: $style.nightMode)
            }

            Section {
                Text("正文固定使用仿真翻页。段评入口保留在正文角标上，点击角标打开段评。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("阅读设置")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .background(style.theme.background.ignoresSafeArea())
    }
}
