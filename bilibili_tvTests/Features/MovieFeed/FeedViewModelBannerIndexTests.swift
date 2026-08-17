//
//  FeedViewModelBannerIndexTests.swift
//  bilibili_tvTests
//
//  Phase 1: currentBannerIndex 迁入 FeedViewModel 后的行为契约（TDD RED 先行）。
//  轮播索引在频道切换时必须归零，否则 scrollPosition 在新数据上可能越界。
//

import Foundation
import Testing

@testable import bilibili_tv

@MainActor
struct FeedViewModelBannerIndexTests {
    /// 构造一个加载必然成功的 ViewModel（空数据即成功）
    private func makeSuccessViewModel() -> FeedViewModel {
        let mock = MockFeedService()
        mock.modPageResult = .success(TVModPageResponse(code: 0, message: "", data: []))
        mock.rankListResult = .success([])
        return FeedViewModel(service: mock)
    }

    @Test("给定轮播索引停留在第 2 页 → 切换到番剧频道后索引归零")
    func switchChannelResetsBannerIndex() async {
        // given
        let vm = makeSuccessViewModel()
        vm.currentBannerIndex = 2

        // when
        await vm.switchChannel(to: .anime)

        // then
        #expect(vm.currentBannerIndex == 0)
    }

    @Test("给定初始状态 → 轮播索引默认为第 0 页")
    func initialBannerIndexIsZero() {
        // given
        let vm = makeSuccessViewModel()

        // then
        #expect(vm.currentBannerIndex == 0)
    }
}
