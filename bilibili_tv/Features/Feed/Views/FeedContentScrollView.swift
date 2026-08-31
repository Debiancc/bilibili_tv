import SwiftUI

/// 主内容态：加载中/远程失败时仍保留下方本地续播 shelf 的完整 feed。
/// 包含顶部状态条、Hero 轮播与各分类 shelf。
/// 从 ContentView 的状态分支抽取,便于 snapshot 测试单独渲染。
struct FeedContentScrollView: View {
    @Bindable var viewModel: FeedViewModel
    let ownerTab: HomeTab
    /// 本 Tab 是否为当前选中 Tab:false 时轮播视频不激活(显式门控,
    /// 不依赖 TabView 切换时可能不触发的 onDisappear)
    var isTabSelected: Bool = true
    /// 详情导航经环境直达根视图协调器(阶段二:hero 详情按钮不再写 ContentView 的绑定)
    @Environment(\.playbackCoordinator) private var playbackCoordinator
    /// 顶部 shelf 与 hero banner 的重叠量(负值=上移):
    /// 只允许 shelf 标题区与 banner 渐变重叠,卡片本体必须位于 banner 焦点框(0...1080)之下,
    /// 否则 tvOS 焦点引擎会因帧重叠而无法从 banner 下移到该 shelf 的卡片。
    /// 唯一写入方是本视图(随滚动联动),故降为内部状态,不再经 ContentView 转发。
    @State private var shelfOverlap: CGFloat = -120
    /// hero 轮播页级焦点(经 HeroCarouselView 绑定):由本视图持有,供「↑ 承接锚点」
    /// 在引擎无法自动揭示 hero 时程序性回锚到当前页 Play 按钮
    @FocusState private var heroFocus: HeroButtonFocus?
    /// 「↑ 承接锚点」自身焦点状态(获焦即触发回 hero)
    @FocusState private var isUpAnchorFocused: Bool

    /// 外层垂直 ScrollView 滚动容器中的 hero 锚点 id(ReturnToHero 滚动目标)
    private static let heroCarouselID = "feed-hero-carousel"
    /// 承接锚点尺寸:透明面板,仅当 hero 内容不可见时为「↑」提供几何候选
    private static let upAnchorWidth: CGFloat = 1_000
    private static let upAnchorHeight: CGFloat = 70

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    statusBanner

                    // Hero Carousel
                    if !viewModel.bannerMovies.isEmpty {
                        HeroCarouselView(
                            items: viewModel.bannerMovies,
                            selectedIndex: $viewModel.currentBannerIndex,
                            indicatorOffset: shelfOverlap,
                            isTabSelected: isTabSelected,
                            onDetail: {
                                guard let index = viewModel.currentBannerIndex,
                                    viewModel.bannerMovies.indices.contains(index)
                                else { return }
                                playbackCoordinator.openDetail(viewModel.bannerMovies[index], owner: ownerTab)
                            },
                            focusedButton: $heroFocus
                        )
                        .id(Self.heroCarouselID)
                        .frame(height: 1_080)
                        .background(
                            GeometryReader { geo in
                                Color.clear
                                    .onChange(of: geo.frame(in: .named("feedScroll")).minY) { _, newValue in
                                        updateShelfOverlap(for: newValue)
                                    }
                            }
                        )
                    }

                    // Shelves
                    ShelvesSection(
                        viewModel: viewModel,
                        topPadding: shelfOverlap,
                        ownerTab: ownerTab
                    )
                }
            }
            .coordinateSpace(.named("feedScroll"))
            .edgesIgnoringSafeArea([.horizontal, .top])
            // 「↑ 承接锚点」:hero 滚出视口后,引擎无法自动揭示嵌套容器内的 hero 按钮
            // (揭示请求发往水平容器,其无垂直滚动能力),↑ 至此被消费、焦点不动。
            // 这里以固定窗口帧放置一个不可见 focusable 面板作为可达候选:
            // 卡片行 ↑ 时引擎先落到锚点,再由 returnToHero 滚动回 hero 并重锚 Play。
            .overlay(alignment: .top) {
                if !viewModel.bannerMovies.isEmpty {
                    upAnchor(proxy: proxy)
                }
            }
        }
    }

    /// 加载中/远程失败的顶部状态条(仍保留下方本地续播 shelf)
    @ViewBuilder
    private var statusBanner: some View {
        if case .failed(let message) = viewModel.state {
            HStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("重试") {
                    Task {
                        await viewModel.fetchInitialFeed()
                    }
                }
                .buttonStyle(.glass)
            }
            .padding(.top, 40)
            .padding(.horizontal, 50)
        } else if case .loading = viewModel.state, viewModel.rankMovies.isEmpty {
            ProgressView()
                .padding(.top, 40)
        }
    }

    /// 「↑ 承接锚点」本体:不可见 focusable 面板,获焦即触发 returnToHero
    private func upAnchor(proxy: ScrollViewProxy) -> some View {
        Color.clear
            .frame(width: Self.upAnchorWidth, height: Self.upAnchorHeight)
            .focusable(isUpAnchorEnabled)
            .focused($isUpAnchorFocused)
            .onChange(of: isUpAnchorFocused) { _, focused in
                guard focused else { return }
                returnToHero(proxy: proxy)
            }
            .accessibilityHidden(true)
    }

    /// 「↑ 承接锚点」是否注册焦点:快照渲染关闭(与 hero 焦点副作用一致,
    /// 锚点会抢占 drawHierarchy 的确定性初始焦点)
    private var isUpAnchorEnabled: Bool {
        #if DEBUG
        !ContentView.isSnapshotTesting
        #else
        true
        #endif
    }

    /// 锚点获焦 → 滚动回 hero 顶部并把焦点重锚到当前页 Play 按钮。
    /// 与 HeroCarouselView 的「焦点先行」惯例一致:先滚动揭示按钮,再写入焦点。
    private func returnToHero(proxy: ScrollViewProxy) {
        guard !viewModel.bannerMovies.isEmpty else { return }
        let page = viewModel.currentBannerIndex ?? 0
        withAnimation(.easeOut(duration: 0.3)) {
            // 外层垂直 ScrollView 的 scrollTo:hero 锚点回到视口顶部
            proxy.scrollTo(Self.heroCarouselID, anchor: .top)
        }
        // 等滚动完成再写焦点,避免对不可见按钮的焦点写入被引擎丢弃
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            // 转焦期间用户可能已把焦点移走:不再覆盖
            guard isUpAnchorFocused else { return }
            heroFocus = .play(page)
        }
    }

    /// hero 与 shelf 重叠量随滚动同步：-120 上移让卡片进入焦点框，< -100 恢复 0。
    private func updateShelfOverlap(for minY: CGFloat) {
        let target: CGFloat = minY < -100 ? 0 : -120
        if shelfOverlap != target {
            withAnimation(.easeOut(duration: 0.2)) {
                shelfOverlap = target
            }
        }
    }
}

/// 主内容 shelf 区：排行榜/继续观看/热播/即将上线，标题随频道语义变化
private struct ShelvesSection: View {
    let viewModel: FeedViewModel
    let topPadding: CGFloat
    let ownerTab: HomeTab

    var body: some View {
        VStack(spacing: 60) {
            if !viewModel.rankMovies.isEmpty {
                ShelfView(
                    title: "\(viewModel.currentChannel.title)热播榜",
                    items: viewModel.rankMovies,
                    ownerTab: ownerTab
                )
            }

            // ▶️ 继续观看:未登录或没有进行中的 PGC 观看记录时隐藏
            if !viewModel.resumeItems.isEmpty {
                ResumeShelfView(items: viewModel.resumeItems)
            }

            if !viewModel.exclusiveMovies.isEmpty {
                ShelfView(
                    title: viewModel.currentChannel == .movie ? "海量热播" : "正在热播",
                    items: viewModel.exclusiveMovies,
                    ownerTab: ownerTab
                )
            }

            if !viewModel.comingSoonMovies.isEmpty {
                ShelfView(title: "即将上线", items: viewModel.comingSoonMovies, ownerTab: ownerTab)
            }

            Spacer(minLength: 100)
        }
        .padding(.top, topPadding)
    }
}
