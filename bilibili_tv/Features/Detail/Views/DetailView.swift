import Kingfisher
import SwiftUI

struct DetailView: View {
    @State private var viewModel: DetailViewModel

    @FocusState private var isPlayFocused: Bool
    @FocusState private var isBookmarkFocused: Bool

    @State private var scrollY: CGFloat = 0

    init(item: FeedItem) {
        _viewModel = State(initialValue: DetailViewModel(feedItem: item))
    }

    /// 测试注入入口：用预置 state 的 ViewModel 渲染（snapshot 四态基准 / 焦点导航 mock）
    init(item: FeedItem, viewModel: DetailViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ZStack(alignment: .top) {
            // 背景层 (深色底 + 全屏海报 + 双向渐变蒙版)
            DetailBackdrop(coverURL: viewModel.coverURL, scrollY: scrollY)

            // 📺 详情主体按加载状态切换
            switch viewModel.state {
            case .idle, .loaded:
                DetailContentScrollView(
                    viewModel: viewModel,
                    isPlayFocused: $isPlayFocused,
                    isBookmarkFocused: $isBookmarkFocused,
                    scrollY: $scrollY
                )
            case .loading:
                DetailLoadingView()
            case .failed(let message):
                DetailErrorView(
                    errorMessage: message,
                    onRetry: {
                        Task { await viewModel.fetchDetail() }
                    }
                )
            }
        }
        .task {
            await viewModel.fetchDetail()
        }
        .onAppear {
            isPlayFocused = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isPlayFocused = true
            }
        }
    }
}

// MARK: - 主内容区 (滚动布局,与 .task 分离,便于 snapshot 测试单独渲染)

struct DetailContentScrollView: View {
    let viewModel: DetailViewModel
    @FocusState.Binding var isPlayFocused: Bool
    @FocusState.Binding var isBookmarkFocused: Bool
    @Binding var scrollY: CGFloat
    @Environment(\.playbackCoordinator) private var playbackCoordinator

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            ScrollViewReader { scrollProxy in
                VStack(alignment: .leading, spacing: 40) {
                    Color.clear.frame(height: 1).id("topOfPage")

                    // --- 顶部 Hero 区域 ---
                    DetailHeroSection(
                        viewModel: viewModel,
                        isPlayFocused: $isPlayFocused,
                        isBookmarkFocused: $isBookmarkFocused,
                        scrollY: $scrollY,
                        scrollToTop: {
                            withAnimation(.easeOut(duration: 0.3)) { scrollProxy.scrollTo("topOfPage", anchor: .top) }
                        }
                    )
                    .padding(.leading, 90)
                    .padding(.bottom, 40)

                    // --- 底部内容区域 (需向下滚动) ---

                    // 选集列表
                    if !viewModel.episodes.isEmpty {
                        VStack(alignment: .leading, spacing: 20) {
                            Text("选集")
                                .font(.headline)
                                .foregroundStyle(.white)
                                .padding(.leading, 90)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 30) {
                                    ForEach(viewModel.episodes) { ep in
                                        EpisodeCardView(episode: ep, action: { play(ep) })
                                    }
                                }
                                .padding(.horizontal, 90)
                                .padding(.vertical, 20)
                            }
                        }
                    }

                    Spacer().frame(height: 100)
                }
            }
        }
    }

    /// 选集播放：经环境协调器直达根视图 cover（原 DetailView 内联 fullScreenCover 已收敛）
    private func play(_ episode: PGCEpisode) {
        print("▶️ [DetailView] 播放: \(viewModel.title)")
        playbackCoordinator.play(viewModel.playbackContext(for: episode))
    }
}

// MARK: - 背景层 (深色底 + 全屏海报 + 双向渐变蒙版)

private struct DetailBackdrop: View {
    let coverURL: URL?
    let scrollY: CGFloat

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

            // 全屏高清海报 (Hero Background)
            GeometryReader { proxy in
                KFImage(coverURL)
                    .placeholder { Color.black }
                    .fade(duration: 0.5)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
                    // 向下滚动时，背景逐渐变暗，确保底部内容的可读性
                    .overlay(
                        Color.black.opacity(min(Double(max(0, -scrollY) / 600.0), 0.85))
                    )
            }
            .ignoresSafeArea()

            // Apple TV 风格双向渐变蒙版 (底部变暗 + 左侧变暗)
            LinearGradient(
                colors: [Color.clear, Color.black.opacity(0.7), Color.black.opacity(0.95)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            LinearGradient(
                colors: [Color.black.opacity(0.8), Color.black.opacity(0.3), Color.clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .ignoresSafeArea()
        }
    }
}

// MARK: - 顶部 Hero 区域

private struct DetailHeroSection: View {
    let viewModel: DetailViewModel
    @FocusState.Binding var isPlayFocused: Bool
    @FocusState.Binding var isBookmarkFocused: Bool
    @Binding var scrollY: CGFloat
    let scrollToTop: () -> Void

    // 阶段一下沉：这两个状态仅在本节内消费（简介展开 / 追剧按钮），不再上抛到 DetailView
    @State private var isDescriptionExpanded: Bool = false
    @State private var isBookmarked = false

    @Environment(\.playbackCoordinator) private var playbackCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            scrollTracker

            // 预留高度，把文字推到屏幕左下侧
            Spacer()
                .frame(height: 100)
                .id("topSpacer")

            titleLogo
            metaBadges
            expandableDescription
            actionButtons
        }
    }

    /// 用 GeometryReader 追踪滚动位移
    private var scrollTracker: some View {
        GeometryReader { geo in
            Color.clear
                .onChange(of: geo.frame(in: .global).minY) { _, newValue in
                    scrollY = newValue - 200  // 补偿初始安全区偏移
                }
        }
        .frame(height: 0)
    }

    /// 台标优先展示,失败/缺失时回退文字标题
    private var titleLogo: some View {
        Group {
            if let logoUrl = viewModel.feedItem.secureLogoURL {
                KFImage(logoUrl)
                    .setProcessor(LogoTrimmingProcessor())
                    .fade(duration: 0.3)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 500, maxHeight: 200, alignment: .bottomLeading)
            } else {
                Text(viewModel.title)
                    .font(.system(size: 64, weight: .heavy))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .shadow(color: .black.opacity(0.5), radius: 10, x: 0, y: 5)
            }
        }
    }

    /// 动态元数据行:类型 / 评分 / 风格 / 年份
    private var metaBadges: some View {
        HStack(spacing: 12) {
            if let typeName = viewModel.typeNameText, !typeName.isEmpty {
                BadgeLabel(title: typeName, color: .white)
            }

            if let rating = viewModel.ratingText {
                HStack(spacing: 2) {
                    Text(rating).font(.caption)
                    Text("分").font(.caption).foregroundStyle(.white.opacity(0.8))
                }
            }

            if let styles = viewModel.stylesText {
                Text(styles)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
            }

            if let year = viewModel.pubYear {
                Text(year)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
    }

    /// 剧情简介:点击在简短/展开间切换
    private var expandableDescription: some View {
        Group {
            if let desc = viewModel.description {
                Button(action: {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        isDescriptionExpanded.toggle()
                    }
                }) {
                    Text(desc)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.9))
                        .lineSpacing(8)
                        .lineLimit(isDescriptionExpanded ? nil : 4)
                        .frame(maxWidth: 900, minHeight: 56, alignment: .leading)
                        .multilineTextAlignment(.leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityValue(isDescriptionExpanded ? "已展开" : "已折叠")
                .accessibilityHint("激活可展开或折叠剧情简介")
            }
        }
    }

    /// 操作按钮行:播放 / 追剧,聚焦时滚回顶部
    private var actionButtons: some View {
        HStack(spacing: 30) {
            Button(action: play) {
                HStack(spacing: 12) {
                    Image(systemName: "play.fill")
                        .font(.title2)
                    Text("立即播放")
                        .font(.headline)
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 14)
            }
            .buttonStyle(.glassProminent)
            .focused($isPlayFocused)

            Button(action: { isBookmarked.toggle() }) {
                HStack(spacing: 10) {
                    Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                        .foregroundStyle(isBookmarked ? .yellow : .white)
                    Text(isBookmarked ? "已追剧" : "追剧")
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
            }
            .buttonStyle(.glass)
            .focused($isBookmarkFocused)
        }
        .padding(.top, 10)
        .onChange(of: isPlayFocused) { _, isFocused in
            if isFocused { scrollToTop() }
        }
        .onChange(of: isBookmarkFocused) { _, isFocused in
            if isFocused { scrollToTop() }
        }
    }

    /// 立即播放：经环境协调器直达根视图 cover（播放第一集,无选集时按整季兜底）
    private func play() {
        print("▶️ [DetailView] 播放: \(viewModel.title)")
        playbackCoordinator.play(viewModel.playbackContext(for: viewModel.episodes.first))
    }
}

// 徽章组件 (复用)
struct BadgeLabel: View {
    let title: String
    let color: Color

    var body: some View {
        Text(title)
            .font(.caption)
            .fontWeight(.semibold)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.25))
            .foregroundStyle(color)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(color.opacity(0.5), lineWidth: 1)
            )
            .cornerRadius(6)
    }
}

#Preview {
    DetailView(
        item: FeedItem(
            // swiftlint:disable line_length
            title: "夏洛特烦恼", subtitle: "马冬梅的排列组合",
            cover: "https://i0.hdslb.com/bfs/bangumi/image/4276bcae64678156b596c4bba2e98876ed74e65d.png@3840w_2160h_1e.webp", rating: "9.5", badge: "DRM",
            link: "", episodeId: 320_665, seasonId: 33_354, stat: FeedStat(view: 34_320_099, danmaku: 0), rank: 1, indexShow: nil, rankTag: nil,
            brief:
                "昔日校花秋雅（王智 饰）的婚礼正在隆重举行，学生时代暗恋秋雅的男主角夏洛（沈腾 饰）看着周围事业成功的老同学，心中泛起酸味，借着七分醉意大闹婚礼现场，甚至惹得妻子马冬梅（马丽 饰）现场发飙，而他发泄过后却在马桶上睡着了。梦里他重回校园，追求到他心爱的女孩、让失望的母亲重展笑颜、甚至成为无所不能的流行乐坛巨星……\n醉生梦死中，他发现身边人都在利用自己，只有马冬梅是最值得珍惜的……",
            overlayImg: nil, logo: nil, ogvFusionInfo: nil, newEp: nil, desc: "DESC..........."
                // swiftlint:enable line_length
        ))
}
