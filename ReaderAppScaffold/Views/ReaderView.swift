import SwiftUI
import SwiftData
import UIKit
import AVFoundation

/// 阅读器：UIPageViewController 稳定翻页 + CoreText 分页 + Apple Books 式控制层。
///
/// 控制层架构（重构后）：
/// - 顶栏：返回 · 书名（点按开目录）· 搜索 / 书签
/// - 底栏：目录 · 页码 · TTS / Aa 排版
/// - 底部细进度线：全书进度，始终可见、不拦截触摸
/// 点击分区：左 24% 上一页，右 24% 下一页，中间唤出/收起控制层。
/// 控制外观统一来自 ReaderChrome，与本地 TXT 阅读器共用。
struct ReaderView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: ReaderViewModel
    let bookUrl: String
    let bookName: String
    let bookAuthor: String
    let coverURL: String

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
    // 段评相关
    @State private var showReviewList = false
    @State private var reviewSheetDetent: PresentationDetent = .fraction(0.65)
    @State private var reviewBrowserDetent: PresentationDetent = .fraction(0.65)
    @State private var selectedParagraphIndex = 0
    @State private var selectedParagraphText = ""
    @State private var selectedReviewURL: String? = nil
    @State private var reviewCounts: [Int: Int] = [:]
    @State private var browserDestination: BrowserDestination?
    /// 有段评弹层（列表或网页）正在展示时，点击正文任意处收起它。
    @State private var isReviewPresented = false

    init(
        viewModel: ReaderViewModel,
        bookUrl: String,
        bookName: String,
        bookAuthor: String = "",
        coverURL: String = ""
    ) {
        self.viewModel = viewModel
        self.bookUrl = bookUrl
        self.bookName = bookName
        self.bookAuthor = bookAuthor
        self.coverURL = coverURL
    }

    private var textColor: Color { config.currentTheme.textColor }

    /// 正文指纹：长度 + 首尾采样。O(1) 而非整章 O(n) hashValue——
    /// body 每次求值（包括每次翻页）都会走到这里，整章哈希是隐形的大头。
    private func contentFingerprint(_ text: String) -> String {
        let head = text.prefix(32)
        let tail = text.suffix(32)
        return "\(text.count)-\(head)-\(tail)"
    }

    /// 全书进度：章序号 + 页内占比 / 总章数（驱动底部细进度线）。
    private var bookProgress: Double {
        guard viewModel.chapters.count > 1 else { return 0 }
        let inChapter = pages.isEmpty ? 0 : min(max(Double(pageIndex + 1) / Double(pages.count), 0), 1)
        return (Double(viewModel.currentIndex) + inChapter) / Double(viewModel.chapters.count)
    }

    var body: some View {
        GeometryReader { geo in
            // 全屏沉浸：分页尺寸按整块屏幕计算（含状态栏与 Home 指示条区域），
            // 翻页视图通过 ignoresSafeArea 铺满全屏，翻页效果覆盖到最顶和最底。
            let fullWidth = geo.size.width + geo.safeAreaInsets.leading + geo.safeAreaInsets.trailing
            let fullHeight = geo.size.height + geo.safeAreaInsets.top + geo.safeAreaInsets.bottom
            let pageSize = CGSize(
                width: max(fullWidth - config.paddingH * 2, 1),
                height: max(fullHeight - config.paddingTop - config.paddingBottom, 1)
            )
            let contentIdentity = contentFingerprint(viewModel.currentContent)
            let markerKey = viewModel.currentReviewMarkers
                .map { "\($0.id):\($0.paragraphIndex):\($0.source):\($0.count):\($0.action ?? "")" }
                .joined(separator: ",")
            let reviewKey = reviewCounts.isEmpty
                ? "0"
                : reviewCounts.keys.sorted().map { "\($0)=\(reviewCounts[$0] ?? 0)" }.joined(separator: ",")
            let paginationKey = [
                contentIdentity, // 结构化正文身份：不再对长正文做 O(n) hash
                "ff\(config.fontFamily)", // 字体族（衬线/无衬线）参与分页
                "f\(Int(config.fontSize))",
                "ls\(Int(config.lineSpacing))",
                "ps\(Int(config.paragraphSpacing))",
                "in\(config.paragraphIndent)",
                "b\(config.bold ? 1 : 0)",
                "pg\(Int(pageSize.width))x\(Int(pageSize.height))",
                "mk\(markerKey)",
                "rv\(reviewKey)",
                "ch\(viewModel.currentIndex)"
            ].joined(separator: "|")

            ZStack {
                config.currentTheme.background.ignoresSafeArea()

                if paginatedForKey == paginationKey, !pages.isEmpty {
                    PageReaderViewRepresentable(
                        pages: pages,
                        config: config,
                        currentIndex: $pageIndex,
                        legacyReviewEnabled: viewModel.reviewEnabled,
                        onReviewTap: { paragraphIndex in
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            selectedReviewURL = nil
                            presentReview(for: paragraphIndex)
                        },
                        reviewCounts: reviewCounts,
                        onInlineReviewTap: { markerID in
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            handleInlineReviewTap(markerID)
                        },
                        onOutsideTap: { location in
                            // 点击正文除段评入口外的任意位置：收起段评弹层，
                            // 没有弹层时维持原有的翻页/呼出菜单逻辑。
                            guard isReviewPresented else {
                                handlePageTap(location, width: geo.size.width)
                                return
                            }
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            showReviewList = false
                            browserDestination = nil
                        }
                    )
                    // 主题/夜间/动画档位已交给 refreshAppearance 热刷新，
                    // 不再通过 .id 强制重建整个 UIKit 容器（消除断崖闪烁）。
                    // 全屏铺满：忽略安全区，翻页折角/滑动效果延伸到
                    // 状态栏顶部与 Home 指示条底部。
                    .ignoresSafeArea(.container, edges: .all)
                    .contentShape(Rectangle())
                    // 主题/夜间切换走 refreshAppearance 热刷新；
                    // 只有翻页模式切换才通过 identity 重建容器。
                    .id(config.pageAnim)
                    // 点击分发由 PageContentView 内部手势统一处理（段评入口 /
                    // 外点回调），这里不再叠加 onTapGesture 避免双重触发。
                } else if viewModel.isLoadingContent || viewModel.isLoadingToc {
                    ProgressView()
                } else if let err = viewModel.errorMessage {
                    Text(err).foregroundStyle(.red).multilineTextAlignment(.center).padding()
                } else {
                    ProgressView()
                }

                chrome
                    .zIndex(20)
            }
            .task(id: paginationKey) {
                await repaginate(content: viewModel.currentContent, pageSize: pageSize, key: paginationKey)
            }
            .task(id: autoRead) {
                guard autoRead else { return }
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
        .statusBarHidden(!showControls)
        .persistentSystemOverlays(.hidden)
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
                    TocSheet.TocEntry(index: $0.offset, name: $0.element.name)
                },
                currentIndex: viewModel.currentIndex,
                onSelectChapter: { index in
                    Task { await viewModel.openChapter(at: index) }
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
        .sheet(isPresented: $showReviewList) {
            ReviewListView(
                paragraphText: selectedParagraphText,
                paragraphIndex: selectedParagraphIndex,
                onClose: { showReviewList = false },
                fetchReviews: { paragraphIndex, paragraphText in
                    await viewModel.fetchReviews(
                        paragraphIndex: paragraphIndex,
                        paragraphText: paragraphText,
                        markerSource: selectedReviewURL
                    )
                }
            )
            .presentationDetents(
                [.fraction(0.65), .fraction(0.90)],
                selection: $reviewSheetDetent
            )
            .presentationDragIndicator(.visible)
            .presentationContentInteraction(.scrolls)
            .presentationBackgroundInteraction(.enabled(upThrough: .fraction(0.65)))
            .onAppear { reviewSheetDetent = .fraction(0.65) }
        }
        .onChange(of: showReviewList) { _, shown in isReviewPresented = shown || browserDestination != nil }
        .onChange(of: browserDestination) { _, dest in isReviewPresented = showReviewList || dest != nil }
        .sheet(item: $browserDestination) { destination in
            if destination.isReview {
                InAppBrowserView(destination: destination)
                    .presentationDetents(
                        [.fraction(0.65), .fraction(0.90)],
                        selection: $reviewBrowserDetent
                    )
                    .presentationDragIndicator(.visible)
                    .presentationContentInteraction(.scrolls)
                    .presentationBackgroundInteraction(.enabled(upThrough: .fraction(0.65)))
                    .onAppear { reviewBrowserDetent = .fraction(0.65) }
            } else {
                InAppBrowserView(destination: destination)
            }
        }
        .onChange(of: viewModel.currentIndex) { _, _ in
            // 切章后总是从新章第一页开始；只有向前切章时才由
            // pendingJumpToLastPage 把页码恢复到上一章末页。
            if !pendingJumpToLastPage { pageIndex = 0 }
            saveProgress()
            refreshBookmarkState()
            if speech.isSpeaking, pageIndex < pages.count { speech.speak(pages[pageIndex].plainText) }
        }
        .onChange(of: pageIndex) { _, _ in
            refreshBookmarkState()
            if speech.isSpeaking, pageIndex < pages.count { speech.speak(pages[pageIndex].plainText) }
        }
    }

    // MARK: - 段评

    private func presentReview(for paragraphIndex: Int) {
        let paragraphs = viewModel.currentContent.components(separatedBy: "\n")
        selectedParagraphIndex = max(0, paragraphIndex)
        selectedParagraphText = paragraphIndex < paragraphs.count ? paragraphs[paragraphIndex] : ""
        showReviewList = true
    }

    private func handleInlineReviewTap(_ markerID: Int) {
        // 有 click/js 时执行书源动作（通常会调用 java.showBrowser）；
        // 没有动作时直接打开段评列表，避免段评图看起来“点了没反应”。
        guard let marker = viewModel.currentReviewMarkers.first(where: { $0.id == markerID }) else { return }
        if marker.action?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            viewModel.executeInlineReviewAction(markerID: markerID) { url, title in
                guard let destination = BrowserDestination(urlString: url, title: title, isReview: true) else { return }
                DispatchQueue.main.async { browserDestination = destination }
            }
        } else if let destination = BrowserDestination(urlString: marker.source, title: marker.title, isReview: true) {
            browserDestination = destination
        } else {
            selectedReviewURL = marker.source
            presentReview(for: marker.paragraphIndex)
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

    // MARK: - 书签（Apple Books 式：顶栏书签按钮 + 目录面板书签列表）

    private var bookmarkIdentity: BookBookmark {
        BookBookmark(
            bookUrl: bookUrl,
            chapterIndex: viewModel.currentIndex,
            pageIndex: pageIndex,
            label: (viewModel.currentChapterTitle ?? bookName) + " · 第 \(pageIndex + 1) 页",
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
            // 同章：分页结果不变，直接落页码；异章则等新章分页完成后再落。
            pageIndex = min(max(bookmark.pageIndex, 0), max(pages.count - 1, 0))
            return
        }
        pendingJumpToPage = bookmark.pageIndex
        Task { await viewModel.openChapter(at: bookmark.chapterIndex) }
    }

    // MARK: - Apple Books 式控制层

    private var chrome: some View {
        VStack(spacing: 0) {
            if showControls {
                LiquidGlassContainer(spacing: 12) {
                    ReaderTopBar(
                        title: viewModel.currentChapterTitle ?? bookName,
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
                // 沉浸态：仅保留角落小页码，不打扰阅读。
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
        Task { await viewModel.nextChapter() }
        return true
    }

    private func goPrevPage() {
        if pageIndex > 0 {
            pageIndex -= 1
        } else if viewModel.hasPreviousChapter {
            pendingJumpToLastPage = true
            pendingJumpToPage = nil
            Task { await viewModel.prevChapter() }
        } else {
            // 已经是第一章第一页，不保留一个无效的“跳到末页”意图。
            pendingJumpToLastPage = false
        }
    }

    // MARK: - 分页

    private func repaginate(content: String, pageSize: CGSize, key: String) async {
        guard !content.isEmpty else {
            pages = []
            pendingJumpToPage = nil
            pendingJumpToLastPage = false
            paginatedForKey = key
            return
        }

        // 单飞分页：同一时刻只有一个分页任务生效，旧任务自然作废，
        // 拖动字号/行距滑杆时不再并发竞争，也不阻塞主线程。
        let taskID = UUID()
        paginationTaskID = taskID

        let font = config.uiFont
        let badgeColor = UIColor.systemGray // 固定中性灰：明暗主题下同一张图，切换主题不需要重新分页
        let lSpacing = config.lineSpacing
        let pSpacing = config.paragraphSpacing
        let indent = config.indentPixels
        let alignment = config.coreTextAlignment
        let markers = viewModel.currentReviewMarkers
        let legacy = viewModel.reviewEnabled
        let counts = reviewCounts
        let chapterIndex = viewModel.currentIndex

        let result = await Task.detached(priority: .userInitiated) {
            ReaderPageComposer.compose(
                content: content,
                markers: markers,
                legacyReviewLinks: legacy,
                reviewCounts: counts,
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

        // 任务已被更新的一轮取代（如快速拖动滑杆），丢弃本次结果。
        guard taskID == paginationTaskID else { return }
        guard content == viewModel.currentContent, chapterIndex == viewModel.currentIndex else { return }

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

    // MARK: - 进度保存

    private func saveProgress() {
        let url = bookUrl
        let descriptor = FetchDescriptor<ShelfBook>(predicate: #Predicate { $0.bookUrl == url })
        if let book = try? context.fetch(descriptor).first {
            book.lastReadChapterIndex = viewModel.currentIndex
            book.lastReadChapterTitle = viewModel.currentChapterTitle
            book.lastReadAt = Date()
            book.totalChapters = viewModel.chapters.count
            try? context.save()
        }
    }
}