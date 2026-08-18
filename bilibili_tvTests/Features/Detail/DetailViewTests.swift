//
//  DetailViewTests.swift
//  bilibili_tvTests
//
//  阶段二：DetailView / DetailContentScrollView 冒烟测试。
//  覆盖 DetailState 每一个 case（idle/loading/loaded/failed(message:)）下
//  body 构建不崩溃，验证 switch 状态机消费端改造没有引入崩溃回归。
//

import SwiftUI
import Testing

@testable import bilibili_tv

@MainActor
struct DetailViewTests {
    private func makeItem(
        seasonId: Int? = 33_354,
        episodeId: Int? = 320_665,
        newEp: NewEpInfo? = nil,
        desc: String? = nil
    ) -> FeedItem {
        FeedItem(
            title: "夏洛特烦恼", subtitle: "马冬梅的排列组合",
            cover: "https://example.com/cover.png@3840w_2160h_1e.webp",
            rating: "9.5", badge: "DRM", link: "", episodeId: episodeId, seasonId: seasonId,
            stat: FeedStat(view: 34_320_099, danmaku: 0), rank: 1, indexShow: nil, rankTag: nil,
            brief: "剧情简介", overlayImg: nil, logo: nil, ogvFusionInfo: nil,
            newEp: newEp, desc: desc
        )
    }

    private func makeViewModel(state: DetailState) -> DetailViewModel {
        let vm = DetailViewModel(feedItem: makeItem())
        if case .loaded = state {
            vm.seasonDetail = DetailViewModel.mock.seasonDetail
        }
        vm.state = state
        return vm
    }

    private func makeView(state: DetailState) -> DetailView {
        DetailView(item: makeItem(), viewModel: makeViewModel(state: state))
    }

    @Test func movieDetailView_idleState_buildsBody() {
        _ = makeView(state: .idle).body
    }

    @Test func movieDetailView_loadingState_buildsBody() {
        _ = makeView(state: .loading).body
    }

    @Test func movieDetailView_loadedState_buildsBody() {
        _ = makeView(state: .loaded).body
    }

    @Test func movieDetailView_failedState_buildsBody() {
        _ = makeView(state: .failed(message: "网络连接失败")).body
    }

    @Test func movieDetailContentScrollView_loadedStateWithEpisodes_buildsBodyWithoutCrashing() {
        let vm = DetailViewModel.mock
        let scrollView = DetailContentScrollView(
            viewModel: vm,
            isPlayFocused: FocusState<Bool>().projectedValue,
            isBookmarkFocused: FocusState<Bool>().projectedValue,
            scrollY: .constant(0)
        )
        _ = scrollView.body
    }

    @Test func movieDetailContentScrollView_failedStateEmptyEpisodes_buildsBodyWithoutCrashing() {
        let vm = DetailViewModel(feedItem: makeItem())
        vm.state = .failed(message: "网络连接失败")
        let scrollView = DetailContentScrollView(
            viewModel: vm,
            isPlayFocused: FocusState<Bool>().projectedValue,
            isBookmarkFocused: FocusState<Bool>().projectedValue,
            scrollY: .constant(0)
        )
        _ = scrollView.body
    }

    @Test func movieDetailView_withNewEpAndDescFields_buildsBodyWithoutCrashing() {
        let item = makeItem(newEp: NewEpInfo(indexShow: "更新至第1集"), desc: "一段全新的剧情描述")
        _ = DetailView(item: item).body
    }

    @Test func movieDetailView_withAllOptionalFieldsNil_buildsBodyWithoutCrashing() {
        let item = makeItem(seasonId: nil, episodeId: nil)
        _ = DetailView(item: item).body
    }
}
