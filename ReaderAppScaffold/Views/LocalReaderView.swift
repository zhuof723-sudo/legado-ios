import SwiftUI
import UIKit

/// 本地 TXT 阅读器（与在线书源阅读器共用同一套 UI：
/// 真分页 / 中间点击显示工具栏 / 滑动翻页 / 控制栏）
struct LocalReaderView: View {
    @Environment(\.dismiss) private var dismiss
    let bookName: String
    @Bindable var viewModel: TxtReaderViewModel

    @AppStorage("reader.fontSize") private var fontSize: Double = 18
    @AppStorage("reader.lineSpacingIndex") private var lineSpacingIndex: Int = 1
    @AppStorage("reader.bgIndex") private var bgIndex: Int = 1
    @AppStorage("reader.nightMode") private var nightMode = false
    @AppStorage("reader.eyeCare") private var eyeCare = false
    @AppStorage("reader.turnMode") private var turnMode: Int = 2
    @AppStorage("reader.autoRead") private var autoRead = false

    @State private var pages: [String] = []
    @State private var paginatedForKey = ""
    @State private var pageIndex = 0
    @State private var showControls = false
    @State private var showSettings = false
    @State private var showToc = false

    private let hPadding: CGFloat = 20
    private let tPadding: CGFloat = 56
    private let bPadding: CGFloat = 44

    init(book: LocalBook) {
        self.bookName = book.name
        self._viewModel = Bindable(TxtReaderViewModel(book: book))
    }

    private var lineSpacingValue: CGFloat {
        [CGFloat(4), CGFloat(8), CGFloat(14)][min(max(lineSpacingIndex, 0), 2)]
    }
    private var effectiveIndex: Int { nightMode ? 4 : min(max(bgIndex, 0), 3) }
    private var bgColor: Color { Theme.readerBackgrounds[effectiveIndex] }
    private var textColor: Color { Theme.readerTextColors[effectiveIndex] }

    var body: some View {
        GeometryReader { geo in
            let pageSize = CGSize(
                width: max(geo.size.width - hPadding * 2, 1),
                height: max(geo.size.height - tPadding - bPadding, 1)
            )
            let key = "\(viewModel.currentContent.hashValue)|\(Int(fontSize))|\(lineSpacingIndex)|"
                + "\(Int(pageSize.width))x\(Int(pageSize.height))|\(viewModel.currentIndex)"

            ZStack {
                bgColor.ignoresSafeArea()

                if paginatedForKey == key, pageIndex < pages.count {
                    if turnMode == 2 {
                        TabView(selection: $pageIndex) {
                            ForEach(pages.indices, id: \.self) { i in
                                pageText(pages[i], pageSize: pageSize).tag(i)
                            }
                        }
                        .tabViewStyle(.page(indexDisplayMode: .never))
                        .ignoresSafeArea(edges: .bottom)
                        .overlay(alignment: .bottom) {
                            if showControls { bottomBar }
                        }
                    } else {
                        pageText(pages[pageIndex], pageSize: pageSize)
                            .id("\(pageIndex)-\(key)")
                            .animation(.easeInOut(duration: 0.22), value: pageIndex)
                    }
                } else {
                    ProgressView()
                }

                if eyeCare {
                    Color.yellow.opacity(0.07).ignoresSafeArea().allowsHitTesting(false)
                }

                if turnMode != 2 {
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
                    try? await Task.sleep(nanoseconds: 3_500_000_000)
                    if Task.isCancelled { break }
                    goNextPage()
                }
            }
        }
        .statusBarHidden(!showControls)
        .readerActive()
        .toolbar(.hidden, for: .tabBar)
        .sheet(isPresented: $showSettings) {
            ReaderSettingsPanel().presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showToc) {
            tocSheet
                .presentationDetents([.large])
        }
    }

    // MARK: - 正文

    private func pageText(_ s: String, pageSize: CGSize) -> some View {
        Text(s)
            .font(.system(size: fontSize))
            .lineSpacing(lineSpacingValue)
            .foregroundStyle(textColor)
            .frame(width: pageSize.width, height: pageSize.height, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .top)
    }

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
                    .foregroundStyle(.secondary)
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
                    .background(Circle().fill(Color.white.opacity(0.7)))
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
        VStack(alignment: .leading, spacing: 12) {
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
                toolButton(nightMode ? "sun.max" : "moon", nightMode ? "日间" : "夜间") {
                    nightMode.toggle()
                }
                toolButton(autoRead ? "pause.circle" : "play.circle", "自动") {
                    autoRead.toggle()
                }
                toolButton("textformat.size", "字号") { showSettings = true }
                Spacer()
                Text("\(pageIndex + 1)/\(pages.count)").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .glassCard(RoundedRectangle(cornerRadius: 20))
    }

    private func toolButton(_ icon: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 18, weight: .medium))
                Text(label).font(.caption2)
            }
            .foregroundStyle(.primary.opacity(0.8))
            .frame(width: 52, height: 46)
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
        let fSize = fontSize
        let lSpacing = lineSpacingValue
        let result = await Task.detached(priority: .userInitiated) {
            TextPaginator.paginate(
                text: viewModel.currentContent,
                font: UIFont.systemFont(ofSize: fSize),
                lineSpacing: lSpacing,
                pageSize: pageSize
            )
        }.value
        pages = result
        if pageIndex >= result.count { pageIndex = 0 }
        paginatedForKey = key
    }
}
