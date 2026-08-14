import SwiftUI

/// 主内容态：加载中/远程失败时仍保留下方本地续播 shelf 的完整 feed。
/// 包含顶部状态条、Hero 轮播与各分类 shelf。
/// 从 ContentView 的状态分支抽取,便于 snapshot 测试单独渲染。
struct FeedContentScrollView: View {
    let viewModel: FeedViewModel
    @Binding var selectedMovie: FeedItem?
    @Binding var currentBannerIndex: Int
    @Binding var bannerToPlay: FeedItem?
    @Binding var shelfOverlap: CGFloat
    let onResume: (LocalWatchHistoryEntry) -> Void

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                // 加载中/远程失败的顶部状态条(仍保留下方本地续播 shelf)
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

                // Hero Carousel
                if !viewModel.bannerMovies.isEmpty {
                    HeroCarouselView(
                        items: viewModel.bannerMovies,
                        selectedIndex: $currentBannerIndex,
                        selectedMovie: $selectedMovie,
                        bannerToPlay: $bannerToPlay,
                        indicatorOffset: shelfOverlap
                    )
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
                    selectedMovie: $selectedMovie,
                    onResume: onResume,
                    topPadding: shelfOverlap
                )
            }
        }
        .coordinateSpace(.named("feedScroll"))
        .edgesIgnoringSafeArea([.horizontal, .top])
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
    @Binding var selectedMovie: FeedItem?
    let onResume: (LocalWatchHistoryEntry) -> Void
    let topPadding: CGFloat

    var body: some View {
        VStack(spacing: 60) {
            if !viewModel.rankMovies.isEmpty {
                MovieShelfView(
                    title: "\(viewModel.currentChannel.title)热播榜",
                    items: viewModel.rankMovies,
                    selectedMovie: $selectedMovie
                )
            }

            // ▶️ 继续观看:未登录或没有进行中的 PGC 观看记录时隐藏
            if !viewModel.resumeItems.isEmpty {
                ResumeShelfView(items: viewModel.resumeItems, onSelect: onResume)
            }

            if !viewModel.exclusiveMovies.isEmpty {
                MovieShelfView(
                    title: viewModel.currentChannel == .movie ? "海量热播" : "正在热播",
                    items: viewModel.exclusiveMovies,
                    selectedMovie: $selectedMovie
                )
            }

            if !viewModel.comingSoonMovies.isEmpty {
                MovieShelfView(title: "即将上线", items: viewModel.comingSoonMovies, selectedMovie: $selectedMovie)
            }

            Spacer(minLength: 100)
        }
        .padding(.top, topPadding)
    }
}
