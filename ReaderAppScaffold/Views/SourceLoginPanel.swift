import SwiftUI
import SwiftData
import UIKit
import LegadoRuleEngine

/// 书源登录面板：根据 source.loginUi 数组动态生成表单，
/// 按钮的 action 字段是书源 loginUrl 里的 JS 函数名（如 login()、key()），
/// 提交时通过 BookSourceRuntime 调用对应 JS 函数。
struct SourceLoginPanel: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let record: BookSourceRecord

    @State private var formValues: [String: String] = [:]
    @State private var message: String?
    @State private var messageColor: Color = .secondary
    @State private var isRunning = false
    @State private var hasLoginHeader = false

    /// loginUi 是 JSON 数组字符串：[{"name":"...","type":"text|password|button","action":"..."}]
    private struct LoginUIItem: Identifiable, Decodable {
        let name: String
        let type: String
        let action: String?
        var id: String { name }
    }

    private var uiItems: [LoginUIItem] {
        guard let json = record.decodeSource()?.loginUi, !json.isEmpty,
              let data = json.data(using: .utf8),
              let arr = try? JSONDecoder().decode([LoginUIItem].self, from: data) else {
            return []
        }
        return arr
    }

    private var inputs: [LoginUIItem] {
        uiItems.filter { $0.type != "button" && !$0.type.isEmpty }
    }

    private var buttons: [LoginUIItem] {
        uiItems.filter { $0.type == "button" }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(record.bookSourceName)
                        .font(.headline)
                    Text("登录面板 · 填写后点击按钮执行对应操作")
                        .font(.caption).foregroundStyle(.secondary)

                    ForEach(inputs) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.name).font(.caption.bold())
                            if item.type == "password" {
                                SecureField(item.name,
                                            text: Binding(
                                                get: { formValues[item.name] ?? "" },
                                                set: { formValues[item.name] = $0 }
                                            ))
                                .textFieldStyle(.roundedBorder)
                            } else {
                                TextField(item.name,
                                          text: Binding(
                                            get: { formValues[item.name] ?? "" },
                                            set: { formValues[item.name] = $0 }
                                          ))
                                .textFieldStyle(.roundedBorder)
                            }
                        }
                    }

                    HStack {
                        Button("💾 保存") { saveValues() }
                            .buttonStyle(.bordered)
                        Button("📋 读取") { loadValues() }
                            .buttonStyle(.bordered)
                    }

                    Divider()

                    ForEach(buttons) { item in
                        Button {
                            runAction(item)
                        } label: {
                            HStack {
                                if isRunning { ProgressView().controlSize(.small) }
                                Text(item.name).font(.subheadline.bold())
                                Spacer()
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.accent.opacity(0.12)))
                        }
                        .buttonStyle(.plain)
                        .disabled(isRunning)
                    }

                    if hasLoginHeader {
                        Label("登录凭据已保存", systemImage: "checkmark.shield.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }

                    if let message {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(messageColor)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 8).fill(messageColor.opacity(0.08)))
                    }
                }
                .padding(16)
            }
            .navigationTitle("登录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .onAppear { loadValues() }
    }

    private func loadValues() {
        let info = record.decodeSource()?.loginInfoMap ?? [:]
        for (k, v) in info { formValues[k] = v }
        hasLoginHeader = !(record.loginHeader?.isEmpty ?? true)
    }

    private func saveValues() {
        record.writeLoginInfo(formValues)
        try? context.save()
        message = "已保存"
        messageColor = .green
    }

    private func runAction(_ item: LoginUIItem) {
        let action = (item.action ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !action.isEmpty else {
            message = "该按钮没有可执行的动作"
            messageColor = .orange
            return
        }

        let rawJSON = record.rawJSON
        let sourceHeader = record.loginHeader
        let info = formValues
        isRunning = true
        message = nil
        record.writeLoginInfo(info)
        try? context.save()

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                guard var source = try BookSourceImporter.parse(rawJSON).first else {
                    throw NSError(domain: "login", code: 1,
                                  userInfo: [NSLocalizedDescriptionKey: "书源解析失败"])
                }
                source.loginInfoMap = info
                source.loginHeader = sourceHeader
                let runtime = BookSourceRuntime(source)
                let capture = LoginExecutionCapture()
                runtime.toastHandler = { capture.setToast($0) }
                runtime.browserOpener = { capture.setBrowserURL($0) }
                let result = try runtime.executeLoginAction(action, infoMap: info)
                let output = LoginExecutionOutput(
                    result: result,
                    toast: capture.toast,
                    browserURL: capture.browserURL,
                    loginInfo: runtime.source.loginInfoMap,
                    loginHeader: runtime.source.loginHeader
                )

                DispatchQueue.main.async {
                    record.writeLoginInfo(output.loginInfo)
                    record.writeLoginHeader(output.loginHeader)
                    try? context.save()
                    hasLoginHeader = !(output.loginHeader?.isEmpty ?? true)
                    if let urlString = output.browserURL, let url = URL(string: urlString) {
                        UIApplication.shared.open(url)
                    }
                    message = output.toast ?? output.result.flatMap { $0.isEmpty ? nil : $0 } ?? "已执行 \(action)"
                    messageColor = (message?.contains("❌") == true) ? .red : .green
                    isRunning = false
                }
            } catch {
                DispatchQueue.main.async {
                    message = "执行失败：\(error.localizedDescription)"
                    messageColor = .red
                    isRunning = false
                }
            }
        }
    }
}

private struct LoginExecutionOutput: Sendable {
    let result: String?
    let toast: String?
    let browserURL: String?
    let loginInfo: [String: String]
    let loginHeader: String?
}

private final class LoginExecutionCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var storedToast: String?
    private var storedBrowserURL: String?

    var toast: String? {
        lock.lock(); defer { lock.unlock() }
        return storedToast
    }

    var browserURL: String? {
        lock.lock(); defer { lock.unlock() }
        return storedBrowserURL
    }

    func setToast(_ value: String) {
        lock.lock(); defer { lock.unlock() }
        storedToast = value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func setBrowserURL(_ value: String) {
        lock.lock(); defer { lock.unlock() }
        storedBrowserURL = value
    }
}