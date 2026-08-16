//
//  MovieDetailViewSnapshotTests.swift
//  bilibili_tvTests
//
//  阶段二：MovieDetailViewModel 状态枚举化（MovieDetailState）重构的视觉基准。
//
//  背景：MovieDetailView 根部 `.task` 会在 snapshot 渲染时自动触发 fetchDetail()，
//  把测试预置的 idle/loading/failed 状态覆盖掉（.idle 会发起网络请求、.failed 会重试），
//  导致无法得到可区分的四态基准。因此先抽取了无 `.task` 的 MovieDetailContentScrollView
//  子视图，再对子视图单独渲染（与阶段一 FeedContentScrollView/FeedLoadingView/FeedErrorView
//  拆子视图快照的做法一致）。
//
//  四态映射:
//  - .idle     → MovieDetailContentScrollView(空数据):黑底 + hero 回落 feedItem 占位
//  - .loading  → MovieDetailLoadingView:全屏 ProgressView("加载中...")
//  - .loaded   → MovieDetailViewModel.mock：标题/评分/年份 + 3 集选集横向列表
//  - .failed(message:) → MovieDetailErrorView:错误图标 + 文案 + 重试按钮
//
//  重构完成后重新生成基准并 diff，必须为空或在 PR 描述中逐条解释差异原因；
//  禁止无理由用 record 模式覆盖。
//
//  注意：视图内 KFImage 为异步加载，snapshot 渲染为同步操作，渲染瞬间必然
//  停留在 placeholder(灰块)状态，因此快照结果在本地与 CI 之间是确定性的。
//

import SnapshotTesting
import SwiftUI
import Testing

@testable import bilibili_tv

@Suite(.snapshots)
@MainActor
struct MovieDetailViewSnapshotTests {
    private func makeItem() -> FeedItem {
        FeedItem(
            title: "夏洛特烦恼",
            subtitle: "马冬梅的排列组合",
            cover: "https://i0.hdslb.com/bfs/bangumi/image/4276bcae64678156b596c4bba2e98876ed74e65d.png@3840w_2160h_1e.webp",
            rating: "9.5", badge: "DRM", link: "", episodeId: 320_665, seasonId: 33_354,
            stat: FeedStat(view: 34_320_099, danmaku: 0), rank: 1, indexShow: nil, rankTag: nil,
            brief: "昔日校花秋雅的婚礼正在隆重举行……", overlayImg: nil, logo: nil,
            ogvFusionInfo: OgvFusionInfo(category: "喜剧", tag: nil), newEp: nil, desc: nil
        )
    }

    private func makeViewModel(state: MovieDetailState) -> MovieDetailViewModel {
        let vm = MovieDetailViewModel(feedItem: makeItem())
        vm.state = state
        return vm
    }

    private func makeHost(viewModel: MovieDetailViewModel) -> MovieDetailContentHost {
        MovieDetailContentHost(viewModel: viewModel)
    }

    @Test func detail_idle_state() async {
        let view = makeHost(viewModel: makeViewModel(state: .idle))
        assertSnapshot(of: view, as: .image(precision: 0.95, layout: .fixed(width: 640, height: 360)))
    }

    @Test func detail_loading_state() async {
        let view = MovieDetailLoadingView()
        assertSnapshot(of: view, as: .image(precision: 0.95, layout: .fixed(width: 640, height: 360)))
    }

    @Test func detail_loaded_state() async {
        // 关键：KFImage 异步加载远程海报，快照渲染是同步的。必须清空 Kingfisher 缓存，
        // 保证渲染瞬间停留在 placeholder（灰块），否则热/冷缓存渲染结果不同，
        // 基准在本地与 CI 之间无法复现。
        ContentView.prepareForSnapshotTesting()
        defer { ContentView.resetSnapshotTesting() }
        let view = makeHost(viewModel: .mock)
        assertSnapshot(of: view, as: .image(precision: 0.95, layout: .fixed(width: 640, height: 480)))
    }

    @Test func detail_loaded_state_withEpisodeShelf() async {
        // 更高画布：同时捕获 hero 与选集横向列表（EpisodeCardView 320pt 宽，需横向空间）
        ContentView.prepareForSnapshotTesting()
        defer { ContentView.resetSnapshotTesting() }
        let view = makeHost(viewModel: .mock)
        assertSnapshot(of: view, as: .image(precision: 0.95, layout: .fixed(width: 1_280, height: 900)))
    }

    @Test func detail_failed_state() async {
        let view = MovieDetailErrorView(errorMessage: "网络连接失败，请检查网络后重试", onRetry: {})
        assertSnapshot(of: view, as: .image(precision: 0.95, layout: .fixed(width: 640, height: 360)))
    }
}

/// 持有 FocusState 的宿主视图：MovieDetailContentScrollView 需要 @FocusState.Binding，
/// 而 FocusState 只能在 View 内部创建，故在测试内包一层真实宿主（带黑底，等同真实详情页背景层）。
private struct MovieDetailContentHost: View {
    let viewModel: MovieDetailViewModel

    @State private var isDescriptionExpanded = false
    @FocusState private var isPlayFocused: Bool
    @FocusState private var isBookmarkFocused: Bool
    @State private var isBookmarked = false
    @State private var scrollY: CGFloat = 0

    var body: some View {
        MovieDetailContentScrollView(
            viewModel: viewModel,
            isDescriptionExpanded: $isDescriptionExpanded,
            isPlayFocused: $isPlayFocused,
            isBookmarkFocused: $isBookmarkFocused,
            isBookmarked: $isBookmarked,
            scrollY: $scrollY,
            onPlay: {},
            onBookmarkToggle: {},
            onEpisodeSelect: { _ in }
        )
        .background(Color.black)
    }
}
