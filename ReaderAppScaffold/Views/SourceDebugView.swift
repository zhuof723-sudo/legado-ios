import SwiftUI
import LegadoRuleEngine

/// 书源调试（对照 legado 原版 Debug.kt 的链路）：
/// 输入约定 —— 关键词=搜索；绝对URL=详情；++URL=目录；--URL=正文。
/// 搜索会自动串起「搜索 → 目录 → 正文」整条链，逐步打印每步结果，定位解析断在哪一环。
struct SourceDebugView: View {
    let record: BookSourceRecord
    @Environment(\.dismiss) private var dismiss

    @State private var key = ""
    @State private var running = false
    @State private var steps: [Step] = []

    struct Step: Identifiable {
        let id = UUID()
        let text: String
        let kind: Kind
        enum Kind { case header, info, item, error }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                inputBar
                if running { ProgressView("解析中…") }
                stepList
            }
            .navigationTitle("测试配置 · \(record.bookSourceName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { steps.removeAll() } label: { Image(systemName: "trash") }
                }
            }
        }
    }

    private var inputBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                TextField("关键词 / 详情URL / ++目录URL / --正文URL", text: $key)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                Button {
                    Task { await run() }
                } label: {
                    Text("开始").bold()
                }
                .prominentGlassButton()
                .tint(Theme.accent)
                .foregroundStyle(.white)
                .disabled(running)
            }
            HStack(spacing: 10) {
                quickButton("搜索", "斗破苍穹")
                quickButton("详情", "https://")
                quickButton("目录", "++")
                quickButton("正文", "--")
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private func quickButton(_ label: String, _ prefix: String) -> some View {
        Button {
            key = prefix
        } label: {
            Text(label).font(.caption)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(Color(.secondarySystemBackground)))
        }
        .buttonStyle(.plain)
    }

    private var stepList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(steps) { step in
                        Text(step.text)
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(step.kind == .error ? .red
                                             : step.kind == .header ? Theme.accent
                                             : step.kind == .item ? .secondary : .primary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(step.id)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))
            }
            .onChange(of: steps.count) {
                if let last = steps.last { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    // MARK: - 运行

    private func add(_ text: String, _ kind: Step.Kind = .info) {
        steps.append(Step(text: text, kind: kind))
    }

    private func run() async {
        running = true
        steps.removeAll()
        guard let source = record.decodeSource() else {
            add("书源配置解析失败（JSON 无效）", .error)
            running = false
            return
        }
        let runtime = BookSourceRuntime(source)
        let k = key.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            if k.hasPrefix("--") {
                await debugContent(runtime, source, url: String(k.dropFirst(2)).trimmingCharacters(in: .whitespaces))
            } else if k.hasPrefix("++") {
                await debugToc(runtime, source, url: String(k.dropFirst(2)).trimmingCharacters(in: .whitespaces))
            } else if isURL(k) {
                await debugDetail(runtime, source, url: k)
            } else {
                await debugSearch(runtime, source, keyword: k)
            }
        } catch {
            add("出错: \(error.localizedDescription)", .error)
        }
        running = false
    }

    private func debugSearch(_ runtime: BookSourceRuntime, _ source: BookSource, keyword: String) async {
        add("━━ 搜索链路 ━━", .header)
        guard let searchUrl = source.searchUrl, !searchUrl.isEmpty else {
            add("searchUrl 为空，无法搜索", .error); return
        }
        guard source.ruleSearch?.bookList?.isEmpty == false else {
            add("ruleSearch.bookList 为空，无法定位列表", .error); return
        }
        let kw = keyword.isEmpty ? "斗破苍穹" : keyword
        add("搜索关键词: \(kw)", .info)
        do {
            let results = try await runtime.search(kw)
            add("命中 \(results.count) 条", .header)
            for r in results.prefix(10) {
                add("《\(r.name)》 \(r.author) → \(r.bookUrl)", .item)
            }
            guard let first = results.first else {
                add("搜索无结果：检查 searchUrl / ruleSearch 规则", .error); return
            }
            add("", .info)
            await debugToc(runtime, source, url: first.bookUrl)
        } catch {
            add("搜索失败: \(error.localizedDescription)", .error)
        }
    }

    private func debugDetail(_ runtime: BookSourceRuntime, _ source: BookSource, url: String) async {
        add("━━ 详情页 ━━", .header)
        add("详情页 URL: \(url)", .info)
        add("引擎会解析 ruleBookInfo.tocUrl 拿到真正目录地址（若书源配置了 JSON 接口/独立目录页）。", .item)
        await debugToc(runtime, source, url: url)
    }

    private func debugToc(_ runtime: BookSourceRuntime, _ source: BookSource, url: String) async {
        add("━━ 目录链路 ━━", .header)
        guard let rule = source.ruleToc else {
            add("ruleToc 为空", .error); return
        }
        guard rule.chapterList?.isEmpty == false else {
            add("ruleToc.chapterList 为空，无法定位章节列表", .error); return
        }
        add("目录请求 URL: \(url)", .info)
        do {
            let toc = try await runtime.getToc(bookUrl: url)
            add("目录共 \(toc.count) 章", .header)
            for (i, c) in toc.prefix(20).enumerated() {
                add("第 \(i + 1) 章: \(c.name)", .item)
                add("   链接: \(c.url)", .item)
            }
            guard let first = toc.first else {
                add("目录为空：检查 ruleToc.chapterList / chapterName / chapterUrl 规则", .error); return
            }
            add("", .info)
            await debugContent(runtime, source, url: first.url)
        } catch {
            add("目录失败: \(error.localizedDescription)", .error)
        }
    }

    private func debugContent(_ runtime: BookSourceRuntime, _ source: BookSource, url: String) async {
        add("━━ 正文链路 ━━", .header)
        guard let rule = source.ruleContent else {
            add("ruleContent 为空", .error); return
        }
        guard rule.content?.isEmpty == false else {
            add("ruleContent.content 为空", .error); return
        }
        add("正文请求 URL: \(url)", .info)
        do {
            let text = try await runtime.getContent(chapterUrl: url)
            if text.isEmpty {
                add("正文为空：检查 ruleContent.content 规则（可能编码/选择器不对）", .error)
            } else {
                add("正文解析完成，共 \(text.count) 字", .header)
                add(String(text.prefix(300)), .item)
                add(text.count > 300 ? "……（已截断）" : "", .item)
            }
        } catch {
            add("正文失败: \(error.localizedDescription)", .error)
        }
    }

    private func isURL(_ s: String) -> Bool {
        guard let u = URL(string: s), let scheme = u.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }
}
