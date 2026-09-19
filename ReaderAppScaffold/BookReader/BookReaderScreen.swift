import SwiftUI
import SwiftData
import UIKit

struct BookReaderScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var session: BookReaderSession
    @ObservedObject private var style = BookReaderStyle.shared

    @State private var showControls = false
    @State private var showReviews = false
    @State private var selectedParagraphIndex = 0
    @State private var selectedParagraphText = ""
    @State private var selectedReviewURL: String?
    @State private var browserDestination: BrowserDestination?

    init(source: BookReaderSession.Source) {
        _session = State(initialValue: BookReaderSession(source: source))
    }

    var body: some View {
        @Bindable var session = session
        GeometryReader { geometry in
            let padH = CGFloat(style.paddingH)
            let padTop = CGFloat(style.paddingTop)
            let padBottom = CGFloat(style.paddingBottom)
            let width = geometry.size.width + geometry.safeAreaInsets.leading + geometry.safeAreaInsets.trailing
            let height = geometry.size.height + geometry.safeAreaInsets.top + geometry.safeAreaInsets.bottom
            let contentOffset = CGPoint(x: padH, y: padTop)
            let contentSize = CGSize(width: max(width - padH * 2, 1), height: max(height - padTop - padBottom, 1))
            let layout = session.makeLayout(
                font: style.font,
                lineSpacing: style.lineSpacing,
                paragraphSpacing: style.paragraphSpacing,
                indent: style.firstLineIndent,
                titleSpacing: style.titleSpacing,
                size: contentSize
            )
            let key = "\(BookReaderDocumentBuilder.fingerprint(session.content))|\(layout.signature)|\(session.markers.map { "\($0.id):\($0.paragraphIndex):\($0.count)" }.joined(separator: ","))|\(session.chapterIndex)"
            let canRender = style.mode == .scroll ? session.document != nil : (!session.pages.isEmpty && session.chapterForPages == session.chapterIndex)

            ZStack {
                style.theme.background.ignoresSafeArea()
                if canRender {
                    BookReaderModeView(
                        mode: style.mode,
                        pages: session.pages,
                        document: session.document,
                        style: style,
                        pageIndex: $session.pageIndex,
                        contentOffset: contentOffset,
                        contentSize: contentSize,
                        onTurn: handleTurn,
                        onLink: handleLink
                    )
                    .id(style.mode)
                    .ignoresSafeArea(.container, edges: .all)
                } else if session.loading || session.content.isEmpty {
                    ProgressView()
                } else if let error = session.error {
                    Text(error).foregroundStyle(.red).multilineTextAlignment(.center).padding(24)
                } else {
                    ProgressView()
                }

                if showControls {
                    controls
                        .zIndex(10)
                }
            }
            .task(id: key + "|mode=" + style.mode.rawValue) {
                if style.mode == .scroll {
                    session.ensureDocument(style: style)
                } else {
                    await session.ensurePages(key: key, layout: layout, style: style)
                }
            }
        }
        .statusBarHidden(!showControls)
        .preferredColorScheme(style.nightMode ? .dark : .light)
        .toolbar(.hidden, for: .tabBar)
        .overlay(alignment: .bottom) {
            readerStatusBar
        }
        .onChange(of: session.chapterIndex) { _, _ in session.savePosition() }
        .onChange(of: session.pageIndex) { _, _ in session.savePosition() }
        .onDisappear { saveProgress() }
        .sheet(isPresented: $showReviews) {
            ReviewListView(
                paragraphText: selectedParagraphText,
                paragraphIndex: selectedParagraphIndex,
                onClose: { showReviews = false },
                fetchReviews: { index, text in
                    try await session.fetchReviews(paragraphIndex: index, paragraphText: text, markerSource: selectedReviewURL)
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

    private var readerStatusBar: some View {
        HStack {
            Text(clockText)
                .font(.caption2.monospacedDigit())
            Spacer()
            if style.mode != .scroll {
                Text("\(session.pageIndex + 1)/\(max(session.pages.count, 1))")
                    .font(.caption2.monospacedDigit())
            } else {
                Text("\(Int(session.progress * 100))%")
                    .font(.caption2.monospacedDigit())
            }
            Spacer()
            HStack(spacing: 4) {
                Text("\(Int(batteryLevel * 100))%")
                    .font(.caption2.monospacedDigit())
                Image(systemName: batteryIcon)
                    .font(.caption2)
            }
        }
        .foregroundStyle(style.theme.text.opacity(showControls ? 0.55 : 0.4))
        .padding(.horizontal, max(CGFloat(style.paddingH), 18))
        .padding(.bottom, 2)
        .allowsHitTesting(false)
    }

    private var clockText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: Date())
    }

    private var batteryLevel: Double {
        UIDevice.current.isBatteryMonitoringEnabled = true
        let level = UIDevice.current.batteryLevel
        guard level >= 0 else { return 1 }
        return Double(level)
    }

    private var batteryIcon: String {
        let percent = batteryLevel
        if percent >= 0.85 { return "battery.100" }
        if percent >= 0.6 { return "battery.75" }
        if percent >= 0.35 { return "battery.50" }
        if percent >= 0.15 { return "battery.25" }
        return "battery.0"
    }

    private var controls: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.bookTitle).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text(session.chapterTitle).font(.caption2).lineLimit(1).opacity(0.7)
                }
                Spacer()
                if style.mode != .scroll {
                    Text("\(session.pageIndex + 1) / \(max(session.pages.count, 1))")
                        .font(.caption.monospacedDigit())
                        .opacity(0.75)
                }
            }
            .foregroundStyle(style.theme.text)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)

            HStack(spacing: 8) {
                ForEach(BookReaderTurnMode.allCases) { mode in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { style.turnMode = mode.rawValue }
                    } label: {
                        Label(mode.title, systemImage: mode.icon)
                            .font(.caption2)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(style.mode == mode ? style.theme.text.opacity(0.12) : .clear)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
            .foregroundStyle(style.theme.text)
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
            .background(.ultraThinMaterial)
            Spacer()
        }
        .ignoresSafeArea(edges: .top)
    }

    private func handleTurn(_ intent: BookReaderTurnIntent) {
        switch intent {
        case .previous:
            Task { await session.previousPage() }
        case .next:
            Task { await session.nextPage(allowNextChapter: true) }
        case .center:
            withAnimation(.easeInOut(duration: 0.16)) { showControls.toggle() }
        }
    }

    private func handleLink(_ link: BookReaderLink) {
        guard session.reviewsEnabled else { return }
        switch link {
        case .paragraph(let index):
            selectedReviewURL = nil
            presentReview(index)
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
                presentReview(marker.paragraphIndex)
            }
        }
    }

    private func presentReview(_ index: Int) {
        let paragraphs = session.content.components(separatedBy: "\n")
        selectedParagraphIndex = max(index, 0)
        let raw = paragraphs.indices.contains(index) ? paragraphs[index] : ""
        selectedParagraphText = String(raw.filter { !$0.unicodeScalars.contains { (0xE000...0xF8FF).contains($0.value) } })
        showReviews = true
    }

    private func saveProgress() {
        session.savePosition()
        guard case .online(let source, let url, _) = session.source else { return }
        let descriptor = FetchDescriptor<ShelfBook>(predicate: #Predicate { $0.bookUrl == url })
        if let book = try? modelContext.fetch(descriptor).first {
            book.lastReadChapterIndex = source.currentChapterIndex
            book.lastReadChapterTitle = source.chapters.indices.contains(source.currentChapterIndex) ? source.chapters[source.currentChapterIndex].name : nil
            book.lastReadAt = Date()
            book.totalChapters = source.chapters.count
            try? modelContext.save()
        }
    }
}
