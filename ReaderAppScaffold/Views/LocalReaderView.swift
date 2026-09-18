import SwiftUI
import UIKit
import AVFoundation

/// 本地 TXT 阅读器（与在线书源阅读器完全同一套 UI：深色液态玻璃控制层）
struct LocalReaderView: View {
    @Environment(\.dismiss) private var dismiss
    let bookName: String
    @Bindable var viewModel: TxtReaderViewModel

    @ObservedObject private var config = ReaderConfig.shared
    @StateObject private var speech = ReaderSpeechController()
    @AppStorage("reader.autoRead") private var autoRead = false

    @State private var pages: [ReaderPage] = []
    @State private var paginatedForKey = ""
    @State private var paginationTaskID: UUID?
    @State private var pageIndex = 0
    @State private var pendingJumpToLastPage = false
    @State private var showControls = false
    @State private var showSettings = false
    @State private var showToc = false

    init(book: LocalBook) {
        self.bookName = book.name
        self._viewModel = Bindable(TxtReaderViewModel(book: book))
    }

    private var bgColor: Color { config.currentTheme.background }
    private var textColor: Color { config.currentTheme.textColor }

    /// 正文指纹：O(1) 长度+首尾采样，替代整章 hashValue。
    private func contentFingerprint(_ text: String) -> String {
        let head = text.prefix(32)
        let tail = text.suffix(32)
        return "\(text.count)-\(head)-\(tail)"
    }

    private var brightnessBinding: Binding<Double> {
        Binding(
            get: { Double(UIScreen.main.brightness) },
            set: { UIScreen.main.brightness = CGFloat($0) }
        )
    }

    var body: some View {
        GeometryReader { geo in
            // 全屏沉浸（与在线阅读器一致）：分页尺寸含安全区，翻页效果铺满全屏。
            let fullWidth = geo.size.width + geo.safeAreaInsets.leading + geo.safeAreaInsets.trailing
            let fullHeight = geo.size.height + geo.safeAreaInsets.top + geo.safeAreaInsets.bottom
            let pageSize = CGSize(
                width: max(fullWidth - config.paddingH * 2, 1),
                height: max(fullHeight - config.paddingTop - config.paddingBottom, 1)
            )
            let paginationKey = [
                "c\(contentFingerprint(viewModel.currentContent))",
                "f\(Int(config.fontSize))",
                "ls\(Int(config.lineSpacing))",
                "ps\(Int(config.paragraphSpacing))",
                "in\(config.paragraphIndent)",
                "b\(config.bold ? 1 : 0)",
                "pg\(Int(pageSize.width))x\(Int(pageSize.height))",
                "ch\(viewModel.currentIndex)"
            ].joined(separator: "|")

            ZStack {
                bgColor.ignoresSafeArea()

                if paginatedForKey == paginationKey, !pages.isEmpty {
                    PageReaderViewRepresentable(
                        pages: pages,
                        config: config,
                        currentIndex: $pageIndex,
                        onOutsideTap: { location in
                            handlePageTap(location, width: geo.size.width)
                        }
                    )
                    // 主题/夜间切换走 refreshAppearance 热刷新；
                    // 只有翻页模式切换才通过 identity 重建容器。
                    .ignoresSafeArea(.container, edges: .all)
                    .contentShape(Rectangle())
                    .id(config.pageAnim)
                    // 点击分发由 PageContentView 内部手势统一处理，
                    // 这里不再叠加 onTapGesture 避免双重触发。
                } else {
                    ProgressView()
                }

                chrome
                    .zIndex(20)
            }
            .task(id: paginationKey) {
                await repaginate(key: paginationKey, pageSize: pageSize)
            }
            .task(id: autoRead) {
                guard autoRead else { return }
                // 使用更安全的循环模式，避免无限递归更新
                for _ in 0..<1000 {
                    guard !Task.isCancelled else { break }
                    try? await Task.sleep(nanoseconds: UInt64(config.autoReadSpeed * 1_000_000_000))
                    guard !Task.isCancelled else { break }
                    guard autoRead else { break }
                    guard advancePage(allowNextChapter: false) else { break }
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
        .onChange(of: viewModel.currentIndex) { _, _ in
            if !pendingJumpToLastPage { pageIndex = 0 }
            if speech.isSpeaking, pageIndex < pages.count { speech.speak(pages[pageIndex].plainText) }
        }
        .onChange(of: pageIndex) { _, _ in
            if speech.isSpeaking, pageIndex < pages.count { speech.speak(pages[pageIndex].plainText) }
        }
    }

    private func handlePageTap(_ location: CGPoint, width: CGFloat) {
        let edge = max(72, width * 0.24)
        if location.x <= edge {
            goPrevPage()
        } else if location.x >= width - edge {
            _ = advancePage(allowNextChapter: true)
        } else {
            withAnimation(.easeInOut(duration: 0.2)) { showControls.toggle() }
        }
    }

    // MARK: - 沉浸式控制层（与在线阅读完全一致）

    private var chrome: some View {
        VStack(spacing: 0) {
            if showControls {
                LiquidGlassContainer(spacing: 12) { immersiveHeader }
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity)
                    ))
            }
            Spacer(minLength: 0)
            if showControls {
                LiquidGlassContainer(spacing: 14) { immersiveBottomPanel }
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
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(textColor)
                    .frame(width: 36, height: 36)
                    .glassCircle()
            }
            Text(viewModel.currentTitle ?? bookName)
                .font(.subheadline.bold())
                .foregroundStyle(textColor)
                .lineLimit(1)
            Spacer(minLength: 8)
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(textColor)
                .frame(width: 36, height: 36)
                .glassCircle()
        }
    }

    private var immersiveBottomPanel: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "sun.min").font(.caption).foregroundStyle(Theme.textSecondary)
                Slider(value: brightnessBinding, in: 0.05...1).tint(Theme.accent)
                Image(systemName: "sun.max.fill").font(.caption).foregroundStyle(Theme.textSecondary)
            }
            HStack {
                Button {
                    pendingJumpToLastPage = true
                    viewModel.prevChapter()
                } label: { Text("上一章").font(.footnote) }
                    .disabled(!viewModel.hasPreviousChapter)
                Spacer()
                Text("\(pageIndex + 1) / \(max(pages.count, 1))")
                    .font(.caption2).foregroundStyle(Theme.textSecondary)
                Spacer()
                Button {
                    pendingJumpToLastPage = false
                    pageIndex = 0
                    viewModel.nextChapter()
                } label: { Text("下一章").font(.footnote) }
                    .disabled(!viewModel.hasNextChapter)
            }
            .foregroundStyle(.primary)
            HStack {
                immersiveToolButton("list.bullet", "目录") { showToc = true }
                Spacer()
                immersiveToolButton(speech.isSpeaking ? "headphones.circle.fill" : "headphones", "TTS") {
                    guard pageIndex < pages.count else { return }
                    speech.toggle(pages[pageIndex].plainText)
                }
                Spacer()
                immersiveToolButton("gearshape", "设置") { showSettings = true }
            }
            .foregroundStyle(.primary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .glassCard(RoundedRectangle(cornerRadius: 18), interactive: true)
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
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

    @discardableResult
    private func advancePage(allowNextChapter: Bool) -> Bool {
        guard !pages.isEmpty else { return false }
        if pageIndex + 1 < pages.count {
            pageIndex += 1
            return true
        }
        guard allowNextChapter, viewModel.hasNextChapter else { return false }
        pendingJumpToLastPage = false
        pageIndex = 0
        viewModel.nextChapter()
        return true
    }

    private func goPrevPage() {
        if pageIndex > 0 {
            pageIndex -= 1
        } else if viewModel.hasPreviousChapter {
            pendingJumpToLastPage = true
            viewModel.prevChapter()
        } else {
            pendingJumpToLastPage = false
        }
    }

    // MARK: - 分页

    private func repaginate(key: String, pageSize: CGSize) async {
        guard !viewModel.currentContent.isEmpty else {
            pages = []; paginatedForKey = key; return
        }

        // 单飞分页：快速拖动滑杆时旧任务自动作废。
        let taskID = UUID()
        paginationTaskID = taskID

        let font = config.uiFont
        let badgeColor = UIColor.systemGray // 固定中性灰：明暗主题下同一张图，切换主题不需要重新分页
        let lSpacing = config.lineSpacing
        let pSpacing = config.paragraphSpacing
        let indent = config.indentPixels
        let content = viewModel.currentContent
        let alignment = config.coreTextAlignment
        let chapterIndex = viewModel.currentIndex

        let result = await Task.detached(priority: .userInitiated) {
            ReaderPageComposer.compose(
                content: content,
                markers: [],
                legacyReviewLinks: false,
                reviewCounts: [:],
                font: font,
                badgeColor: badgeColor,
                lineSpacing: lSpacing,
                paragraphSpacing: pSpacing,
                firstLineIndent: indent,
                alignment: alignment,
                pageSize: pageSize,
                buildKey: key
            )
        }.value

        guard taskID == paginationTaskID else { return }
        guard chapterIndex == viewModel.currentIndex else { return }

        guard let result, !result.isEmpty else {
            pages = []
            paginatedForKey = key
            return
        }
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
