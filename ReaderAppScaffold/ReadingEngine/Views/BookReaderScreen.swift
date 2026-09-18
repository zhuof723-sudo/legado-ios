import SwiftUI
import SwiftData
import UIKit

/// 阅读页（TXT / EPUB / 在线书源统一入口）。
///
/// 架构分层：
/// - 本视图：控制层与状态编排（顶栏 / 底栏 / 面板 / TTS / 书签 / 进度）
/// - BookReaderViewModel：章节导航 + 分页编排 + 阅读位置
/// - ReaderPaginator：CoreText 分页（中文断行 / 两端对齐 / 首行缩进）
/// - BookPagedReaderRepresentable：仿真卷页 / 平移 / 无动画 三种翻页容器
///
/// 点击分区：左右各 24% 翻页，中间唤出控制层（ReaderTapZones）。
struct BookReaderScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var model: BookReaderViewModel

    @ObservedObject private var config = ReaderConfig.shared
    @StateObject private var speech = ReaderSpeechController()
    @AppStorage("reader.autoRead") private var autoRead = false

    @State private var showControls = false
    @State private var showSettings = false
    @State private var showToc = false
    @State private var showSearch = false
    @State private var isCurrentPageBookmarked = false

    // 段评（仅在线书源）
    @State private var showReviewList = false
    @State private var reviewSheetDetent: PresentationDetent = .fraction(0.65)
    @State private var reviewBrowserDetent: PresentationDetent = .fraction(0.65)
    @State private var selectedParagraphIndex = 0
    @State private var selectedParagraphText = ""
    @State private var selectedReviewURL: String?
    @State private var browserDestination: BrowserDestination?
    /// 有段评弹层展示时，点击正文任意处收起它。
    @State private var isReviewPresented = false

    init(source: BookReaderViewModel.BookSourceKind) {
        _model = State(initialValue: BookReaderViewModel(source: source))
    }

    private var textColor: Color { config.currentTheme.textColor }

    var body: some View {
        @Bindable var model = model

        GeometryReader { geo in
            // 全屏沉浸：分页尺寸按整块屏幕计算（含安全区），翻页铺满全屏。
            let fullWidth = geo.size.width + geo.safeAreaInsets.leading + geo.safeAreaInsets.trailing
            let fullHeight = geo.size.height + geo.safeAreaInsets.top + geo.safeAreaInsets.bottom
            let padH = CGFloat(config.paddingH)
            let padTop = CGFloat(config.paddingTop)
            let padBottom = CGFloat(config.paddingBottom)
            let contentOffset = CGPoint(x: padH, y: padTop)
            let contentSize = CGSize(
                width: max(fullWidth - padH * 2, 1),
                height: max(fullHeight - padTop - padBottom, 1)
            )
            let typography = ReaderTypography(
                font: config.uiFont,
                lineSpacing: config.lineSpacing,
                paragraphGap: config.paragraphSpacing,
                firstLineIndent: config.indentPixels,
                pageSize: contentSize
            )
            let paginationKey = BookReaderViewModel.paginationKey(
                contentFingerprint: ReaderDocumentBuilder.fingerprint(of: model.currentContent),
                markerKey: model.currentMarkerKey,
                chapterIndex: model.currentChapterIndex,
                typography: typography
            )

            ZStack {
                config.currentTheme.background.ignoresSafeArea()

                if !model.pages.isEmpty, model.pagesChapterIndex == model.currentChapterIndex {
                    BookPagedReaderRepresentable(
                        pages: model.pages,
                        config: config,
                        pageIndex: $model.pageIndex,
                        contentOffset: contentOffset,
                        contentSize: contentSize,
                        onZoneTap: { action in handleZoneTap(action) },
                        onLinkTap: { target in handleLinkTap(target) }
                    )
                    .ignoresSafeArea(.container, edges: .all)
                    // 翻页模式变化重建容器；主题/排版变化分别走热刷新与重排。
                    .id(config.turnStyle)
                } else if model.isLoading {
                    ProgressView()
                } else if let error = model.errorMessage {
                    Text(error).foregroundStyle(.red).multilineTextAlignment(.center).padding()
                } else {
                    ProgressView()
                }

                chrome
                    .zIndex(20)
            }
            .task(id: paginationKey) {
                await model.ensurePaginated(
                    key: paginationKey,
                    typography: typography,
                    badgeColor: .systemGray
                )
            }
            .task(id: autoRead) {
                guard autoRead else { return }
                for _ in 0..<1000 {
                    guard !Task.isCancelled else { break }
                    try? await Task.sleep(nanoseconds: UInt64(config.autoReadSpeed * 1_000_000_000))
                    guard !Task.isCancelled, autoRead else { break }
                    guard await model.advancePage(allowNextChapter: false) else { break }
                }
            }
        }
        .overlay(alignment: .bottom) {
            // Apple Books 式全书进度细线：贴底常显，不拦截触摸。
            ReaderProgressHairline(progress: model.bookProgress, accent: config.currentAccent)
        }
        .statusBarHidden(!showControls)
        .persistentSystemOverlays(.hidden)
        .preferredColorScheme(config.nightMode ? .dark : .light)
        .toolbar(.hidden, for: .tabBar)
        .onDisappear {
            speech.stop()
            model.saveProgress()
        }
        .sheet(isPresented: $showSettings) {
            ReaderAaPanel().presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showToc) {
            TocSheet(
                bookUrl: model.bookKey,
                entries: (0..<model.chapterCount).map {
                    TocSheet.TocEntry(index: $0, name: model.chapterTitle(at: $0))
                },
                currentIndex: model.currentChapterIndex,
                onSelectChapter: { index in
                    Task { await model.openChapter(index) }
                },
                onSelectBookmark: { bookmark in
                    Task { await model.jumpToBookmark(bookmark) }
                }
            )
            .presentationDetents([.large])
        }
        .sheet(isPresented: $showSearch) {
            ReaderChapterSearchView(text: model.currentContent)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showReviewList) {
            ReviewListView(
                paragraphText: selectedParagraphText,
                paragraphIndex: selectedParagraphIndex,
                onClose: { showReviewList = false },
                fetchReviews: { paragraphIndex, paragraphText in
                    try await model.fetchReviews(
                        paragraphIndex: paragraphIndex,
                        paragraphText: paragraphText,
                        markerSource: selectedReviewURL
                    )
                }
            )
            .presentationDetents([.fraction(0.65), .fraction(0.90)], selection: $reviewSheetDetent)
            .presentationDragIndicator(.visible)
            .presentationContentInteraction(.scrolls)
            .presentationBackgroundInteraction(.enabled(upThrough: .fraction(0.65)))
            .onAppear { reviewSheetDetent = .fraction(0.65) }
        }
        .sheet(item: $browserDestination) { destination in
            if destination.isReview {
                InAppBrowserView(destination: destination)
                    .presentationDetents([.fraction(0.65), .fraction(0.90)], selection: $reviewBrowserDetent)
                    .presentationDragIndicator(.visible)
                    .presentationContentInteraction(.scrolls)
                    .presentationBackgroundInteraction(.enabled(upThrough: .fraction(0.65)))
                    .onAppear { reviewBrowserDetent = .fraction(0.65) }
            } else {
                InAppBrowserView(destination: destination)
            }
        }
        .onChange(of: showReviewList) { _, shown in
            isReviewPresented = shown || browserDestination != nil
        }
        .onChange(of: browserDestination) { _, destination in
            isReviewPresented = showReviewList || destination != nil
        }
        .onChange(of: model.currentChapterIndex) { _, _ in
            refreshBookmarkState()
            saveProgress()
            continueSpeakingIfNeeded()
        }
        .onChange(of: model.pageIndex) { _, _ in
            refreshBookmarkState()
            continueSpeakingIfNeeded()
        }
    }

    // MARK: - 点击分发

    private func handleZoneTap(_ action: ReaderTapAction) {
        // 段评弹层展示中：点击正文任意处先收起弹层。
        guard !isReviewPresented else {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showReviewList = false
            browserDestination = nil
            return
        }
        switch action {
        case .previousPage:
            Task { await model.goPreviousPage() }
        case .nextPage:
            Task { await model.advancePage(allowNextChapter: true) }
        case .toggleControls:
            withAnimation(.easeInOut(duration: 0.2)) { showControls.toggle() }
        }
    }

    private func handleLinkTap(_ target: ReaderLinkTarget) {
        guard model.supportsReviews else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        switch target {
        case .legacyParagraph(let index):
            selectedReviewURL = nil
            presentReview(paragraphIndex: index)
        case .marker(let id):
            handleMarkerTap(id)
        }
    }

    // MARK: - 段评

    private func presentReview(paragraphIndex: Int) {
        let paragraphs = model.currentContent.components(separatedBy: "\n")
        selectedParagraphIndex = max(0, paragraphIndex)
        let raw = paragraphIndex < paragraphs.count ? paragraphs[paragraphIndex] : ""
        // 剔除段评占位符（PUA 区），引用框只显示人读的文字。
        selectedParagraphText = String(raw.filter {
            !$0.unicodeScalars.contains(where: { (0xE000...0xF8FF).contains($0.value) })
        })
        showReviewList = true
    }

    private func handleMarkerTap(_ markerID: Int) {
        guard let marker = model.marker(id: markerID) else { return }
        if marker.action?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            // 有 click/js：执行书源动作（通常会打开浏览器）。
            model.executeMarkerAction(id: markerID) { url, title in
                guard let destination = BrowserDestination(urlString: url, title: title, isReview: true) else { return }
                DispatchQueue.main.async { browserDestination = destination }
            }
        } else if let destination = BrowserDestination(urlString: marker.source, title: marker.title, isReview: true) {
            browserDestination = destination
        } else {
            selectedReviewURL = marker.source
            presentReview(paragraphIndex: marker.paragraphIndex)
        }
    }

    // MARK: - 书签

    private var bookmarkIdentity: BookBookmark {
        BookBookmark(
            bookUrl: model.bookKey,
            chapterIndex: model.currentChapterIndex,
            pageIndex: model.pageIndex,
            label: model.currentChapterTitle + " · 第 \(model.pageIndex + 1) 页",
            createdAt: Date()
        )
    }

    private func refreshBookmarkState() {
        let identity = bookmarkIdentity
        isCurrentPageBookmarked = BookmarkStore.all(for: model.bookKey).contains { $0.id == identity.id }
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

    // MARK: - 进度

    private func saveProgress() {
        model.saveProgress()
        // 在线书籍同时回写书架（章节号 / 章名 / 时间）。
        guard case .online(let viewModel, let bookUrl, _) = model.source else { return }
        let descriptor = FetchDescriptor<ShelfBook>(predicate: #Predicate { $0.bookUrl == bookUrl })
        if let book = try? context.fetch(descriptor).first {
            book.lastReadChapterIndex = viewModel.currentIndex
            book.lastReadChapterTitle = viewModel.currentChapterTitle
            book.lastReadAt = Date()
            book.totalChapters = viewModel.chapters.count
            try? context.save()
        }
    }

    // MARK: - TTS

    private func continueSpeakingIfNeeded() {
        guard speech.isSpeaking else { return }
        guard model.pages.indices.contains(model.pageIndex) else { return }
        speech.speak(model.pages[model.pageIndex].plainText)
    }

    // MARK: - Apple Books 式控制层

    private var chrome: some View {
        VStack(spacing: 0) {
            if showControls {
                LiquidGlassContainer(spacing: 12) {
                    ReaderTopBar(
                        title: model.currentChapterTitle,
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
                        pageText: "第 \(model.pageIndex + 1) 页 / 共 \(max(model.pages.count, 1)) 页",
                        accent: textColor,
                        isSpeaking: speech.isSpeaking,
                        onToc: { showToc = true },
                        onTts: {
                            guard model.pages.indices.contains(model.pageIndex) else { return }
                            speech.toggle(model.pages[model.pageIndex].plainText)
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
                Text("\(model.pageIndex + 1) / \(max(model.pages.count, 1))")
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
}
