import SwiftUI
import SwiftData
import LegadoRuleEngine

/// 设置页（对照设计稿：阅读 / 数据 / 通用 / 关于 分组）
struct SettingsView: View {
    @Query private var allSources: [BookSourceRecord]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("设置").font(.system(size: 30, weight: .bold))
                        .padding(.top, 6)

                    settingGroup {
                        navRow("阅读设置", icon: "book", destination: ReaderSettingsPage())
                        sheetRow("书源管理", icon: "tray.full", subtitle: "\(allSources.filter(\.enabled).count) 个已启用") {
                            SourceListSheet()
                        }
                        navRow("下载管理", icon: "arrow.down.circle", destination: DownloadStubPage())
                        navRow("数据备份", icon: "externaldrive", destination: BackupPage())
                    }

                    Text("通用").font(.footnote.bold()).foregroundStyle(.secondary)
                        .padding(.leading, 6)
                    settingGroup {
                        navRow("主题模式", icon: "circle.lefthalf.filled", destination: AppearancePage())
                        navRow("隐私设置", icon: "hand.raised", destination: PrivacyStubPage())
                        navRow("通知设置", icon: "bell", destination: NotificationStubPage())
                    }

                    Text("关于").font(.footnote.bold()).foregroundStyle(.secondary)
                        .padding(.leading, 6)
                    settingGroup {
                        navRow("关于我们", icon: "info.circle", detail: "1.0.0", destination: AboutPage())
                        navRow("意见反馈", icon: "envelope", destination: FeedbackPage())
                    }

                    Text("书源驱动的本地阅读器 · 学习交流用途")
                        .font(.caption2).foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 8)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 90)
            }
            .background(Theme.bg.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    // MARK: - 通用小组件

    private func settingGroup<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .background(RoundedRectangle(cornerRadius: 16).fill(Color.white))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.hairline, lineWidth: 0.5))
    }

    private func rowShell<Label: View, Trailing: View>(
        @ViewBuilder label: () -> Label,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 12) {
            label()
            Spacer()
            trailing()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.hairline).frame(height: 0.5).padding(.leading, 46)
        }
    }

    private func navRow<D: View>(_ title: String, icon: String, detail: String? = nil, destination: D) -> some View {
        NavigationLink {
            destination
        } label: {
            rowShell {
                Label {
                    Text(title).font(.subheadline)
                } icon: {
                    Image(systemName: icon)
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 22)
                }
            } trailing: {
                HStack(spacing: 5) {
                    if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    @State private var showSources = false

    private func sheetRow(_ title: String, icon: String, subtitle: String,
                          @ViewBuilder sheet: @escaping () -> some View) -> some View {
        Button {
            showSources = true
        } label: {
            rowShell {
                Label {
                    Text(title).font(.subheadline)
                } icon: {
                    Image(systemName: icon)
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 22)
                }
            } trailing: {
                HStack(spacing: 5) {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showSources) { sheet() }
    }
}

// MARK: - 书源管理弹层

struct SourceListSheet: View {
    var body: some View {
        BookSourceListView()
    }
}

// MARK: - 子页面

struct DownloadStubPage: View {
    var body: some View {
        ContentUnavailableView("离线缓存开发中", systemImage: "arrow.down.circle",
                               description: Text("后续支持整本缓存，无网也能读"))
            .navigationTitle("下载管理")
            .navigationBarTitleDisplayMode(.inline)
            .background(Theme.bg.ignoresSafeArea())
    }
}

struct AppearancePage: View {
    @AppStorage("app.appearance") private var appearance = 0   // 0跟随系统 1浅色 2深色

    var body: some View {
        List {
            Section("界面外观") {
                Picker("主题模式", selection: $appearance) {
                    Text("跟随系统").tag(0)
                    Text("浅色").tag(1)
                    Text("深色").tag(2)
                }
                .pickerStyle(.inline)
                .tint(Theme.accent)
            }
            Section {
                Text("阅读器背景不受主题模式影响，可在阅读时单独设置。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("主题模式")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct PrivacyStubPage: View {
    @AppStorage("app.privacy.history") private var keepHistory = true
    @AppStorage("app.privacy.cover") private var loadCovers = true

    var body: some View {
        List {
            Section {
                Toggle(isOn: $keepHistory) { Text("记录阅读历史") }
                Toggle(isOn: $loadCovers) { Text("加载网络封面") }
            } footer: {
                Text("所有数据仅保存在本机，应用不含任何数据上传。")
            }
            .tint(Theme.accent)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("隐私设置")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct NotificationStubPage: View {
    @AppStorage("app.notify.update") private var notifyUpdate = false

    var body: some View {
        List {
            Section {
                Toggle(isOn: $notifyUpdate) { Text("章节更新提醒") }
            } footer: {
                Text("提醒依赖书源的更新检查，当前版本尚未实现后台检查，开关仅作记录。")
            }
            .tint(Theme.accent)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("通知设置")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct BackupPage: View {
    @Environment(\.modelContext) private var context

    private struct BackupPayload: Codable {
        var exportedAt: Date
        var sources: [String]
        var shelf: [ShelfEntry]
    }
    private struct ShelfEntry: Codable {
        var bookUrl, sourceUrl, name, author, intro, coverUrl: String
        var lastReadChapterIndex: Int
    }

    private func makeJSON() -> String? {
        let records = (try? context.fetch(FetchDescriptor<BookSourceRecord>())) ?? []
        let books = (try? context.fetch(FetchDescriptor<ShelfBook>())) ?? []
        let payload = BackupPayload(
            exportedAt: Date(),
            sources: records.compactMap(\.rawJSON),
            shelf: books.map {
                .init(bookUrl: $0.bookUrl, sourceUrl: $0.sourceUrl, name: $0.name,
                      author: $0.author, intro: $0.intro, coverUrl: $0.coverUrl,
                      lastReadChapterIndex: $0.lastReadChapterIndex)
            }
        )
        guard let data = try? JSONEncoder().encode(payload) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    var body: some View {
        List {
            Section {
                if let json = makeJSON() {
                    ShareLink(item: json, subject: Text("legado-ios 备份")) {
                        Label("导出书源与书架 (JSON)", systemImage: "square.and.arrow.up")
                    }
                    .tint(Theme.accent)
                } else {
                    Label("生成备份失败", systemImage: "exclamationmark.triangle").foregroundStyle(.secondary)
                }
            } footer: {
                Text("书源 JSON 可随时再次导入；书架记录包含阅读进度。")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("数据备份")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct AboutPage: View {
    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "books.vertical.fill")
                .font(.system(size: 52))
                .foregroundStyle(Theme.accent)
                .frame(width: 104, height: 104)
                .background(RoundedRectangle(cornerRadius: 26).fill(Color.white))
                .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
            Text("Legado iOS").font(.title3.bold())
            Text("1.0.0 (Build 1)").font(.caption).foregroundStyle(.secondary)
            Text("书源规则引擎 Swift 移植 + SwiftUI 阅读器\n仅供学习交流，请尊重内容版权方")
                .font(.footnote).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("关于我们")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct FeedbackPage: View {
    var body: some View {
        List {
            Section {
                if let url = URL(string: "https://github.com/zhuof723-sudo/legado-ios/issues") {
                    Link(destination: url) {
                        Label("GitHub Issues", systemImage: "safari")
                    }
                    .tint(Theme.accent)
                }
            } header: {
                Text("反馈渠道")
            } footer: {
                Text("编译问题、书源兼容性、UI 建议都欢迎提交。")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("意见反馈")
        .navigationBarTitleDisplayMode(.inline)
    }
}
