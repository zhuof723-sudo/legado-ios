import SwiftUI
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
    @State private var headerStatus: String?

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

                    if let headerStatus {
                        Text("已保存鉴权串: \(headerStatus)")
                            .font(.caption).foregroundStyle(.secondary)
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
    }

    private func saveValues() {
        record.writeLoginInfo(formValues)
        try? context.save()
        message = "已保存"
        messageColor = .green
    }

    private func runAction(_ item: LoginUIItem) {
        let action = item.action ?? ""
        // 提取函数名 "login()" → "login"
        let funcName = action.replacingOccurrences(of: "()", with: "")
        guard !funcName.isEmpty else {
            message = "该按钮没有可执行的动作"
            messageColor = .orange
            return
        }
        isRunning = true
        message = nil
        Task {
            do {
                let runtime = try makeRuntime()
                let result = try await runtime.executeLoginAction(funcName, infoMap: formValues)
                record.writeLoginInfo(formValues)
                if let header = record.decodeSource()?.loginHeader {
                    headerStatus = String(header.prefix(20)) + (header.count > 20 ? "..." : "")
                }
                await MainActor.run {
                    message = result ?? "已执行 \(funcName)"
                    messageColor = .green
                    isRunning = false
                }
            } catch {
                await MainActor.run {
                    message = "执行失败：\(error.localizedDescription)"
                    messageColor = .red
                    isRunning = false
                }
            }
        }
    }

    private func makeRuntime() throws -> BookSourceRuntime {
        guard let src = record.decodeSource() else {
            throw NSError(domain: "login", code: 1, userInfo: [NSLocalizedDescriptionKey: "书源解析失败"])
        }
        let runtime = BookSourceRuntime(src)
        let ctxImpl = SourceJSContextImpl(record: record)
        runtime.sourceContext = ctxImpl
        // 登录表单持久化
        runtime.loginInfoPersister = { [weak record] info in
            record?.writeLoginInfo(info)
        }
        runtime.loginActionHandler = { [weak record] action, info in
            record?.writeLoginInfo(info)
        }
        return runtime
    }
}