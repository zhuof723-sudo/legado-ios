import SwiftUI
import SwiftData
import UIKit
import LegadoRuleEngine

enum SourceEditTab: String, CaseIterable, Identifiable {
    case basic = "基本"
    case search = "搜索"
    case explore = "发现"
    case info = "详情"
    case toc = "目录"
    case content = "正文"
    var id: String { rawValue }
}

private struct SourceEditField: Identifiable {
    let path: String
    let title: String
    let key: String
    let placeholder: String
    let minHeight: CGFloat
    let code: Bool
    var id: String { path }

    init(_ path: String, _ title: String, key: String? = nil,
         placeholder: String? = nil, minHeight: CGFloat = 58, code: Bool = false) {
        self.path = path
        self.title = title
        self.key = key ?? path.split(separator: ".").last.map(String.init) ?? path
        self.placeholder = placeholder ?? "请输入\(title)"
        self.minHeight = minHeight
        self.code = code
    }
}

private enum SourceEditSchema {
    static let basic: [SourceEditField] = [
        .init("bookSourceUrl", "源 URL", key: "sourceUrl", placeholder: "请输入书源 URL"),
        .init("bookSourceName", "源名称", key: "sourceName", placeholder: "请输入源名称"),
        .init("bookSourceGroup", "源分组", key: "sourceGroup", placeholder: "请输入源分组"),
        .init("bookSourceComment", "源注释", key: "sourceComment", minHeight: 94),
        .init("loginUrl", "登录 URL", minHeight: 94, code: true),
        .init("loginUi", "登录 UI", minHeight: 130, code: true),
        .init("loginCheckJs", "登录检查 JS", minHeight: 120, code: true),
        .init("bookUrlPattern", "书籍 URL 正则", minHeight: 74, code: true),
        .init("header", "请求头", minHeight: 130, code: true),
        .init("variableComment", "变量说明", minHeight: 94),
        .init("concurrentRate", "并发率", placeholder: "例如 1/1000"),
        .init("jsLib", "jsLib", minHeight: 180, code: true),
        .init("coverDecodeJs", "封面解密 JS", minHeight: 120, code: true),
        .init("exploreScreen", "发现筛选配置", minHeight: 100, code: true)
    ]

    static let search: [SourceEditField] = [
        .init("searchUrl", "搜索地址", key: "url", minHeight: 84, code: true),
        .init("ruleSearch.checkKeyWord", "校验关键字", key: "checkKeyWord"),
        .init("ruleSearch.bookList", "书籍列表规则", key: "bookList", minHeight: 90, code: true),
        .init("ruleSearch.name", "书名规则", key: "name", minHeight: 74, code: true),
        .init("ruleSearch.author", "作者规则", key: "author", minHeight: 74, code: true),
        .init("ruleSearch.kind", "分类规则", key: "kind", minHeight: 74, code: true),
        .init("ruleSearch.wordCount", "字数规则", key: "wordCount", minHeight: 74, code: true),
        .init("ruleSearch.lastChapter", "最新章节规则", key: "lastChapter", minHeight: 74, code: true),
        .init("ruleSearch.intro", "简介规则", key: "intro", minHeight: 90, code: true),
        .init("ruleSearch.coverUrl", "封面规则", key: "coverUrl", minHeight: 120, code: true),
        .init("ruleSearch.bookUrl", "详情页 URL 规则", key: "bookUrl", minHeight: 90, code: true),
        .init("ruleSearch.updateTime", "更新时间规则", key: "updateTime", minHeight: 74, code: true)
    ]

    static let explore: [SourceEditField] = [
        .init("exploreUrl", "发现地址规则", key: "url", minHeight: 210, code: true),
        .init("ruleExplore.bookList", "书籍列表规则", key: "bookList", minHeight: 90, code: true),
        .init("ruleExplore.name", "书名规则", key: "name", minHeight: 74, code: true),
        .init("ruleExplore.author", "作者规则", key: "author", minHeight: 74, code: true),
        .init("ruleExplore.kind", "分类规则", key: "kind", minHeight: 74, code: true),
        .init("ruleExplore.wordCount", "字数规则", key: "wordCount", minHeight: 74, code: true),
        .init("ruleExplore.lastChapter", "最新章节规则", key: "lastChapter", minHeight: 74, code: true),
        .init("ruleExplore.intro", "简介规则", key: "intro", minHeight: 90, code: true),
        .init("ruleExplore.coverUrl", "封面规则", key: "coverUrl", minHeight: 120, code: true),
        .init("ruleExplore.bookUrl", "详情页 URL 规则", key: "bookUrl", minHeight: 90, code: true),
        .init("ruleExplore.updateTime", "更新时间规则", key: "updateTime", minHeight: 74, code: true)
    ]

    static let info: [SourceEditField] = [
        .init("ruleBookInfo.init", "预处理规则", key: "bookInfoInit", minHeight: 110, code: true),
        .init("ruleBookInfo.name", "书名规则", key: "name", minHeight: 74, code: true),
        .init("ruleBookInfo.author", "作者规则", key: "author", minHeight: 74, code: true),
        .init("ruleBookInfo.kind", "分类规则", key: "kind", minHeight: 74, code: true),
        .init("ruleBookInfo.wordCount", "字数规则", key: "wordCount", minHeight: 74, code: true),
        .init("ruleBookInfo.lastChapter", "最新章节规则", key: "lastChapter", minHeight: 74, code: true),
        .init("ruleBookInfo.intro", "简介规则", key: "intro", minHeight: 100, code: true),
        .init("ruleBookInfo.coverUrl", "封面规则", key: "coverUrl", minHeight: 110, code: true),
        .init("ruleBookInfo.tocUrl", "目录 URL 规则", key: "tocUrl", minHeight: 90, code: true),
        .init("ruleBookInfo.canReName", "允许修改书名作者", key: "canReName"),
        .init("ruleBookInfo.downloadUrls", "下载 URL 规则", key: "downloadUrls", minHeight: 120, code: true),
        .init("ruleBookInfo.updateTime", "更新时间规则", key: "updateTime", minHeight: 74, code: true)
    ]

    static let toc: [SourceEditField] = [
        .init("ruleToc.preUpdateJs", "更新之前 JS", key: "preUpdateJs", minHeight: 100, code: true),
        .init("ruleToc.chapterList", "目录列表规则", key: "chapterList", minHeight: 220, code: true),
        .init("ruleToc.chapterName", "章节名称规则", key: "chapterName", minHeight: 74, code: true),
        .init("ruleToc.chapterUrl", "章节 URL 规则", key: "chapterUrl", minHeight: 74, code: true),
        .init("ruleToc.formatJs", "格式化规则", key: "formatJs", minHeight: 100, code: true),
        .init("ruleToc.wordCount", "字数规则", key: "wordCount", minHeight: 74, code: true),
        .init("ruleToc.isVolume", "Volume 标识", key: "isVolume", minHeight: 74, code: true),
        .init("ruleToc.updateTime", "更新时间", key: "updateTime", minHeight: 74, code: true),
        .init("ruleToc.isVip", "VIP 标识", key: "isVip", minHeight: 74, code: true),
        .init("ruleToc.isPay", "购买标识", key: "isPay", minHeight: 74, code: true),
        .init("ruleToc.nextTocUrl", "目录下一页规则", key: "nextTocUrl", minHeight: 90, code: true)
    ]

    static let content: [SourceEditField] = [
        .init("ruleContent.content", "正文规则", key: "content", minHeight: 260, code: true),
        .init("ruleContent.subContent", "正文副本", key: "subContent", minHeight: 100, code: true),
        .init("ruleContent.title", "标题规则", key: "title", minHeight: 74, code: true),
        .init("ruleContent.nextContentUrl", "正文下一页 URL 规则", key: "nextContentUrl", minHeight: 90, code: true),
        .init("ruleContent.webJs", "WebView JS", key: "webJs", minHeight: 110, code: true),
        .init("ruleContent.sourceRegex", "资源正则", key: "sourceRegex", minHeight: 90, code: true),
        .init("ruleContent.replaceRegex", "替换规则", key: "replaceRegex", minHeight: 110, code: true),
        .init("ruleContent.imageStyle", "图片样式", key: "imageStyle", minHeight: 74, code: true),
        .init("ruleContent.imageDecode", "图片解密", key: "imageDecode", minHeight: 120, code: true),
        .init("ruleContent.payAction", "购买操作", key: "payAction", minHeight: 110, code: true),
        .init("ruleContent.callBackJs", "回调操作", key: "callBackJs", minHeight: 120, code: true)
    ]

    static var all: [SourceEditField] { basic + search + explore + info + toc + content }
    static func fields(for tab: SourceEditTab) -> [SourceEditField] {
        switch tab {
        case .basic: return basic
        case .search: return search
        case .explore: return explore
        case .info: return info
        case .toc: return toc
        case .content: return content
        }
    }
}

@MainActor
@Observable
private final class SourceEditorDraft {
    var values: [String: String] = [:]
    var sourceType = 0
    var enabled = true
    var enabledExplore = true
    var enabledCookieJar = true
    var presentsAndroidIdentity = true
    var eventListener = false
    var customButton = false
    private var root: [String: Any]

    init(rawJSON: String) {
        let object: Any? = rawJSON.data(using: .utf8).flatMap {
            try? JSONSerialization.jsonObject(with: $0, options: [.fragmentsAllowed])
        }
        if let dictionary = object as? [String: Any] {
            root = dictionary
        } else if let array = object as? [[String: Any]], let first = array.first {
            root = first
        } else {
            root = [:]
        }
        normalizeRuleObjects()
        for field in SourceEditSchema.all {
            values[field.path] = stringValue(at: field.path)
        }
        sourceType = intValue(root["bookSourceType"], fallback: 0)
        enabled = boolValue(root["enabled"], fallback: true)
        enabledExplore = boolValue(root["enabledExplore"], fallback: true)
        enabledCookieJar = boolValue(root["enabledCookieJar"], fallback: true)
        presentsAndroidIdentity = boolValue(root["presentsAndroidIdentity"], fallback: true)
        eventListener = boolValue(root["eventListener"], fallback: false)
        customButton = boolValue(root["customButton"], fallback: false)
    }

    func value(_ path: String) -> String { values[path] ?? "" }
    func setValue(_ value: String, path: String) { values[path] = value }

    func encodedJSON() throws -> String {
        var output = root
        for field in SourceEditSchema.all {
            setPath(field.path, value: values[field.path] ?? "", in: &output)
        }
        output["bookSourceType"] = sourceType
        output["enabled"] = enabled
        output["enabledExplore"] = enabledExplore
        output["enabledCookieJar"] = enabledCookieJar
        output["presentsAndroidIdentity"] = presentsAndroidIdentity
        output["eventListener"] = eventListener
        output["customButton"] = customButton
        guard JSONSerialization.isValidJSONObject(output) else {
            throw NSError(domain: "SourceEditor", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "编辑后的书源无法序列化"])
        }
        let data = try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    func rawPreview() -> String {
        (try? encodedJSON()) ?? "{}"
    }

    private func normalizeRuleObjects() {
        for key in ["ruleSearch", "ruleExplore", "ruleBookInfo", "ruleToc", "ruleContent", "ruleReview"] {
            guard let text = root[key] as? String,
                  let data = text.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            root[key] = object
        }
    }

    private func stringValue(at path: String) -> String {
        let parts = path.split(separator: ".").map(String.init)
        var current: Any = root
        for part in parts {
            guard let dictionary = current as? [String: Any], let next = dictionary[part] else { return "" }
            current = next
        }
        if current is NSNull { return "" }
        if let text = current as? String { return text }
        if let number = current as? NSNumber { return number.stringValue }
        if JSONSerialization.isValidJSONObject(current),
           let data = try? JSONSerialization.data(withJSONObject: current, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) {
            return String(data: data, encoding: .utf8) ?? ""
        }
        return String(describing: current)
    }

    private func setPath(_ path: String, value: String, in root: inout [String: Any]) {
        let parts = path.split(separator: ".").map(String.init)
        guard let first = parts.first else { return }
        if parts.count == 1 {
            if value.isEmpty { root.removeValue(forKey: first) } else { root[first] = value }
            return
        }
        var nested = root[first] as? [String: Any] ?? [:]
        setNested(Array(parts.dropFirst()), value: value, in: &nested)
        if nested.isEmpty { root.removeValue(forKey: first) } else { root[first] = nested }
    }

    private func setNested(_ parts: [String], value: String, in dictionary: inout [String: Any]) {
        guard let first = parts.first else { return }
        if parts.count == 1 {
            if value.isEmpty { dictionary.removeValue(forKey: first) } else { dictionary[first] = value }
            return
        }
        var nested = dictionary[first] as? [String: Any] ?? [:]
        setNested(Array(parts.dropFirst()), value: value, in: &nested)
        if nested.isEmpty { dictionary.removeValue(forKey: first) } else { dictionary[first] = nested }
    }

    private func boolValue(_ value: Any?, fallback: Bool) -> Bool {
        if let bool = value as? Bool { return bool }
        if let number = value as? NSNumber { return number.boolValue }
        if let text = value as? String {
            if text == "1" || text.lowercased() == "true" { return true }
            if text == "0" || text.lowercased() == "false" { return false }
        }
        return fallback
    }

    private func intValue(_ value: Any?, fallback: Int) -> Int {
        if let value = value as? Int { return value }
        if let number = value as? NSNumber { return number.intValue }
        if let text = value as? String, let number = Int(text) { return number }
        return fallback
    }
}

@MainActor
private struct LegacySourceEditView: View {
    let record: BookSourceRecord
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var draft: SourceEditorDraft
    @State private var selectedTab: SourceEditTab = .basic
    @State private var showDebug = false
    @State private var showRawJSON = false
    @State private var rawJSONText = ""
    @State private var notice: String?
    @State private var errorMessage: String?

    init(record: BookSourceRecord) {
        self.record = record
        self._draft = State(initialValue: SourceEditorDraft(rawJSON: record.rawJSON))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color(.systemGroupedBackground).ignoresSafeArea()
            VStack(spacing: 0) {
                editHeader
                typeAndFlags
                tabBar
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(SourceEditSchema.fields(for: selectedTab)) { field in
                            editField(field)
                        }
                        if let errorMessage {
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .padding(16)
                        }
                    }
                    .padding(.bottom, 60)
                }
                .scrollDismissesKeyboard(.interactively)
            }

            if let notice {
                Text(notice)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.78), in: Capsule())
                    .padding(.bottom, 24)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: notice)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showDebug) { SourceDebugView(record: record) }
        .sheet(isPresented: $showRawJSON) {
            RawSourceJSONEditor(text: $rawJSONText) {
                applyRawJSON()
            }
        }
    }

    private var editHeader: some View {
        HStack(spacing: 14) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: 54, height: 54)
                    .background(Color.white, in: Circle())
            }
            Spacer()
            Text("编辑书源")
                .font(.title2.bold())
            Spacer()
            Button { save(showDebugAfter: true) } label: {
                Image(systemName: "ladybug")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 54, height: 54)
                    .background(Color.white, in: Circle())
            }
            Menu {
                Button("保存配置", systemImage: "checkmark.circle") { save() }
                Button("查看原始 JSON", systemImage: "curlybraces") {
                    rawJSONText = draft.rawPreview()
                    showRawJSON = true
                }
                Button("复制 JSON", systemImage: "doc.on.doc") {
                    UIPasteboard.general.string = draft.rawPreview()
                    showNotice("已复制书源 JSON")
                }
                Button("恢复已保存内容", systemImage: "arrow.counterclockwise") {
                    draft = SourceEditorDraft(rawJSON: record.rawJSON)
                    showNotice("已恢复")
                }
            } label: {
                Image(systemName: "ellipsis.vertical")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.primary)
                    .frame(width: 54, height: 54)
                    .background(Color.white, in: Circle())
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemGroupedBackground))
    }

    private var typeAndFlags: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    Text("类型：").font(.headline)
                    Menu {
                        Picker("类型", selection: $draft.sourceType) {
                            Text("小说").tag(0)
                            Text("音频").tag(1)
                            Text("图片").tag(2)
                            Text("文件").tag(3)
                            Text("视频").tag(4)
                        }
                    } label: {
                        HStack(spacing: 7) {
                            Text(typeName)
                            Image(systemName: "chevron.down")
                        }
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 16)
                        .frame(height: 48)
                        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 9))
                    }
                    checkbox("启用", isOn: $draft.enabled)
                    checkbox("发现", isOn: $draft.enabledExplore)
                    checkbox("CookieJar", isOn: $draft.enabledCookieJar)
                }
                .padding(.horizontal, 20)
            }
            .frame(minHeight: 70)

            Divider()
            HStack(spacing: 28) {
                checkbox("事件监听", isOn: $draft.eventListener)
                checkbox("定制按钮", isOn: $draft.customButton)
                Spacer()
            }
            .padding(.horizontal, 28)
            .frame(minHeight: 66)
        }
        .background(Color(.systemBackground))
    }

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 30) {
                ForEach(SourceEditTab.allCases) { tab in
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) { selectedTab = tab }
                    } label: {
                        VStack(spacing: 8) {
                            Text(tab.rawValue)
                                .font(.headline)
                                .foregroundStyle(selectedTab == tab ? Theme.accent : .primary)
                            Capsule()
                                .fill(selectedTab == tab ? Theme.accent : Color.clear)
                                .frame(height: 4)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 22)
        }
        .frame(height: 60)
        .background(Color(.systemBackground))
        .overlay(alignment: .bottom) { Divider() }
    }

    private func checkbox(_ title: String, isOn: Binding<Bool>) -> some View {
        Button { isOn.wrappedValue.toggle() } label: {
            HStack(spacing: 7) {
                Image(systemName: isOn.wrappedValue ? "checkmark.square.fill" : "square")
                    .font(.title3)
                    .foregroundStyle(isOn.wrappedValue ? Theme.accent : .secondary)
                Text(title).font(.headline).foregroundStyle(.primary)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func editField(_ field: SourceEditField) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(field.title) (\(field.key))")
                .font(.headline)
                .foregroundStyle(Theme.accent)

            if field.minHeight > 80 {
                ZStack(alignment: .topLeading) {
                    TextEditor(text: binding(for: field.path))
                        .font(field.code ? .system(.body, design: .monospaced) : .body)
                        .scrollContentBackground(.hidden)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                    if draft.value(field.path).isEmpty {
                        Text(field.placeholder)
                            .font(.body)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 17)
                            .allowsHitTesting(false)
                    }
                }
                .frame(minHeight: field.minHeight)
                .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.black.opacity(0.10), lineWidth: 0.7))
            } else {
                TextField(field.placeholder, text: binding(for: field.path), axis: .vertical)
                    .font(field.code ? .system(.body, design: .monospaced) : .body)
                    .lineLimit(1...5)
                    .padding(.horizontal, 16)
                    .frame(minHeight: field.minHeight)
                    .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.black.opacity(0.10), lineWidth: 0.7))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 20)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func binding(for path: String) -> Binding<String> {
        Binding(
            get: { draft.value(path) },
            set: { draft.setValue($0, path: path) }
        )
    }

    private var typeName: String {
        switch draft.sourceType {
        case 1: return "音频"
        case 2: return "图片"
        case 3: return "文件"
        case 4: return "视频"
        default: return "小说"
        }
    }

    private func save(showDebugAfter: Bool = false) {
        do {
            let json = try draft.encodedJSON()
            guard let source = try BookSourceImporter.parse(json).first,
                  !source.bookSourceUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !source.bookSourceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw NSError(domain: "SourceEditor", code: 2,
                              userInfo: [NSLocalizedDescriptionKey: "源 URL 和源名称不能为空"])
            }
            let oldJSON = record.rawJSON
            let oldURL = record.bookSourceUrl
            let oldName = record.bookSourceName
            let oldGroup = record.bookSourceGroup
            let oldEnabled = record.enabled
            record.rawJSON = json
            record.bookSourceUrl = source.bookSourceUrl
            record.bookSourceName = source.bookSourceName
            record.bookSourceGroup = source.bookSourceGroup
            record.enabled = source.enabled
            do {
                try context.save()
                errorMessage = nil
                showNotice("书源已保存")
                if showDebugAfter { showDebug = true }
            } catch {
                record.rawJSON = oldJSON
                record.bookSourceUrl = oldURL
                record.bookSourceName = oldName
                record.bookSourceGroup = oldGroup
                record.enabled = oldEnabled
                throw error
            }
        } catch {
            errorMessage = "保存失败：\(error.localizedDescription)"
        }
    }

    private func applyRawJSON() {
        guard (try? BookSourceImporter.parse(rawJSONText).first) != nil else {
            errorMessage = "原始 JSON 无法解析"
            return
        }
        draft = SourceEditorDraft(rawJSON: rawJSONText)
        showRawJSON = false
        errorMessage = nil
        showNotice("已应用原始 JSON")
    }

    private func showNotice(_ text: String) {
        notice = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if notice == text { notice = nil }
        }
    }
}

private struct RawSourceJSONEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var text: String
    let onApply: () -> Void

    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .font(.system(.footnote, design: .monospaced))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding(12)
                .navigationTitle("原始 JSON")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("关闭") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("应用") { onApply() }
                    }
                }
        }
    }
}

@MainActor
struct SourceEditView: View {
    let record: BookSourceRecord
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var draft: SourceEditorDraft
    @State private var selectedTab: SourceEditTab = .basic
    @State private var editingField: SourceEditField?
    @State private var showDebug = false
    @State private var showRawJSON = false
    @State private var rawJSONText = ""
    @State private var notice: String?
    @State private var errorMessage: String?

    init(record: BookSourceRecord) {
        self.record = record
        self._draft = State(initialValue: SourceEditorDraft(rawJSON: record.rawJSON))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color(red: 0.82, green: 0.88, blue: 0.98).ignoresSafeArea()
            VStack(spacing: 0) {
                header
                tabPicker
                ScrollView {
                    LazyVStack(spacing: 14) {
                        if selectedTab == .basic {
                            basicSettingsCard
                        }
                        fieldGroup(SourceEditSchema.fields(for: selectedTab))
                        if selectedTab == .basic {
                            advancedSettingsCard
                        }
                        if let errorMessage {
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 18)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
                    .padding(.bottom, 30)
                }
                .scrollDismissesKeyboard(.interactively)
            }

            if let notice {
                Text(notice)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.78), in: Capsule())
                    .padding(.bottom, 24)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: notice)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $editingField) { field in
            SourceFieldEditor(
                field: field,
                initialValue: draft.value(field.path),
                onSave: { value in
                    draft.setValue(value, path: field.path)
                }
            )
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showDebug) {
            SourceDebugView(record: record)
        }
        .sheet(isPresented: $showRawJSON) {
            RawSourceJSONEditor(text: $rawJSONText) { applyRawJSON() }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.blue)
                    .frame(width: 58, height: 58)
                    .background(Color.white.opacity(0.86), in: Circle())
            }
            .accessibilityLabel("关闭")

            Spacer(minLength: 4)
            Text(record.bookSourceName.isEmpty ? "新建书源" : "编辑书源")
                .font(.title2.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Spacer(minLength: 4)

            HStack(spacing: 0) {
                Button {
                    saveAndDismiss()
                } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 25, weight: .medium))
                        .foregroundStyle(canSave ? .blue : .secondary)
                        .frame(width: 58, height: 58)
                }
                .disabled(!canSave)

                Menu {
                    Button("保存配置", systemImage: "checkmark.circle") { save() }
                    Button("测试当前配置", systemImage: "ladybug") {
                        if save() { showDebug = true }
                    }
                    Button("查看原始 JSON", systemImage: "curlybraces") {
                        rawJSONText = draft.rawPreview()
                        showRawJSON = true
                    }
                    Button("复制 JSON", systemImage: "doc.on.doc") {
                        UIPasteboard.general.string = draft.rawPreview()
                        showNotice("已复制书源 JSON")
                    }
                    Button("恢复已保存内容", systemImage: "arrow.counterclockwise") {
                        draft = SourceEditorDraft(rawJSON: record.rawJSON)
                        showNotice("已恢复")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.blue)
                        .frame(width: 54, height: 58)
                }
            }
            .background(Color.white.opacity(0.86), in: Capsule())
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .background(Color.white.opacity(0.30))
    }

    private var tabPicker: some View {
        HStack(spacing: 2) {
            ForEach(SourceEditTab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    Text(tab.rawValue)
                        .font(.headline)
                        .foregroundStyle(selectedTab == tab ? .primary : .primary.opacity(0.82))
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(
                            selectedTab == tab
                                ? Color.white.opacity(0.95)
                                : Color.clear,
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color.black.opacity(0.06), in: Capsule())
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private var basicSettingsCard: some View {
        VStack(spacing: 0) {
            settingRow("类型", subtitle: typeName) {
                Menu {
                    Picker("类型", selection: $draft.sourceType) {
                        Text("文字").tag(0)
                        Text("音频").tag(1)
                        Text("图片").tag(2)
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(typeName).foregroundStyle(.blue)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption)
                    }
                }
            }
            settingRow("启用", subtitle: "允许此书源参与搜索和阅读") {
                Toggle("", isOn: $draft.enabled).labelsHidden().tint(.blue)
            }
            settingRow("发现", subtitle: "在浏览页显示该书源的发现内容") {
                Toggle("", isOn: $draft.enabledExplore).labelsHidden().tint(.blue)
            }
            settingRow("提供设备标识码", subtitle: "默认开启，书源需要设备码时才会拿到。只有在某个书源不能被当成 Android 时才关闭。") {
                Toggle("", isOn: $draft.presentsAndroidIdentity).labelsHidden().tint(.blue)
            }
        }
        .editorCard()
    }

    private var advancedSettingsCard: some View {
        VStack(spacing: 0) {
            settingRow("CookieJar", subtitle: "保存网站 Cookie") {
                Toggle("", isOn: $draft.enabledCookieJar).labelsHidden().tint(.blue)
            }
            settingRow("事件监听", subtitle: "启用书源事件回调") {
                Toggle("", isOn: $draft.eventListener).labelsHidden().tint(.blue)
            }
            settingRow("定制按钮", subtitle: "启用书源自定义按钮") {
                Toggle("", isOn: $draft.customButton).labelsHidden().tint(.blue)
            }
        }
        .editorCard()
    }

    @ViewBuilder
    private func settingRow<Trailing: View>(
        _ title: String,
        subtitle: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.body)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 15)
        .overlay(alignment: .bottom) {
            Divider().padding(.leading, 18)
        }
    }

    private func fieldGroup(_ fields: [SourceEditField]) -> some View {
        VStack(spacing: 0) {
            ForEach(fields) { field in
                fieldRow(field)
                if field.id != fields.last?.id { Divider().padding(.leading, 18) }
            }
        }
        .editorCard()
    }

    private func fieldRow(_ field: SourceEditField) -> some View {
        Button {
            editingField = field
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(displayTitle(for: field))
                        .font(.body)
                        .foregroundStyle(.primary)
                    Text(preview(for: field))
                        .font(field.code ? .system(.subheadline, design: .monospaced) : .subheadline)
                        .foregroundStyle(draft.value(field.path).isEmpty ? .secondary : .primary.opacity(0.58))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 15)
            .frame(minHeight: field.minHeight > 130 ? 88 : 76)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func displayTitle(for field: SourceEditField) -> String {
        switch field.path {
        case "bookSourceUrl": return "书源地址"
        case "bookSourceName": return "书源名称"
        case "bookSourceGroup": return "书源分组"
        case "bookSourceComment": return "源注释"
        case "loginUrl": return "登入页 URL"
        case "loginUi": return "登录 UI"
        case "loginCheckJs": return "登入检查 JS"
        case "coverDecodeJs": return "封面解密"
        case "bookUrlPattern": return "书籍 URL 正则"
        case "header": return "请求头"
        case "variableComment": return "变量说明"
        case "concurrentRate": return "并发率"
        case "jsLib": return "jsLib"
        case "searchUrl": return "搜索 URL"
        case "exploreUrl": return "发现地址规则"
        case "ruleSearch.bookList": return "书籍列表规则"
        case "ruleSearch.checkKeyWord": return "校验关键字"
        case "ruleSearch.name": return "书名规则"
        case "ruleSearch.author": return "作者规则"
        case "ruleSearch.kind": return "分类规则"
        case "ruleSearch.wordCount": return "字数规则"
        case "ruleSearch.lastChapter": return "最新章节规则"
        case "ruleSearch.intro": return "简介规则"
        case "ruleSearch.coverUrl": return "封面规则"
        case "ruleSearch.bookUrl": return "详情页 URL 规则"
        case "ruleSearch.updateTime": return "更新时间规则"
        case "ruleExplore.bookList": return "书籍列表规则"
        case "ruleExplore.name": return "书名规则"
        case "ruleExplore.author": return "作者规则"
        case "ruleExplore.kind": return "分类规则"
        case "ruleExplore.wordCount": return "字数规则"
        case "ruleExplore.lastChapter": return "最新章节规则"
        case "ruleExplore.intro": return "简介规则"
        case "ruleExplore.coverUrl": return "封面规则"
        case "ruleExplore.bookUrl": return "详情页 URL 规则"
        case "ruleExplore.updateTime": return "更新时间规则"
        case "ruleBookInfo.init": return "预处理规则"
        case "ruleBookInfo.name": return "书名规则"
        case "ruleBookInfo.author": return "作者规则"
        case "ruleBookInfo.kind": return "分类规则"
        case "ruleBookInfo.wordCount": return "字数规则"
        case "ruleBookInfo.lastChapter": return "最新章节规则"
        case "ruleBookInfo.intro": return "简介规则"
        case "ruleBookInfo.coverUrl": return "封面规则"
        case "ruleBookInfo.tocUrl": return "目录 URL 规则"
        case "ruleBookInfo.canReName": return "允许修改书名作者"
        case "ruleBookInfo.downloadUrls": return "下载 URL 规则"
        case "ruleBookInfo.updateTime": return "更新时间规则"
        case "ruleToc.preUpdateJs": return "更新之前 JS"
        case "ruleToc.chapterList": return "章节列表规则"
        case "ruleToc.chapterName": return "章节名称规则"
        case "ruleToc.chapterUrl": return "章节 URL 规则"
        case "ruleToc.formatJs": return "格式化规则"
        case "ruleToc.wordCount": return "字数规则"
        case "ruleToc.isVolume": return "卷标识"
        case "ruleToc.updateTime": return "章节信息"
        case "ruleToc.isVip": return "VIP 标识"
        case "ruleToc.isPay": return "购买标识"
        case "ruleToc.nextTocUrl": return "目录下一页规则"
        case "ruleContent.content": return "正文规则"
        case "ruleContent.subContent": return "正文副本"
        case "ruleContent.title": return "章节名称规则"
        case "ruleContent.nextContentUrl": return "正文下一页 URL 规则"
        case "ruleContent.webJs": return "WebView JS"
        case "ruleContent.sourceRegex": return "资源正则"
        case "ruleContent.replaceRegex": return "净化规则"
        case "ruleContent.imageStyle": return "图片样式"
        case "ruleContent.imageDecode": return "图片解密"
        case "ruleContent.payAction": return "购买操作"
        case "ruleContent.callBackJs": return "回调操作"
        default: return field.title
        }
    }

    private func preview(for field: SourceEditField) -> String {
        let value = draft.value(field.path)
        if value.isEmpty { return field.placeholder }
        let lines = value.split(separator: "\n", omittingEmptySubsequences: false)
        let compact = lines.prefix(2).joined(separator: "\n")
        return compact + (lines.count > 2 ? "…" : "")
    }

    private var typeName: String {
        switch draft.sourceType {
        case 1: return "音频"
        case 2: return "图片"
        default: return "文字"
        }
    }

    private var canSave: Bool {
        !draft.value("bookSourceUrl").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !draft.value("bookSourceName").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @discardableResult
    private func save() -> Bool {
        do {
            let json = try draft.encodedJSON()
            guard let source = try BookSourceImporter.parse(json).first,
                  !source.bookSourceUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !source.bookSourceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw NSError(domain: "SourceEditor", code: 2,
                              userInfo: [NSLocalizedDescriptionKey: "书源地址和名称不能为空"])
            }
            let old = (record.rawJSON, record.bookSourceUrl, record.bookSourceName, record.bookSourceGroup, record.enabled)
            record.rawJSON = json
            record.bookSourceUrl = source.bookSourceUrl
            record.bookSourceName = source.bookSourceName
            record.bookSourceGroup = source.bookSourceGroup
            record.enabled = source.enabled
            do {
                try context.save()
                errorMessage = nil
                showNotice("书源已保存")
                return true
            } catch {
                record.rawJSON = old.0
                record.bookSourceUrl = old.1
                record.bookSourceName = old.2
                record.bookSourceGroup = old.3
                record.enabled = old.4
                throw error
            }
        } catch {
            errorMessage = "保存失败：\(error.localizedDescription)"
            return false
        }
    }

    private func saveAndDismiss() {
        if save() { dismiss() }
    }

    private func applyRawJSON() {
        guard (try? BookSourceImporter.parse(rawJSONText).first) != nil else {
            errorMessage = "原始 JSON 无法解析"
            return
        }
        draft = SourceEditorDraft(rawJSON: rawJSONText)
        showRawJSON = false
        errorMessage = nil
        showNotice("已应用原始 JSON")
    }

    private func showNotice(_ text: String) {
        notice = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if notice == text { notice = nil }
        }
    }
}

private struct SourceFieldEditor: View {
    @Environment(\.dismiss) private var dismiss
    let field: SourceEditField
    @State private var text: String
    let onSave: (String) -> Void

    init(field: SourceEditField, initialValue: String, onSave: @escaping (String) -> Void) {
        self.field = field
        self._text = State(initialValue: initialValue)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 10) {
                Text(field.title)
                    .font(.headline)
                    .foregroundStyle(Theme.accent)
                TextEditor(text: $text)
                    .font(field.code ? .system(.body, design: .monospaced) : .body)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(.separator, lineWidth: 0.7))
            }
            .padding(16)
            .navigationTitle("编辑字段")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        onSave(text)
                        dismiss()
                    }
                }
            }
        }
    }
}

private extension View {
    func editorCard() -> some View {
        background(Color(red: 0.91, green: 0.96, blue: 1.0), in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.white.opacity(0.72), lineWidth: 0.8))
    }
}
