import SwiftUI
import UIKit

/// 本地 TXT 阅读器：复用 TextPaginator 真分页，支持左右滑动 + 点击分区翻页
struct LocalReaderView: View {
    @Environment(\.dismiss) private var dismiss
    let bookName: String
    @Bindable var viewModel: TxtReaderViewModel

    @AppStorage("reader.fontSize") private var fontSize: Double = 18
    @State private var pages: [String] = []
    @State private var paginatedForKey = ""
    @State private var pageIndex = 0
    @State private var showControls = false
    @State private var showToc = false
    @State private var pageSizeState: CGSize = .zero

    private let hPadding: CGFloat = 20
    private let tPadding: CGFloat = 56
    private let bPadding: CGFloat = 44

    init(book: LocalBook) {
        self.bookName = book.name
        self._viewModel = Bindable(TxtReaderViewModel(book: book))
    }

    var body: some View {
        GeometryReader { geo in
            let pageSize = CGSize(
                width: max(geo.size.width - hPadding * 2, 1),
                height: max(geo.size.height - tPadding - bPadding, 1)
            )
            let key = "\(viewModel.currentContent.hashValue)|\(Int(fontSize))|\(Int(pageSize.width))x\(Int(pageSize.height))|\(viewModel.currentIndex)"

            ZStack {
                Theme.readerBackgrounds[1].ignoresSafeArea()
                content(pageSize: pageSize, key: key)
                tapZones
                chrome
            }
            .onAppear { pageSizeState = pageSize }
            .task(id: key) {
                pageSizeState = pageSize
                await repaginate(key: key, pageSize: pageSize)
            }
        }
        .statusBarHidden(!showControls)
        .sheet(isPresented: $showToc) {
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
                                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(Theme.accent)
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
    }

    @ViewBuilder
    private func content(pageSize: CGSize, key: String) -> some View {
        if paginatedForKey == key, !pages.isEmpty {
            TabView(selection: $pageIndex) {
                ForEach(pages.indices, id: \.self) { i in
                    Text(pages[i])
                        .font(.system(size: fontSize))
                        .lineSpacing(8)
                        .foregroundStyle(Theme.readerTextColors[1])
                        .frame(width: pageSize.width, height: pageSize.height, alignment: .topLeading)
                        .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        } else {
            ProgressView()
        }
    }

    private var tapZones: some View {
        HStack(spacing: 0) {
            Color.clear.onTapGesture { prevPage() }
            Color.clear.onTapGesture { withAnimation { showControls.toggle() } }
            Color.clear.onTapGesture { nextPage() }
        }
        .contentShape(Rectangle())
    }

    private var chrome: some View {
        VStack(spacing: 0) {
            if showControls {
                HStack(spacing: 12) {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold))
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(Color.white.opacity(0.7)))
                    }
                    Text(viewModel.currentTitle).font(.subheadline.bold()).lineLimit(1)
                    Spacer()
                }
                .padding(10)
                .glassCard(RoundedRectangle(cornerRadius: 16))
            }
            Spacer(minLength: 0)
            if showControls {
                VStack(alignment: .leading, spacing: 10) {
                    Slider(
                        value: Binding(get: { Double(min(pageIndex, max(pages.count - 1, 0))) },
                                       set: { pageIndex = Int($0) }),
                        in: 0...Double(max(pages.count - 1, 1))
                    )
                    .tint(Theme.accent)
                    HStack {
                        Button { viewModel.prevChapter() } label: { Label("上一章", systemImage: "chevron.left") }
                        Spacer()
                        Button { showToc = true } label: { Image(systemName: "list.bullet") }
                        Spacer()
                        Button { viewModel.nextChapter() } label: { Label("下一章", systemImage: "chevron.right") }
                    }
                    .font(.footnote)
                    Text("\(pageIndex + 1) / \(max(pages.count, 1))").font(.caption2).foregroundStyle(.secondary)
                }
                .padding(14)
                .glassCard(RoundedRectangle(cornerRadius: 20))
            } else if !pages.isEmpty {
                Text("\(pageIndex + 1) / \(pages.count)").font(.caption2).foregroundStyle(.secondary)
                    .padding(.bottom, 10)
            }
        }
        .padding(.horizontal, 12)
        .animation(.easeInOut(duration: 0.2), value: showControls)
    }

    private func nextPage() {
        guard !pages.isEmpty else { return }
        if pageIndex + 1 < pages.count { pageIndex += 1 } else { viewModel.nextChapter() }
    }
    private func prevPage() {
        if pageIndex > 0 { pageIndex -= 1 } else { viewModel.prevChapter() }
    }

    private func repaginate(key: String, pageSize: CGSize) async {
        guard !viewModel.currentContent.isEmpty else {
            pages = []; paginatedForKey = key; return
        }
        let fSize = fontSize
        let result = await Task.detached(priority: .userInitiated) {
            TextPaginator.paginate(text: viewModel.currentContent,
                                   font: UIFont.systemFont(ofSize: fSize),
                                   lineSpacing: 8, pageSize: pageSize)
        }.value
        pages = result
        pageIndex = 0
        paginatedForKey = key
    }
}
