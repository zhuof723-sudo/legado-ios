import SwiftUI

// MARK: - 统一翻页视图（对齐 legado-E 5 种翻页动画）

struct PageReaderView: View {
    let pages: [String]
    @Binding var pageIndex: Int
    let pageSize: CGSize
    let config: ReaderConfig
    let onPageChange: (Int) -> Void

    var body: some View {
        switch config.currentPageAnim {
        case .slide:
            slidePageView
        case .cover:
            coverPageView
        case .simulation:
            simulationPageView
        case .scroll:
            scrollPageView
        case .none:
            nonePageView
        }
    }

    // MARK: - 滑动翻页（TabView .page 风格）

    private var slidePageView: some View {
        TabView(selection: $pageIndex) {
            ForEach(pages.indices, id: \.self) { i in
                pageContent(pages[i])
                    .tag(i)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .ignoresSafeArea(edges: .bottom)
        .onChange(of: pageIndex) { onPageChange(pageIndex) }
    }

    // MARK: - 覆盖翻页（新页从右侧滑入覆盖旧页）

    private var coverPageView: some View {
        ZStack {
            if pageIndex < pages.count {
                pageContent(pages[pageIndex])
                    .id(pageIndex)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .opacity
                    ))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: pageIndex)
        .contentShape(Rectangle())
        .gesture(
            DragGesture()
                .onEnded { value in
                    if value.translation.width < -50 {
                        goNext()
                    } else if value.translation.width > 50 {
                        goPrev()
                    }
                }
        )
    }

    // MARK: - 仿真翻页（简化版：3D 旋转 + 阴影）

    private var simulationPageView: some View {
        ZStack {
            if pageIndex > 0 {
                pageContent(pages[pageIndex - 1])
                    .opacity(0.3)
            }
            if pageIndex < pages.count {
                pageContent(pages[pageIndex])
                    .id(pageIndex)
                    .background(
                        RoundedRectangle(cornerRadius: 2)
                            .fill(config.currentTheme.background)
                            .shadow(color: .black.opacity(0.15), radius: 8, x: -4, y: 0)
                    )
            }
        }
        .animation(.easeInOut(duration: 0.3), value: pageIndex)
        .contentShape(Rectangle())
        .gesture(
            DragGesture()
                .onEnded { value in
                    if value.translation.width < -50 {
                        goNext()
                    } else if value.translation.width > 50 {
                        goPrev()
                    }
                }
        )
    }

    // MARK: - 滚动翻页（连续滚动，不分页）

    private var scrollPageView: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: config.paragraphSpacing) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { i, page in
                        pageContent(page)
                            .id(i)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                }
                .padding(.top, config.paddingTop)
                .padding(.bottom, config.paddingBottom)
            }
            .onAppear {
                proxy.scrollTo(pageIndex, anchor: .top)
            }
        }
    }

    // MARK: - 无动画翻页

    private var nonePageView: some View {
        ZStack {
            if pageIndex < pages.count {
                pageContent(pages[pageIndex])
                    .id(pageIndex)
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture()
                .onEnded { value in
                    if value.translation.width < -50 {
                        goNext()
                    } else if value.translation.width > 50 {
                        goPrev()
                    }
                }
        )
    }

    // MARK: - 页面内容渲染

    private func pageContent(_ text: String) -> some View {
        Text(text)
            .font(config.swiftUIFont)
            .foregroundStyle(config.currentTheme.textColor)
            .lineSpacing(config.lineSpacing)
            .tracking(config.letterSpacing)
            .multilineTextAlignment(config.textAlignmentValue)
            .frame(width: pageSize.width, height: pageSize.height, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .top)
    }

    // MARK: - 翻页控制

    private func goNext() {
        guard pageIndex + 1 < pages.count else { return }
        withAnimation { pageIndex += 1 }
        onPageChange(pageIndex)
    }

    private func goPrev() {
        guard pageIndex > 0 else { return }
        withAnimation { pageIndex -= 1 }
        onPageChange(pageIndex)
    }
}
