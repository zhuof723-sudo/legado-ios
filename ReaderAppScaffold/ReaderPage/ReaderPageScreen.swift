import SwiftUI
import SwiftData
import UIKit

/// 全新的正文阅读页。
///
/// 阅读页只保留两类交互：
/// - CoreText 页面排版与段评链接
/// - UIPageViewController.pageCurl 仿真翻页
///
/// 其余旧阅读功能（平移/无动画、目录面板、书签、TTS、搜索、旧 Aa 面板）
/// 不再属于正文页面。
struct ReaderPageScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var session: ReaderPageSession
    @ObservedObject private var style = ReaderPageStyle.shared

    @State private var showControls = false
    @State private var showReviews = false
    @State private var selectedParagraphIndex = 0
    @State private var selectedParagraphText = ""
    @State private var selectedReviewURL: String?
    @State private var browserDestination: BrowserDestination?

    init(source: ReaderPageSession.Source) {
        _session = State(initialValue: ReaderPageSession(source: source))
    }

    var body: some View {
        @Bindable var session = session

        GeometryReader { geometry in
            let horizontal = CGFloat(style.paddingH)
            let top = CGFloat(style.paddingTop)
            let bottom = CGFloat(style.paddingBottom)
            let width = geometry.size.width + geometry.safeAreaInsets.leading + geometry.safeAreaInsets.trailing
            let height = geometry.size.height + geometry.safeAreaInsets.top + geometry.safeAreaInsets.bottom
            let contentOffset = CGPoint(x: horizontal, y: top)
            let contentSize = CGSize(
                width: max(width - horizontal * 2, 1),
                height: max(height - top - bottom, 1)
            )
            let layout = ReaderPageLayout(
                font: style.uiFont,
                lineSpacing: style.lineSpacing,
                paragraphSpacing: style.paragraphSpacing,
                firstLineIndent: style.firstLineIndent,
                pageSize: contentSize
            )
            let key = ReaderPageSession.key(
                content: session.currentContent,
                markers: session.markers,
                chapter: session.currentChapterIndex,
                layout: layout
            )

            ZStack {
                style.theme.background.ignoresSafeArea()

                if !session.pages.isEmpty, session.pagesChapterIndex == session.currentChapterIndex {
                    ReaderPageCurlView(
                        pages: session.pages,
                        style: style,
                        pageIndex: $session.pageIndex,
                        contentOffset: contentOffset,
                        contentSize: contentSize,
                        onTap: handlePageTap,
                        onLink: handlePageLink
                    )
                    .ignoresSafeArea(.container, edges: .all)
                } else if session.isLoading {
                    ProgressView()
                } else if let error = session.errorMessage {
                    Text(error)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(24)
                } else {
                    ProgressView()
                }

                if showControls {
                    controls
                        .zIndex(10)
                }
            }
            .task(id: key) {
                await session.ensurePages(key: key, layout: layout)
            }
        }
        .statusBarHidden(!showControls)
        .preferredColorScheme(style.nightMode ? .dark : .light)
        .toolbar(.hidden, for: .tabBar)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(style.theme.text.opacity(0.18))
                .frame(height: 2)
                .overlay(alignment: .leading) {
                    GeometryReader { geometry in
                        Rectangle()
                            .fill(style.theme.text.opacity(0.75))
                            .frame(width: geometry.size.width * session.progress)
                    }
                }
                .allowsHitTesting(false)
        }
        .onChange(of: session.currentChapterIndex) { _, _ in saveProgress() }
        .onChange(of: session.pageIndex) { _, _ in saveProgress() }
        .onDisappear { saveProgress() }
        .sheet(isPresented: $showReviews) {
            ReviewListView(
                paragraphText: selectedParagraphText,
                paragraphIndex: selectedParagraphIndex,
                onClose: { showReviews = false },
                fetchReviews: { paragraphIndex, paragraphText in
                    try await session.fetchReviews(
                        paragraphIndex: paragraphIndex,
                        paragraphText: paragraphText,
                        markerSource: selectedReviewURL
                    )
                }
            )
            .presentationDetents([.fraction(0.65), .fraction(0.90)])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $browserDestination) { destination in
            InAppBrowserView(destination: destination)
                .presentationDetents([.fraction(0.65), .fraction(0.90)])
                .presentationDragIndicator(.visible)
        }
    }

    private var controls: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 2) {
                    Text(session.bookTitle)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(session.currentChapterTitle)
                        .font(.caption2)
                        .lineLimit(1)
                        .opacity(0.7)
                }
                Spacer()
                Text("\(session.pageIndex + 1) / \(max(session.pages.count, 1))")
                    .font(.caption.monospacedDigit())
                    .opacity(0.75)
            }
            .foregroundStyle(style.theme.text)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
            Spacer()
        }
        .ignoresSafeArea(edges: .top)
    }

    private func handlePageTap(_ tap: ReaderPageTap) {
        switch tap {
        case .previous:
            Task { await session.previousPage() }
        case .next:
            Task { await session.nextPage(allowNextChapter: true) }
        case .center:
            withAnimation(.easeInOut(duration: 0.16)) { showControls.toggle() }
        }
    }

    private func handlePageLink(_ link: ReaderPageLink) {
        guard session.supportsReviews else { return }
        switch link {
        case .paragraph(let index):
            selectedReviewURL = nil
            presentReview(index: index)
        case .marker(let id):
            guard let marker = session.marker(id: id) else { return }
            if marker.action?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                session.executeMarkerAction(id: id) { url, title in
                    guard let destination = BrowserDestination(urlString: url, title: title, isReview: true) else { return }
                    DispatchQueue.main.async { browserDestination = destination }
                }
            } else if let destination = BrowserDestination(urlString: marker.source, title: marker.title, isReview: true) {
                browserDestination = destination
            } else {
                selectedReviewURL = marker.source
                presentReview(index: marker.paragraphIndex)
            }
        }
    }

    private func presentReview(index: Int) {
        let paragraphs = session.currentContent.components(separatedBy: "\n")
        selectedParagraphIndex = max(index, 0)
        let raw = paragraphs.indices.contains(index) ? paragraphs[index] : ""
        selectedParagraphText = String(raw.filter {
            !$0.unicodeScalars.contains { (0xE000...0xF8FF).contains($0.value) }
        })
        showReviews = true
    }

    private func saveProgress() {
        session.savePosition()
        guard case .online(let source, let bookURL, _) = session.source else { return }
        let descriptor = FetchDescriptor<ShelfBook>(predicate: #Predicate { $0.bookUrl == bookURL })
        if let book = try? context.fetch(descriptor).first {
            book.lastReadChapterIndex = source.currentChapterIndex
            book.lastReadChapterTitle = source.chapters.indices.contains(source.currentChapterIndex)
                ? source.chapters[source.currentChapterIndex].name
                : nil
            book.lastReadAt = Date()
            book.totalChapters = source.chapters.count
            try? context.save()
        }
    }
}
