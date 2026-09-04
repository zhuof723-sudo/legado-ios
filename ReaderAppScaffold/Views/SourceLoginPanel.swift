import SwiftUI
import SwiftData
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
    @State private var runningAction: String?
    @State private var hasLoginHeader = false
    @State private var browserDestination: BrowserDestination?
    @State private var toastMessage: String?
    @State private var toastGeneration = 0

    /// loginUi 是 JSON 数组字符串：[{"name":"...","type":"text|password|button","action":"..."}]
    private struct LoginUIItem: Identifiable, Decodable {
        let name: String
        let type: String
        let action: String?
        var id: String { name }

        var normalizedAction: String {
            (action ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private enum LoginRow: Identifiable {
        case field(LoginUIItem)
        case buttons(LoginUIItem, LoginUIItem?)
        case section(String)

        var id: String {
            switch self {
            case .field(let item): return "field-\(item.id)"
            case .buttons(let first, let second): return "buttons-\(first.id)-\(second?.id ?? "")"
            case .section(let title): return "section-\(title)"
            }
        }
    }

    private var uiItems: [LoginUIItem] {
        guard let json = record.decodeSource()?.loginUi, !json.isEmpty,
              let data = json.data(using: .utf8),
              let arr = try? JSONDecoder().decode([LoginUIItem].self, from: data) else {
            return []
        }
        return arr
    }

    private var rows: [LoginRow] {
        var result: [LoginRow] = []
        var pendingButton: LoginUIItem?

        func flushButton() {
            if let pendingButton {
                result.append(.buttons(pendingButton, nil))
            }
            pendingButton = nil
        }

        for item in uiItems {
            if item.type != "button" {
                flushButton()
                result.append(.field(item))
            } else if item.normalizedAction.isEmpty {
                flushButton()
                result.append(.section(item.name))
            } else if let first = pendingButton {
                result.append(.buttons(first, item))
                pendingButton = nil
            } else {
                pendingButton = item
            }
        }
        flushButton()
        return result
    }

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar

                ScrollView {
                    LazyVStack(spacing: 14) {
                        ForEach(rows) { row in
                            switch row {
                            case .field(let item):
                                inputField(item)
                            case .buttons(let first, let second):
                                HStack(spacing: 14) {
                                    actionButton(first)
                                    if let second {
                                        actionButton(second)
                                    } else {
                                        Color.clear.frame(maxWidth: .infinity, minHeight: 58)
                                    }
                                }
                            case .section(let title):
                                Text(title.replacingOccurrences(of: "↓", with: ""))
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.top, 8)
                                    .padding(.horizontal, 4)
                            }
                        }

                        if hasLoginHeader {
                            Label("登录凭据已保存", systemImage: "checkmark.shield.fill")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.green)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14)
                                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
                        }

                        if let message {
                            Text(message)
                                .font(.footnote)
                                .foregroundStyle(messageColor)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14)
                                .background(messageColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 18)
                    .padding(.bottom, 24)
                }
                .scrollDismissesKeyboard(.interactively)
            }

            if let toastMessage {
                toastOverlay(toastMessage)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 128)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .zIndex(100)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: toastMessage)
        .onAppear { loadValues() }
        .fullScreenCover(item: $browserDestination) { destination in
            InAppBrowserView(destination: destination)
        }
    }

    private func toastOverlay(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .regular))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 15)
            .padding(.vertical, 10)
            .frame(maxWidth: 290)
            .background(Color.black.opacity(0.80), in: RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
            .padding(.horizontal, 28)
            .contentShape(Rectangle())
            .onTapGesture { dismissToast() }
    }

    @MainActor
    private func showToast(_ text: String) {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        toastGeneration += 1
        let generation = toastGeneration
        toastMessage = cleaned
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            guard toastGeneration == generation else { return }
            dismissToast()
        }
    }

    @MainActor
    private func dismissToast() {
        toastGeneration += 1
        toastMessage = nil
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button("关闭") { dismiss() }
                .font(.headline)
                .foregroundStyle(.primary)
                .padding(.horizontal, 18)
                .frame(height: 52)
                .background(.thinMaterial, in: Capsule())

            Text("登录 - \(record.bookSourceName)")
                .font(.title3.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            Spacer(minLength: 4)

            HStack(spacing: 4) {
                Menu {
                    Button("读取已保存信息", systemImage: "arrow.clockwise") { loadValues() }
                    Button("清空输入", systemImage: "eraser") { formValues.removeAll() }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title2)
                        .frame(width: 44, height: 48)
                }

                Button("确认") { confirmLogin() }
                    .font(.headline)
                    .frame(height: 48)
                    .disabled(isRunning)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .background(.thinMaterial, in: Capsule())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func inputField(_ item: LoginUIItem) -> some View {
        let binding = Binding(
            get: { formValues[item.name] ?? "" },
            set: { formValues[item.name] = $0 }
        )
        Group {
            if item.type == "password" {
                SecureField(item.name, text: binding)
            } else {
                TextField(item.name, text: binding)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        }
        .font(.body)
        .padding(.horizontal, 16)
        .frame(height: 58)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func actionButton(_ item: LoginUIItem) -> some View {
        Button {
            runAction(item)
        } label: {
            HStack(spacing: 8) {
                if runningAction == item.id {
                    ProgressView().controlSize(.small)
                }
                Text(item.name)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .foregroundStyle(Color.blue)
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.7), lineWidth: 0.7))
        }
        .buttonStyle(.plain)
        .disabled(isRunning)
    }

    private func loadValues() {
        let info = record.decodeSource()?.loginInfoMap ?? [:]
        for (k, v) in info { formValues[k] = v }
        hasLoginHeader = !(record.loginHeader?.isEmpty ?? true)
    }

    private func saveValues() {
        record.writeLoginInfo(formValues)
        try? context.save()
        showToast("已保存")
    }

    private func confirmLogin() {
        if let loginItem = uiItems.first(where: {
            let action = $0.normalizedAction.lowercased()
            return action == "login()" || action == "login" || $0.name.contains("账号登录")
        }) {
            runAction(loginItem)
        } else {
            saveValues()
        }
    }

    private func runAction(_ item: LoginUIItem) {
        let action = (item.action ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !action.isEmpty else {
            message = "该按钮没有可执行的动作"
            messageColor = .orange
            return
        }
        isRunning = true
        runningAction = item.id
        message = nil
        record.writeLoginInfo(formValues)
        try? context.save()
        Task {
            do {
                let runtime = try makeRuntime()
                let result = try await runtime.executeLoginAction(action, infoMap: formValues)
                record.writeLoginInfo(formValues)
                try? context.save()
                if let header = record.loginHeader, !header.isEmpty {
                    hasLoginHeader = true
                }
                await MainActor.run {
                    message = result.flatMap { $0.isEmpty ? nil : $0 } ?? "已执行 \(action)"
                    messageColor = .green
                    runningAction = nil
                    isRunning = false
                }
            } catch {
                await MainActor.run {
                    message = "执行失败：\(error.localizedDescription)"
                    messageColor = .red
                    runningAction = nil
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
        runtime.loginInfoPersister = { [weak record] info in
            record?.writeLoginInfo(info)
        }
        runtime.loginActionHandler = { [weak record] _, info in
            record?.writeLoginInfo(info)
        }
        runtime.toastHandler = { text in
            Task { @MainActor in
                showToast(text)
            }
        }
        runtime.browserOpener = { urlString, title in
            Task { @MainActor in
                browserDestination = BrowserDestination(urlString: urlString, title: title)
            }
        }
        return runtime
    }
}