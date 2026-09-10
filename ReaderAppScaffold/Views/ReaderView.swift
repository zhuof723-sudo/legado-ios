import SwiftUI
import SwiftData
import UIKit
import AVFoundation

/// 阅读器：UIPageViewController 稳定翻页 + CoreText 分页 + 液态玻璃控制层
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

    @State private var pages: [String] = []
    @State private var paginatedForKey = ""
    @State private var pageIndex = 0
    @State private var pendingJumpToLastPage = false
    @State private var showControls = false
    @State private var showSettings = false
    @State private var showToc = false
    // 段评相关
    @State private var showReviewList = false
    @State private var selectedParagraphIndex = 0
    @State private var selectedParagraphText = ""
    @State private var selectedReviewURL: String? = nil
    @State private var reviewCounts: [Int: Int] = [:]
    @State private var browserDestination: BrowserDestination?

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

    private var brightnessBinding: Binding<Double> {
        Binding(
            get: { Double(UIScreen.main.brightness) },
            set: { UIScreen.main.brightness = CGFloat($0) }
        )
    }

    var body: some View {
        GeometryReader { geo in
            let pageSize = CGSize(
                width: max(geo.size.width - config.paddingH * 2, 1),
                height: max(geo.size.height - config.paddingTop - config.paddingBottom, 1)
            )
            let paginationKey = "\(viewModel.currentContent.hashValue)|\(Int(config.fontSize))|\(config.lineSpacing)|\(config.bold)|\(config.paragraphSpacing)|\(config.paragraphIndent)|"
                + "\(Int(pageSize.width))x\(Int(pageSize.height))|\(viewModel.currentIndex)"

            ZStack {
                config.currentTheme.background.ignoresSafeArea()

                if paginatedForKey == paginationKey, !pages.isEmpty {
                    PageReaderViewRepresentable(
                        pages: pages,
                        config: config,
                        currentIndex: $pageIndex,
                        reviewEnabled: viewModel.reviewEnabled,
                        onReviewTap: { paragraphIndex in
                            selectedReviewURL = nil
                            presentReview(for: paragraphIndex)
                        },
                        reviewCounts: reviewCounts,
                        inlineReviewMarkers: viewModel.currentReviewMarkers,
                        onInlineReviewTap: { markerID in
                            handleInlineReviewTap(markerID)
                        }
                    )
                    .id("\(config.pageAnim)_\(config.themeId)_\(config.nightMode)_reviews\(viewModel.currentReviewMarkers.map { "\($0.id):\($0.paragraphIndex):\($0.source)" }.joined(separator: "|").hashValue)")
                    // 页面边距由 PageContentView 内部承担；这样每个被翻页
                    // transform 的页面包含完整背景和文字，不会留下固定的父背景。
                    .contentShape(Rectangle())
                    .onTapGesture(count: 1, coordinateSpace: .local) { location in
                        handlePageTap(location, width: geo.size.width)
                    }
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
        .statusBarHidden(false)
        .preferredColorScheme(config.nightMode ? .dark : .light)
        .toolbar(.hidden, for: .tabBar)
        .onDisappear { speech.stop() }
        .sheet(isPresented: $showSettings) {
            ReaderSettingsPanel().presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showToc) {
            TocSheet(bookUrl: bookUrl, viewModel: viewModel).presentationDetents([.large])
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
        }
        .sheet(item: $browserDestination) { destination in
            InAppBrowserView(destination: destination)
        }
        .onChange(of: viewModel.currentIndex) { _, _ in
            // 切章后总是从新章第一页开始；只有向前切章时才由
            // pendingJumpToLastPage 把页码恢复到上一章末页。
            if !pendingJumpToLastPage { pageIndex = 0 }
            saveProgress()
            if speech.isSpeaking, pageIndex < pages.count { speech.speak(pages[pageIndex]) }
        }
        .onChange(of: pageIndex) { _, _ in
            if speech.isSpeaking, pageIndex < pages.count { speech.speak(pages[pageIndex]) }
        }
    }

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
                guard let destination = BrowserDestination(urlString: url, title: title) else { return }
                DispatchQueue.main.async { browserDestination = destination }
            }
        } else if let destination = BrowserDestination(urlString: marker.source, title: marker.title) {
            browserDestination = destination
        } else {
            selectedReviewURL = marker.source
            presentReview(for: marker.paragraphIndex)
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

    // MARK: - 沉浸式控制层

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
                    Text(viewModel.currentChapterTitle ?? "")
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
            Text(viewModel.currentChapterTitle ?? bookName)
                .font(.subheadline.bold())
                .foregroundStyle(textColor)
                .lineLimit(1)
            Spacer(minLength: 8)
            Menu {
                Button { } label: { Label("分享", systemImage: "square.and.arrow.up") }
                Button { } label: { Label("书源详情", systemImage: "info.circle") }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(textColor)
                    .frame(width: 36, height: 36)
                    .glassCircle()
            }
        }
    }

    private var immersiveBottomPanel: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "sun.min")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                Slider(value: brightnessBinding, in: 0.05...1)
                    .tint(Theme.accent)
                Image(systemName: "sun.max.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }

            HStack {
                Button {
                    pendingJumpToLastPage = true
                    Task { await viewModel.prevChapter() }
                } label: {
                    Text("上一章").font(.footnote)
                }
                .disabled(!viewModel.hasPreviousChapter)
                Spacer()
                Text("\(pageIndex + 1) / \(max(pages.count, 1))")
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Button {
                    pendingJumpToLastPage = false
                    pageIndex = 0
                    Task { await viewModel.nextChapter() }
                } label: {
                    Text("下一章").font(.footnote)
                }
                .disabled(!viewModel.hasNextChapter)
            }
            .foregroundStyle(.primary)

            HStack {
                immersiveToolButton("list.bullet", "目录") { showToc = true }
                Spacer()
                immersiveToolButton(speech.isSpeaking ? "headphones.circle.fill" : "headphones", "TTS") {
                    guard pageIndex < pages.count else { return }
                    speech.toggle(pages[pageIndex])
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
        Task { await viewModel.nextChapter() }
        return true
    }

    private func goPrevPage() {
        if pageIndex > 0 {
            pageIndex -= 1
        } else if viewModel.hasPreviousChapter {
            pendingJumpToLastPage = true
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
            paginatedForKey = key
            return
        }
        let font = config.uiFont
        let lSpacing = config.lineSpacing
        let pSpacing = config.paragraphSpacing
        let indent = config.indentPixels
        let alignment = config.coreTextAlignment

        let result = await Task.detached(priority: .userInitiated) {
            TextPaginator.paginate(
                text: content,
                font: font,
                lineSpacing: lSpacing,
                paragraphSpacing: pSpacing,
                firstLineIndent: indent,
                alignment: alignment,
                pageSize: pageSize
            )
        }.value

        guard !Task.isCancelled else { return }
        guard content == viewModel.currentContent else { return }
        pages = result
        if pendingJumpToLastPage {
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
