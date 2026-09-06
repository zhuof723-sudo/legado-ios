import SwiftUI
import UIKit
import AVFoundation

/// 本地 TXT 阅读器（与在线书源阅读器完全同一套 UI：深色液态玻璃控制层）
struct LocalReaderView: View {
    @Environment(\.dismiss) private var dismiss
    let bookName: String
    @Bindable var viewModel: TxtReaderViewModel

    @StateObject private var config = ReaderConfig.shared
    @StateObject private var speech = ReaderSpeechController()
    @AppStorage("reader.autoRead") private var autoRead = false

    @State private var pages: [String] = []
    @State private var paginatedForKey = ""
    @State private var pageIndex = 0
    @State private var pendingJumpToLastPage = false
    @State private var showControls = false
    @State private var showSettings = false
    @State private var showToc = false
    @State private var showChapterSearch = false

    init(book: LocalBook) {
        self.bookName = book.name
        self._viewModel = Bindable(TxtReaderViewModel(book: book))
    }

    private var bgColor: Color { config.currentTheme.background }
    private var textColor: Color { config.currentTheme.textColor }

    var body: some View {
        GeometryReader { geo in
            let pageSize = CGSize(
                width: max(geo.size.width - config.paddingH * 2, 1),
                height: max(geo.size.height - config.paddingTop - config.paddingBottom, 1)
            )
            let key = "\(viewModel.currentContent.hashValue)|\(Int(config.fontSize))|\(config.lineSpacing)|\(config.bold)|\(config.paragraphSpacing)|\(config.paragraphIndent)|"
                + "\(Int(pageSize.width))x\(Int(pageSize.height))|\(viewModel.currentIndex)"

            ZStack {
                bgColor.ignoresSafeArea()

                if paginatedForKey == key, !pages.isEmpty {
                    PageReaderViewRepresentable(
                        pages: pages,
                        config: config,
                        currentIndex: $pageIndex
                    )
                    .padding(.horizontal, config.paddingH)
                    .padding(.top, config.paddingTop)
                    .padding(.bottom, config.paddingBottom)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) { showControls.toggle() }
                    }
                } else {
                    ProgressView()
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
        .statusBarHidden(false)
        .preferredColorScheme(config.nightMode ? .dark : .light)
        .toolbar(.hidden, for: .tabBar)
        .onDisappear { speech.stop() }
        .sheet(isPresented: $showSettings) {
            ReaderSettingsPanel().presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showToc) {
            tocSheet
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showChapterSearch) {
            ReaderChapterSearchView(text: viewModel.currentContent)
                .presentationDetents([.medium, .large])
        }
        .onChange(of: pageIndex) {
            if speech.isSpeaking, pageIndex < pages.count { speech.speak(pages[pageIndex]) }
        }
    }

    // MARK: - 沉浸式控制层（与在线阅读完全一致）

    private var chrome: some View {
        VStack(spacing: 0) {
            if showControls {
                immersiveHeader
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity)
                    ))
            }
            Spacer(minLength: 0)
            if showControls {
                immersiveBottomPanel
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .move(edge: .bottom).combined(with: .opacity)
                    ))
            } else if !pages.isEmpty {
                HStack {
                    Text("\(pageIndex + 1)/\(pages.count)")
                    Spacer()
                    Text(viewModel.currentTitle ?? "")
                        .lineLimit(1)
                }
                .font(.caption2)
                .foregroundStyle(textColor.opacity(0.55))
                .padding(.horizontal, 18)
                .padding(.bottom, 8)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .animation(.spring(response: 0.35, dampingFraction: 0.85, blendDuration: 0.1), value: showControls)
    }

    private var immersiveHeader: some View {
        HStack(spacing: 10) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .glassCircle()
            }
            Spacer(minLength: 0)
            Text(bookName)
                .font(.subheadline.bold())
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .frame(height: 36)
                .background(Color.black.opacity(0.22), in: Capsule())
                .glassCard(Capsule(), interactive: true)
            Spacer(minLength: 0)
            Circle()
                .fill(Color.white.opacity(0.15))
                .frame(width: 36, height: 36)
                .overlay(
                    Image(systemName: "book")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.7))
                )
        }
        .environment(\.colorScheme, .dark)
    }

    private var immersiveBottomPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(viewModel.currentTitle ?? bookName)
                    .font(.caption).foregroundStyle(.white).lineLimit(1)
                Spacer()
                Text("\(pageIndex + 1) / \(max(pages.count, 1))")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
            HStack(spacing: 8) {
                Button { goPrevPage() } label: {
                    Image(systemName: "chevron.left").frame(width: 28, height: 28)
                }
                .tint(.white.opacity(0.9))
                Slider(
                    value: Binding(
                        get: { Double(min(pageIndex, max(pages.count - 1, 0))) },
                        set: { pageIndex = Int($0.rounded()) }
                    ),
                    in: 0...Double(max(pages.count - 1, 1))
                )
                .tint(Theme.accent)
                Button { goNextPage() } label: {
                    Image(systemName: "chevron.right").frame(width: 28, height: 28)
                }
                .tint(.white.opacity(0.9))
            }
            HStack {
                immersiveToolButton("list.bullet", "目录") { showToc = true }
                Spacer()
                immersiveToolButton(speech.isSpeaking ? "speaker.wave.2.fill" : "speaker.wave.2", "听书") {
                    guard pageIndex < pages.count else { return }
                    speech.toggle(pages[pageIndex])
                }
                Spacer()
                immersiveToolButton("magnifyingglass", "搜索") { showChapterSearch = true }
                Spacer()
                immersiveToolButton("textformat.size", "排版") { showSettings = true }
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.36), in: RoundedRectangle(cornerRadius: 18))
        .glassCard(RoundedRectangle(cornerRadius: 18), interactive: true)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.1), lineWidth: 0.6))
        .shadow(color: .black.opacity(0.3), radius: 14, y: 6)
        .environment(\.colorScheme, .dark)
    }

    private func immersiveToolButton(_ icon: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 16, weight: .medium))
                Text(label).font(.caption2)
            }
            .frame(minWidth: 40, minHeight: 40)
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
            pendingJumpToLastPage = true
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
        let indent = config.indentPixels
        let result = await Task.detached(priority: .userInitiated) {
            TextPaginator.paginate(
                text: viewModel.currentContent,
                font: font,
                lineSpacing: lSpacing,
                paragraphSpacing: pSpacing,
                firstLineIndent: indent,
                alignment: config.coreTextAlignment,
                pageSize: pageSize
            )
        }.value
        pages = result
        if pendingJumpToLastPage {
            pageIndex = max(0, result.count - 1)
            pendingJumpToLastPage = false
        } else if pageIndex >= result.count {
            pageIndex = 0
        }
        paginatedForKey = key
    }
}
