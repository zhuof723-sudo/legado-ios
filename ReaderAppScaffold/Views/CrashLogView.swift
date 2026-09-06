import SwiftUI
import UIKit

struct CrashLogView: View {
    @State private var selected: CrashLogEntry?
    @State private var confirmClear = false

    private var entries: [CrashLogEntry] { CrashLogStore.shared.entries }

    var body: some View {
        List {
            if !entries.isEmpty {
                Section {
                    ForEach(entries) { entry in
                        Button {
                            selected = entry
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: icon(for: entry.kind))
                                    .font(.title3)
                                    .foregroundStyle(.red)
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(entry.title)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    Text(entry.kind + " · " + entry.timestamp.formatted(date: .abbreviated, time: .standard))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(summary(entry.details))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                                Spacer(minLength: 4)
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 5)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("本机记录")
                } footer: {
                    Text("MetricKit 的系统崩溃报告可能在崩溃后的下次或后续启动才送达。敏感凭据会自动脱敏。")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("崩溃日志")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    UIPasteboard.general.string = CrashReporter.shared.reportText()
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .disabled(entries.isEmpty)
                Button(role: .destructive) {
                    confirmClear = true
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(entries.isEmpty)
            }
        }
        .overlay {
            if entries.isEmpty {
                ContentUnavailableView(
                    "暂无崩溃日志",
                    systemImage: "checkmark.shield",
                    description: Text("若应用异常退出，重新打开后可在这里查看最近运行步骤和系统诊断。")
                )
            }
        }
        .onAppear { CrashLogStore.shared.reload() }
        .sheet(item: $selected) { entry in
            CrashLogDetailView(entry: entry)
        }
        .confirmationDialog("清除全部崩溃日志？", isPresented: $confirmClear) {
            Button("清除", role: .destructive) { CrashLogStore.shared.clear() }
            Button("取消", role: .cancel) {}
        }
    }

    private func icon(for kind: String) -> String {
        if kind.contains("MetricKit") { return "waveform.path.ecg.rectangle" }
        if kind.contains("SIG") { return "bolt.trianglebadge.exclamationmark.fill" }
        return "exclamationmark.triangle.fill"
    }

    private func summary(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
    }
}

private struct CrashLogDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let entry: CrashLogEntry

    private var report: String {
        """
        时间：\(entry.timestamp.formatted(date: .complete, time: .standard))
        类型：\(entry.kind)
        App：\(entry.appVersion)
        系统：\(entry.osVersion)

        \(entry.title)

        \(entry.details)
        """
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(report)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
            .navigationTitle("崩溃详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: report) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
    }
}
