import SwiftUI
import UIKit
import AVFoundation

// MARK: - 语音合成控制器（在线/本地阅读共用）

@MainActor
final class ReaderSpeechController: ObservableObject {
    @Published private(set) var isSpeaking = false
    private let synthesizer = AVSpeechSynthesizer()

    func toggle(_ text: String) {
        if isSpeaking {
            stop()
        } else {
            speak(text)
        }
    }

    func speak(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
        isSpeaking = true
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
    }
}

// MARK: - 章内搜索（在线/本地阅读共用）

struct ReaderChapterSearchView: View {
    @Environment(\.dismiss) private var dismiss
    let text: String
    @State private var query = ""

    private var matches: [String] {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return [] }
        return text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.localizedCaseInsensitiveContains(keyword) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ContentUnavailableView("章内搜索", systemImage: "magnifyingglass",
                                           description: Text("输入关键字查找当前章节内容"))
                } else if matches.isEmpty {
                    ContentUnavailableView("没有找到结果", systemImage: "magnifyingglass",
                                           description: Text("当前章节不包含“\(query)”"))
                } else {
                    List(Array(matches.enumerated()), id: \.offset) { _, line in
                        Text(line).font(.body).textSelection(.enabled)
                    }
                    .listStyle(.plain)
                }
            }
            .searchable(text: $query, prompt: "搜索当前章节")
            .navigationTitle("章内搜索")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}
