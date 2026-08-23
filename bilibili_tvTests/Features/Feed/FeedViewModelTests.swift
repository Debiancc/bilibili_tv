//
//  FeedViewModelTests.swift
//  bilibili_tvTests
//
//  阶段一：FeedViewModel 状态机（FeedState）行为断言测试。
//  注入 MockFeedService（Result 脚本 + 调用计数），断言状态迁移的具体结果：
//  成功填充 shelves、失败携带预期文案、失败后重试真的重新发起请求、loading/loaded 幂等。
//

import Foundation
import Testing

@testable import bilibili_tv

/// Mock 主页服务：按脚本返回预置结果，驱动 FeedViewModel 状态机测试
@MainActor
final class MockFeedService: FeedServicing {
    var modPageResult: Result<TVModPageResponse, Error> = .failure(URLError(.badServerResponse))
    var rankListResult: Result<[FeedItem], Error> = .failure(URLError(.badServerResponse))

    private(set) var modPageCallCount = 0
    private(set) var rankListCallCount = 0

    private(set) var modPageIDs: [Int] = []
    private(set) var rankSeasonTypes: [Int] = []

    /// 测试钩子：每次 fetchTVModPage 被调用时触发（在返回结果前）。
    /// 用于在“请求在途”时机注入真实调用（如模拟用户此时又选了另一个频道）。
    var onModPageCalled: (() async -> Void)?

    func fetchTVModPage(pageId: Int) async throws -> TVModPageResponse {
        modPageCallCount += 1
        modPageIDs.append(pageId)
        await onModPageCalled?()
        return try modPageResult.get()
    }

    func fetchRankList(day: Int, seasonType: Int) async throws -> [FeedItem] {
        rankListCallCount += 1
        rankSeasonTypes.append(seasonType)
        return try rankListResult.get()
    }
}

@MainActor
struct FeedViewModelTests {
    private func makeItem(title: String, episodeId: Int) -> FeedItem {
        FeedItem(
            title: title,
            subtitle: nil,
            cover: "https://example.com/cover.png",
            rating: nil,
            badge: nil,
            link: nil,
            episodeId: episodeId,
            seasonId: nil,
            stat: nil,
            rank: nil,
            indexShow: nil,
            rankTag: nil,
            brief: nil,
            overlayImg: nil,
            logo: nil,
            ogvFusionInfo: nil,
            newEp: nil,
            desc: nil
        )
    }

    private func makeSuccessModPage() -> TVModPageResponse {
        TVModPageResponse(
            code: 0,
            message: "ok",
            data: [
                TVModPageModule(id: 1, type: TVModuleType.banner.rawValue, title: "banner", data: [makeItem(title: "Banner", episodeId: 11)]),
                TVModPageModule(id: 2, type: TVModuleType.exclusive.rawValue, title: "exclusive", data: [makeItem(title: "Exclusive", episodeId: 22)]),
                TVModPageModule(id: 3, type: TVModuleType.comingSoon.rawValue, title: "comingSoon", data: [makeItem(title: "ComingSoon", episodeId: 33)])
            ]
        )
    }

    private func makeRankList() -> [FeedItem] {
        [makeItem(title: "Rank 1", episodeId: 44)]
    }

    // MARK: - 成功路径

    @Test func fetch_success_populatesShelvesAndTransitionsToLoaded() async {
        let service = MockFeedService()
        service.modPageResult = .success(makeSuccessModPage())
        service.rankListResult = .success(makeRankList())
        let vm = FeedViewModel(service: service)

        await vm.fetchInitialFeed()

        #expect(vm.state == .loaded)
        #expect(vm.rankMovies.count == 1)
        #expect(vm.bannerMovies.count == 1)
        #expect(vm.exclusiveMovies.count == 1)
        #expect(vm.comingSoonMovies.count == 1)
        #expect(vm.rankMovies[0].title == "Rank 1")
        #expect(service.modPageCallCount == 1)
        #expect(service.rankListCallCount == 1)
    }

    // MARK: - 失败路径

    @Test func fetch_failure_carriesExpectedErrorMessage() async {
        let service = MockFeedService()
        let expected = URLError(.notConnectedToInternet)
        service.modPageResult = .failure(expected)
        let vm = FeedViewModel(service: service)

        await vm.fetchInitialFeed()

        #expect(vm.state == .failed(message: expected.localizedDescription))
        #expect(vm.rankMovies.isEmpty)
        #expect(vm.bannerMovies.isEmpty)
    }

    // MARK: - 失败后重试真的重新发起请求

    @Test func fetch_afterFailure_retryReissuesRequestsAndRecovers() async {
        let service = MockFeedService()
        service.modPageResult = .failure(URLError(.timedOut))
        service.rankListResult = .failure(URLError(.timedOut))
        let vm = FeedViewModel(service: service)

        await vm.fetchInitialFeed()
        #expect(vm.state == .failed(message: URLError(.timedOut).localizedDescription))
        #expect(service.modPageCallCount == 1)
        #expect(service.rankListCallCount == 1)

        service.modPageResult = .success(makeSuccessModPage())
        service.rankListResult = .success(makeRankList())

        await vm.fetchInitialFeed()

        #expect(vm.state == .loaded)
        #expect(vm.rankMovies.count == 1)
        #expect(service.modPageCallCount == 2)
        #expect(service.rankListCallCount == 2)
    }

    // MARK: - 幂等守卫

    @Test func fetch_whenLoading_doesNotReissueRequests() async {
        let service = MockFeedService()
        service.modPageResult = .success(makeSuccessModPage())
        service.rankListResult = .success(makeRankList())
        let vm = FeedViewModel(service: service)
        vm.state = .loading

        await vm.fetchInitialFeed()

        #expect(vm.state == .loading)
        #expect(service.modPageCallCount == 0)
        #expect(service.rankListCallCount == 0)
    }

    @Test func fetch_whenLoaded_doesNotReissueRequests() async {
        let service = MockFeedService()
        let vm = FeedViewModel(service: service)
        vm.state = .loaded

        await vm.fetchInitialFeed()

        #expect(vm.state == .loaded)
        #expect(service.modPageCallCount == 0)
        #expect(service.rankListCallCount == 0)
    }

    // MARK: - 频道切换

    @Test func fetch_initialFeed_usesMovieChannelParameters() async {
        let service = MockFeedService()
        service.modPageResult = .success(makeSuccessModPage())
        service.rankListResult = .success(makeRankList())
        let vm = FeedViewModel(service: service)

        await vm.fetchInitialFeed()

        #expect(service.modPageIDs == [FeedChannel.movie.modPageID])
        #expect(service.rankSeasonTypes == [FeedChannel.movie.rankSeasonType])
        #expect(vm.currentChannel == .movie)
    }

    @Test func switchChannel_toAnime_reloadsWithAnimeParameters() async {
        let service = MockFeedService()
        service.modPageResult = .success(makeSuccessModPage())
        service.rankListResult = .success(makeRankList())
        let vm = FeedViewModel(service: service)
        await vm.fetchInitialFeed()

        await vm.switchChannel(to: .anime)

        #expect(vm.currentChannel == .anime)
        #expect(service.modPageIDs == [FeedChannel.movie.modPageID, FeedChannel.anime.modPageID])
        #expect(service.rankSeasonTypes == [FeedChannel.movie.rankSeasonType, FeedChannel.anime.rankSeasonType])
        #expect(vm.state == .loaded)
        #expect(vm.rankMovies.count == 1)
        #expect(vm.bannerMovies.count == 1)
        #expect(vm.exclusiveMovies.count == 1)
        #expect(vm.comingSoonMovies.count == 1)
    }

    @Test func switchChannel_sameChannel_doesNotReissueRequests() async {
        let service = MockFeedService()
        let vm = FeedViewModel(service: service)
        vm.state = .loaded

        await vm.switchChannel(to: .movie)

        #expect(service.modPageCallCount == 0)
        #expect(service.rankListCallCount == 0)
    }

    @Test func switchChannel_whileLoading_isIgnored() async {
        let service = MockFeedService()
        let vm = FeedViewModel(service: service)
        vm.state = .loading

        await vm.switchChannel(to: .anime)

        #expect(vm.currentChannel == .movie)
        #expect(service.modPageCallCount == 0)
        #expect(service.rankListCallCount == 0)
    }

    /// 竞态回归：切换进行中用户又选了另一个频道，最新选择不应被丢弃或回滚。
    /// 旧实现里第二次请求被 `state == .loading` 静默吞掉，第一次完成后调用方会把
    /// 选中态回写回旧频道（侧边栏高亮被拉回）。修复后应记为 pending 并接着切过去。
    /// 复现方式：首次（番剧）请求在途时，由 mock 钩子以真实入口发起第二次选择 ——
    /// 此刻 isSwitchingChannel == true，应走 pending 路径。单任务驱动、完全确定性。
    @Test func switchChannel_duringInFlightSwitch_appliesLatestPendingChannel() async {
        let service = MockFeedService()
        service.modPageResult = .success(makeSuccessModPage())
        service.rankListResult = .success(makeRankList())
        let vm = FeedViewModel(service: service)

        // 首次(番剧)请求进入时,同步发起第二次选择(电影)
        service.onModPageCalled = { [weak vm] in
            guard let vm else { return }
            await vm.switchChannel(to: .movie)
        }

        await vm.switchChannel(to: .anime)

        #expect(vm.currentChannel == .movie)
        #expect(service.modPageIDs == [FeedChannel.anime.modPageID, FeedChannel.movie.modPageID])
        #expect(vm.state == .loaded)
    }

    /// 竞态回归：anime -> movie -> anime 在第一个请求完成前连续选择三次。
    /// 预期最终频道为 .anime（用户最后一次选择），不应回滚到 .movie。
    /// 旧实现会在第三次选择 .anime 时因 currentChannel == .anime 提前返回，
    /// 导致 pending 保留为 .movie，第一个请求完成后错误地切回 .movie。
    /// 修复后：pending 被更新为 .anime，首个请求完成后因 pending == currentChannel 不再发起额外请求，
    /// 最终频道正确保持为 .anime。
    @Test func switchChannel_animeToMovieToAnimeDuringFirstRequest_appliesFinalAnimeSelection() async {
        let service = MockFeedService()
        service.modPageResult = .success(makeSuccessModPage())
        service.rankListResult = .success(makeRankList())
        let vm = FeedViewModel(service: service)

        // 首次(番剧)请求进入时,先切 movie，再切 anime
        service.onModPageCalled = { [weak vm] in
            guard let vm else { return }
            await vm.switchChannel(to: .movie)
            await vm.switchChannel(to: .anime)
        }

        await vm.switchChannel(to: .anime)

        #expect(vm.currentChannel == .anime)
        // 仅发起首个 anime 请求：pending 最终为 .anime，与 currentChannel 相同，
        // while 循环不再继续（避免对同一频道重复请求），这是预期行为。
        #expect(service.modPageIDs == [FeedChannel.anime.modPageID])
        #expect(vm.state == .loaded)
    }

    @Test func switchChannel_failure_fallsBackToFailedState() async {
        let service = MockFeedService()
        service.modPageResult = .success(makeSuccessModPage())
        service.rankListResult = .success(makeRankList())
        let vm = FeedViewModel(service: service)
        await vm.fetchInitialFeed()

        let expected = URLError(.timedOut)
        service.modPageResult = .failure(expected)
        service.rankListResult = .failure(expected)

        await vm.switchChannel(to: .anime)

        #expect(vm.state == .failed(message: expected.localizedDescription))
        #expect(vm.rankMovies.isEmpty)
        #expect(vm.bannerMovies.isEmpty)
        #expect(vm.exclusiveMovies.isEmpty)
        #expect(vm.comingSoonMovies.isEmpty)
    }
}
