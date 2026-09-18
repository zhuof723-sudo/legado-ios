import SwiftUI
import UIKit
import AVFoundation

/// 本地 TXT 阅读器（与在线阅读器共用同一套 Apple Books 式控制层 ReaderChrome）
struct LocalReaderView: View {
    @Environment(\.dismiss) private var dismiss
    let bookName: String
    /// 本地书籍标识：书签存储的 bookUrl 命名空间（local://id）
    private let bookID: String
    @Bindable var viewModel: TxtReaderViewModel

    @ObservedObject private var config = ReaderConfig.shared
    @StateObject private var speech = ReaderSpeechController()
    @AppStorage("reader.autoRead") private var autoRead = false

    @State private var pages: [ReaderPage] = []
    @State private var paginatedForKey = ""
    @State private var paginationTaskID: UUID?
    @State private var pageIndex = 0
    @State private var pendingJumpToLastPage = false
    /// 书签跳页目标：等新章分页完成后落到指定页。
    @State private var pendingJumpToPage: Int?
    @State private var showControls = false
    @State private var showSettings = false
    @State private var showToc = false
    @State private var showSearch = false
    @State private var isCurrentPageBookmarked = false

    init(book: LocalBook) {
        self.bookName = book.name
        self.bookID = book.id
        self._viewModel = Bindable(TxtReaderViewModel(book: book))
    }

    private var bookUrl: String { "local://\(bookID)" }
    private var bgColor: Color { config.currentTheme.background }
    private var textColor: Color { config.currentTheme.textColor }

    /// 正文指纹：O(1) 长度+首尾采样，替代整章 hashValue。
    private func contentFingerprint(_ text: String) -> String {
        let head = text.prefix(32)
        let tail = text.suffix(32)
        return "\(text.count)-\(head)-\(tail)"
    }

    /// 全书进度：章序号 + 页内占比 / 总章数。
    private var bookProgress: Double {
        guard viewModel.chapters.count > 1 else { return 0 }
        let inChapter = pages.isEmpty ? 0 : min(max(Double(pageIndex + 1) / Double(pages.count), 0), 1)
        return (Double(viewModel.currentIndex) + inChapter) / Double(viewModel.chapters.count)
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
                "ff\(config.fontFamily)", // 字体族（衬线/无衬线）参与分页
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
        .overlay(alignment: .bottom) {
            // Apple Books 式全书进度细线：贴底常显，不拦截触摸。
            ReaderProgressHairline(progress: bookProgress, accent: config.currentAccent)
        }
        .statusBarHidden(false)
        .preferredColorScheme(config.nightMode ? .dark : .light)
        .toolbar(.hidden, for: .tabBar)
        .onDisappear { speech.stop() }
        .sheet(isPresented: $showSettings) {
            ReaderAaPanel().presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showToc) {
            TocSheet(
                bookUrl: bookUrl,
                entries: viewModel.chapters.enumerated().map {
                    TocSheet.TocEntry(index: $0.offset, name: $0.element.title)
                },
                currentIndex: viewModel.currentIndex,
                onSelectChapter: { index in
                    viewModel.openChapter(index)
                },
                onSelectBookmark: { bookmark in
                    jumpToBookmark(bookmark)
                }
            )
            .presentationDetents([.large])
        }
        .sheet(isPresented: $showSearch) {
            ReaderChapterSearchView(text: viewModel.currentContent)
                .presentationDetents([.medium, .large])
        }
        .onChange(of: viewModel.currentIndex) { _, _ in
            if !pendingJumpToLastPage { pageIndex = 0 }
            refreshBookmarkState()
            if speech.isSpeaking, pageIndex < pages.count { speech.speak(pages[pageIndex].plainText) }
        }
        .onChange(of: pageIndex) { _, _ in
            refreshBookmarkState()
            if speech.isSpeaking, pageIndex < pages.count { speech.speak(pages[pageIndex].plainText) }
        }
    }

    // MARK: - 点击分区

    private func handlePageTap(_ location: CGPoint, width: CGFloat) {
        switch ReaderTapZones.classify(x: location.x, width: width) {
        case .previousPage:
            goPrevPage()
        case .nextPage:
            _ = advancePage(allowNextChapter: true)
        case .toggleControls:
            withAnimation(.easeInOut(duration: 0.2)) { showControls.toggle() }
        }
    }

    // MARK: - 书签

    private var bookmarkIdentity: BookBookmark {
        BookBookmark(
            bookUrl: bookUrl,
            chapterIndex: viewModel.currentIndex,
            pageIndex: pageIndex,
            label: (viewModel.currentTitle) + " · 第 \(pageIndex + 1) 页",
            createdAt: Date()
        )
    }

    private func refreshBookmarkState() {
        let id = bookmarkIdentity
        isCurrentPageBookmarked = BookmarkStore.all(for: bookUrl).contains { $0.id == id.id }
    }

    private func toggleBookmark() {
        let bookmark = bookmarkIdentity
        if isCurrentPageBookmarked {
            BookmarkStore.remove(bookmark)
        } else {
            BookmarkStore.add(bookmark)
        }
        isCurrentPageBookmarked.toggle()
    }

    private func jumpToBookmark(_ bookmark: BookBookmark) {
        guard bookmark.chapterIndex != viewModel.currentIndex else {
            pageIndex = min(max(bookmark.pageIndex, 0), max(pages.count - 1, 0))
            return
        }
        pendingJumpToPage = bookmark.pageIndex
        viewModel.openChapter(bookmark.chapterIndex)
    }

    // MARK: - Apple Books 式控制层

    private var chrome: some View {
        VStack(spacing: 0) {
            if showControls {
                LiquidGlassContainer(spacing: 12) {
                    ReaderTopBar(
                        title: viewModel.currentTitle,
                        accent: textColor,
                        isBookmarked: isCurrentPageBookmarked,
                        onBack: { dismiss() },
                        onTitle: { showToc = true },
                        onSearch: { showSearch = true },
                        onBookmark: { toggleBookmark() }
                    )
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity),
                    removal: .move(edge: .top).combined(with: .opacity)
                ))
            }
            Spacer(minLength: 0)
            if showControls {
                LiquidGlassContainer(spacing: 14) {
                    ReaderBottomBar(
                        pageText: "第 \(pageIndex + 1) 页 / 共 \(max(pages.count, 1)) 页",
                        accent: textColor,
                        isSpeaking: speech.isSpeaking,
                        onToc: { showToc = true },
                        onTts: {
                            guard pageIndex < pages.count else { return }
                            speech.toggle(pages[pageIndex].plainText)
                        },
                        onAa: { showSettings = true }
                    )
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .move(edge: .bottom).combined(with: .opacity)
                ))
            } else {
                // 沉浸态：仅保留角落小页码。
                Text("\(pageIndex + 1) / \(max(pages.count, 1))")
                    .font(.caption2)
                    .foregroundStyle(textColor.opacity(0.45))
                    .padding(.bottom, 10)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .animation(.spring(response: 0.35, dampingFraction: 0.85, blendDuration: 0.1), value: showControls)
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
        pendingJumpToPage = nil
        pageIndex = 0
        viewModel.nextChapter()
        return true
    }

    private func goPrevPage() {
        if pageIndex > 0 {
            pageIndex -= 1
        } else if viewModel.hasPreviousChapter {
            pendingJumpToLastPage = true
            pendingJumpToPage = nil
            viewModel.prevChapter()
        } else {
            pendingJumpToLastPage = false
        }
    }

    // MARK: - 分页

    private func repaginate(key: String, pageSize: CGSize) async {
        guard !viewModel.currentContent.isEmpty else {
            pages = []; pendingJumpToPage = nil; pendingJumpToLastPage = false; paginatedForKey = key; return
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
            pendingJumpToPage = nil
            pendingJumpToLastPage = false
            paginatedForKey = key
            return
        }
        pages = result
        if let jump = pendingJumpToPage {
            // 书签跳页：新章分页完成后落到指定页。
            pageIndex = min(max(jump, 0), result.count - 1)
            pendingJumpToPage = nil
        } else if pendingJumpToLastPage {
            pageIndex = max(0, result.count - 1)
            pendingJumpToLastPage = false
        } else if pageIndex >= result.count {
            pageIndex = 0
        }
        paginatedForKey = key
    }
}