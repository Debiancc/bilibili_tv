//
//  FeedViewSnapshotTests.swift
//  bilibili_tvTests
//
//  阶段一：FeedViewModel 状态枚举化（FeedState）重构前的视觉基准。
//
//  背景：ContentView 根部 `.task` 会在 snapshot 渲染时自动触发 fetchInitialFeed(),
//  把测试预置的 idle/failed 状态覆盖成 loading,导致直接 snapshot ContentView 无法
//  得到可区分的四态基准。因此先把 body 的状态分支抽取为三个独立子视图
//  (FeedLoadingView / FeedErrorView / FeedContentScrollView),再对子视图单独渲染。
//
//  四态映射:
//  - .idle     → FeedContentScrollView(空数据):黑屏 + 空 shelves
//  - .loading  → FeedLoadingView:全屏 ProgressView("加载中...")
//  - .loaded   → MovieShelfView(mock 卡片行):成功态的核心视觉单元。
//                不用整页 FeedContentScrollView,因为 Hero 高 1080pt 会占满
//                小窗口导致卡片不可见,而放大窗口需在 CI 模拟器上验证渲染尺寸,
//                存在跨机 gap;卡片区块在 640×480 窗口内完整可见、CI 稳定。
//  - .failed(message:) → FeedErrorView:错误图标 + 文案 + 重试按钮
//
//  重构完成后重新生成基准并 diff,必须为空或在 PR 描述中逐条解释差异原因;
//  禁止无理由用 record 模式覆盖。
//
//  注意：视图内 KFImage 为异步加载,snapshot 渲染为同步操作,渲染瞬间必然
//  停留在 placeholder(灰块)状态,因此快照结果在本地与 CI 之间是确定性的。
//

import SnapshotTesting
import SwiftUI
import Testing

@testable import bilibili_tv

@Suite(.snapshots, .serialized)
@MainActor
struct FeedViewSnapshotTests {
    @Test func contentView_0_hero_carousel_state() async {
        // 同上：轮播页背景/logo 均为 KFImage，清缓存保证首帧停在灰块 + 标题占位，确定性渲染。
        // 顺序要求：命名含 0_ 前缀确保在字母序及 .serialized 队列中排在套件首位执行。
        ContentView.prepareForSnapshotTesting()
        defer { ContentView.resetSnapshotTesting() }
        let mock = FeedViewModel.mock
        let view = HeroCarouselView(
            items: mock.bannerMovies,
            selectedIndex: .constant(0),
            onDetail: {}
        )
        assertSnapshot(
            of: view,
            as: .image(drawHierarchyInKeyWindow: true, precision: 0.95, layout: .fixed(width: 1_920, height: 1_080))
        )
    }

    @Test func contentView_idle_state() async {
        let view = FeedContentScrollView(
            viewModel: FeedViewModel(),
            selectedMovie: .constant(nil)
        )
        assertSnapshot(of: view, as: .image(precision: 0.95, layout: .fixed(width: 640, height: 360)))
    }

    @Test func contentView_loading_state() async {
        let view = FeedLoadingView()
        assertSnapshot(of: view, as: .image(precision: 0.95, layout: .fixed(width: 640, height: 360)))
    }

    @Test func contentView_loaded_state() async {
        // 关键：KFImage 异步加载远程海报，快照渲染是同步的。必须清空 Kingfisher 缓存，
        // 保证渲染瞬间停留在 placeholder（灰块），否则热/冷缓存渲染结果不同，
        // 基准在本地与 CI 之间无法复现（precision 0.356 mismatch 正是冷缓存灰块 vs 基准海报）。
        ContentView.prepareForSnapshotTesting()
        defer { ContentView.resetSnapshotTesting() }
        let mock = FeedViewModel.mock
        let view = MovieShelfView(
            title: "电影热播榜",
            items: mock.rankMovies,
            selectedMovie: .constant(nil)
        )
        assertSnapshot(of: view, as: .image(precision: 0.95, layout: .fixed(width: 640, height: 480)))
    }

    @Test func contentView_failed_state() async {
        let view = FeedErrorView(
            errorMessage: "网络连接失败，请检查网络后重试",
            resumeItems: [],
            onRetry: {}
        )
        assertSnapshot(of: view, as: .image(precision: 0.95, layout: .fixed(width: 640, height: 360)))
    }
}
