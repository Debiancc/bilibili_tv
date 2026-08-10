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

    func fetchTVModPage(pageId: Int) async throws -> TVModPageResponse {
        modPageCallCount += 1
        return try modPageResult.get()
    }

    func fetchMovieRankList(day: Int, seasonType: Int) async throws -> [FeedItem] {
        rankListCallCount += 1
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
}
