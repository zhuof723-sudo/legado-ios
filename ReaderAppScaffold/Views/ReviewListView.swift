import SwiftUI

// MARK: - 评论列表弹窗

/// 段评列表视图，展示某一段的所有评论。
/// 参考微信读书/起点读书的段评 UI 设计：底部弹出，半屏高度，评论列表 + 输入框。
struct ReviewListView: View {
    let paragraphText: String
    let paragraphIndex: Int
    @State private var reviews: [Review] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var newComment = ""
    let onClose: () -> Void
    let fetchReviews: (Int, String) async throws -> [Review]

    var body: some View {
        VStack(spacing: 0) {
            // 顶部拖拽条 + 标题
            header

            // 段落引用
            paragraphQuote

            Divider()

            // 评论列表
            if isLoading {
                loadingView
            } else if let error = errorMessage {
                errorView(error)
            } else if reviews.isEmpty {
                emptyView
            } else {
                reviewList
            }

            Spacer(minLength: 0)

            // 底部输入框
            inputBar
        }
        .background(Color(.systemBackground))
        .cornerRadius(16, corners: [.topLeft, .topRight])
        .presentationDetents([.fraction(0.5)])
        .presentationDragIndicator(.visible)
        .onAppear {
            loadReviews()
        }
    }

    // MARK: - 头部

    private var header: some View {
        HStack {
            Text("段评")
                .font(.headline)
                .fontWeight(.semibold)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .font(.title2)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    // MARK: - 段落引用

    private var paragraphQuote: some View {
        HStack(alignment: .top, spacing: 8) {
            Rectangle()
                .fill(Color.accentColor)
                .frame(width: 3)
            Text(paragraphText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(3)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glassCard(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - 评论列表

    private var reviewList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(reviews) { review in
                    ReviewRow(review: review)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
    }

    // MARK: - 加载中

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            Text("加载评论中...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    // MARK: - 错误

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("重试") {
                loadReviews()
            }
            .plainGlassButton()
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
        .padding(.horizontal, 16)
    }

    // MARK: - 空状态

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("还没有评论，来抢沙发吧")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    // MARK: - 底部输入框

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("说点什么...", text: $newComment)
                .textFieldStyle(.roundedBorder)
                .disabled(true) // 发布评论功能暂未实现
            Button(action: {}) {
                Image(systemName: "paperplane.fill")
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.accentColor.opacity(0.5))
                    .clipShape(Circle())
            }
            .disabled(true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .liquidGlass(in: Rectangle())
    }

    // MARK: - 加载评论

    private func loadReviews() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                let result = try await fetchReviews(paragraphIndex, paragraphText)
                await MainActor.run {
                    reviews = result
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }
}

// MARK: - 单条评论行

struct ReviewRow: View {
    let review: Review

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // 头像
            avatar
            VStack(alignment: .leading, spacing: 4) {
                // 用户名 + 时间
                HStack {
                    Text(review.userName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                    Spacer()
                    if let time = review.postTime, !time.isEmpty {
                        Text(time)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                // 评论内容
                Text(review.content)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                // 点赞/回复
                HStack(spacing: 16) {
                    Button(action: {}) {
                        HStack(spacing: 4) {
                            Image(systemName: "hand.thumbsup")
                                .font(.caption)
                            if let count = review.likeCount, count > 0 {
                                Text("\(count)")
                                    .font(.caption)
                            }
                        }
                        .foregroundStyle(.secondary)
                    }
                    Button(action: {}) {
                        HStack(spacing: 4) {
                            Image(systemName: "bubble.right")
                                .font(.caption)
                            if let count = review.replyCount, count > 0 {
                                Text("\(count)")
                                    .font(.caption)
                            }
                        }
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var avatar: some View {
        Group {
            if let avatarUrl = review.avatarUrl,
               let url = URL(string: avatarUrl) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    default:
                        placeholderAvatar
                    }
                }
            } else {
                placeholderAvatar
            }
        }
        .frame(width: 36, height: 36)
        .clipShape(Circle())
    }

    private var placeholderAvatar: some View {
        Circle()
            .fill(Color.gray.opacity(0.3))
            .overlay(
                Text(String(review.userName.prefix(1)))
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
            )
    }
}

// MARK: - 圆角修饰符（兼容旧版 iOS）

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}
