import SwiftUI
import UIKit

/// 本地 TXT 阅读器（与在线书源阅读器共用同一套 UI：
/// 5种翻页动画 / 丰富排版 / 中间点击显示工具栏 / 控制栏）
struct LocalReaderView: View {
    @Environment(\.dismiss) private var dismiss
    let bookName: String
    @Bindable var viewModel: TxtReaderViewModel

    @StateObject private var config = ReaderConfig.shared
    @AppStorage("reader.autoRead") private var autoRead = false

    @State private var pages: [String] = []
    @State private var paginatedForKey = ""
    @State private var pageIndex = 0
    @State private var showControls = false
    @State private var showSettings = false
    @State private var showToc = false

    init(book: LocalBook) {
        self.bookName = book.name
        self._viewModel = Bindable(TxtReaderViewModel(book: book))
    }

    private var bgColor: Color { config.currentTheme.background }
    private var textColor: Color { config.currentTheme.textColor }

    var body: some View {
        GeometryReader { geo in
            let pageSize = CGSize(
                width: max(geo.size.width - config.paddingLeft - config.paddingRight, 1),
                height: max(geo.size.height - config.paddingTop - config.paddingBottom, 1)
            )
            let key = "\(viewModel.currentContent.hashValue)|\(Int(config.fontSize))|\(config.lineSpacing)|\(config.fontName)|\(config.bold)|\(config.paragraphSpacing)|\(config.paragraphIndent)|\(config.textAlignment)|"
                + "\(Int(pageSize.width))x\(Int(pageSize.height))|\(viewModel.currentIndex)"

            ZStack {
                bgColor.ignoresSafeArea()

                if paginatedForKey == key, pageIndex < pages.count {
                    PageReaderView(
                        pages: pages,
                        pageIndex: $pageIndex,
                        pageSize: pageSize,
                        config: config,
                        onPageChange: { _ in }
                    )
                } else {
                    ProgressView()
                }

                if config.eyeCare {
                    Color.yellow.opacity(0.07).ignoresSafeArea().allowsHitTesting(false)
                }

                if config.currentPageAnim != .slide && config.currentPageAnim != .scroll {
                    readerTapOverlay
                }

                chrome
                    .zIndex(20)
            }
            .task(id: key) {
                await repaginate(key: key, pageSize: pageSize)
            }
            .task(id: autoRead) {
                guard autoRead else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: UInt64(config.autoReadSpeed * 1_000_000_000))
                    if Task.isCancelled { break }
                    goNextPage()
                }
            }
        }
        .statusBarHidden(!showControls)
        .preferredColorScheme(config.nightMode ? .dark : .light)
        .toolbar(.hidden, for: .tabBar)
        .sheet(isPresented: $showSettings) {
            ReaderSettingsPanel().presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showToc) {
            tocSheet
                .presentationDetents([.large])
        }
    }

    // MARK: - 点击区域

    private var readerTapOverlay: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                Rectangle().fill(.clear)
                    .contentShape(Rectangle())
                    .onTapGesture { goPrevPage() }
                Rectangle().fill(.clear)
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { showControls.toggle() } }
                Rectangle().fill(.clear)
                    .contentShape(Rectangle())
                    .onTapGesture { goNextPage() }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .zIndex(10)
    }

    // MARK: - 控制层

    private var chrome: some View {
        VStack(spacing: 0) {
            if showControls { topBar }
            Spacer(minLength: 0)
            if showControls {
                bottomBar
            } else if !pages.isEmpty {
                Text("\(pageIndex + 1) / \(pages.count)")
                    .font(.caption2)
                    .foregroundStyle(textColor.opacity(0.55))
                    .padding(.bottom, 10)
            }
        }
        .padding(.horizontal, 12)
        .animation(.easeInOut(duration: 0.2), value: showControls)
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 36, height: 36)
                    .glassCircle()
            }
            Text(viewModel.currentTitle ?? bookName)
                .font(.subheadline.bold())
                .lineLimit(1)
            Spacer()
        }
        .padding(10)
        .glassCard(RoundedRectangle(cornerRadius: 16))
    }

    private var bottomBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(viewModel.currentTitle ?? bookName)
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Slider(
                value: Binding(
                    get: { Double(min(pageIndex, max(pages.count - 1, 0))) },
                    set: { pageIndex = Int($0) }
                ),
                in: 0...Double(max(pages.count - 1, 1))
            )
            .tint(Theme.accent)
            HStack {
                toolButton("list.bullet", "目录") { showToc = true }
                toolButton(config.nightMode ? "sun.max" : "moon", config.nightMode ? "日间" : "夜间") {
                    config.nightMode.toggle()
                }
                toolButton(autoRead ? "pause.circle" : "play.circle", "自动") {
                    autoRead.toggle()
                }
                toolButton("textformat.size", "排版") { showSettings = true }
                Spacer()
                Text("\(pageIndex + 1)/\(pages.count)").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .glassCard(RoundedRectangle(cornerRadius: 16))
    }

    private func toolButton(_ icon: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 16, weight: .medium))
                Text(label).font(.caption2)
            }
            .foregroundStyle(.primary.opacity(0.8))
            .frame(width: 44, height: 40)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 目录

    private var tocSheet: some View {
        NavigationStack {
            List {
                ForEach(0..<viewModel.chapters.count, id: \.self) { idx in
                    let ch = viewModel.chapters[idx]
                    Button {
                        viewModel.openChapter(idx)
                        showToc = false
                    } label: {
                        HStack {
                            Text(ch.title).font(.subheadline)
                                .foregroundStyle(idx == viewModel.currentIndex ? Theme.accent : .primary)
                                .lineLimit(1)
                            Spacer()
                            if idx == viewModel.currentIndex {
                                Image(systemName: "chevron.right")
                                    .font(.caption2).foregroundStyle(Theme.accent)
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("目录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { showToc = false }
                }
            }
        }
    }

    // MARK: - 翻页

    private func goNextPage() {
        guard !pages.isEmpty else { return }
        if pageIndex + 1 < pages.count {
            pageIndex += 1
        } else {
            viewModel.nextChapter()
        }
    }
    private func goPrevPage() {
        if pageIndex > 0 {
            pageIndex -= 1
        } else {
            viewModel.prevChapter()
        }
    }

    // MARK: - 分页

    private func repaginate(key: String, pageSize: CGSize) async {
        guard !viewModel.currentContent.isEmpty else {
            pages = []; paginatedForKey = key; return
        }
        let font = config.uiFont
        let lSpacing = config.lineSpacing
        let pSpacing = config.paragraphSpacing
        let indent = config.indentPrefix
        let result = await Task.detached(priority: .userInitiated) {
            TextPaginator.paginate(
                text: viewModel.currentContent,
                font: font,
                lineSpacing: lSpacing,
                paragraphSpacing: pSpacing,
                paragraphIndent: indent,
                alignment: config.coreTextAlignment,
                pageSize: pageSize
            )
        }.value
        pages = result
        if pageIndex >= result.count { pageIndex = 0 }
        paginatedForKey = key
    }
}
