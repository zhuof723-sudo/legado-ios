import SwiftUI

/// 阅读设置独立页（设置页入口用）。
struct ReadingSettingsPage: View {
    var body: some View {
        AppearancePanel()
            .navigationTitle("阅读设置")
            .navigationBarTitleDisplayMode(.inline)
    }
}
