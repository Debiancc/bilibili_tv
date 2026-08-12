//
//  MovieDetailViewModelTests.swift
//  bilibili_tvTests
//
//  阶段二：MovieDetailViewModel 状态机（MovieDetailState）冒烟 + 行为断言测试。
//  注入 MockMovieDetailService（Result 脚本 + 调用计数），断言：
//  - idle 初始不发起请求
//  - 成功态 computed 属性（title/episodes/rating/styles/pubYear/description）与 seasonDetail 一致
//  - 失败态携带预期文案
//  - 失败后重试真的重新发起请求
//  - loading/loaded 幂等（不重复请求）
//  - 缺 seasonId/epId 时不发起请求
//

import Foundation
import Testing

@testable import bilibili_tv

/// Mock 详情服务：按脚本返回预置结果，驱动 MovieDetailViewModel 状态机测试
@MainActor
final class MockMovieDetailService: MovieDetailServicing {
    var result: Result<PGCSeasonDetail, Error> = .failure(URLError(.badServerResponse))

    private(set) var callCount = 0

    func fetchSeasonDetail(seasonId: Int?, epId: Int?) async throws -> PGCSeasonDetail {
        callCount += 1
        return try result.get()
    }
}

@MainActor
struct MovieDetailViewModelTests {
    // MARK: - Fixtures

    private func makeFeedItem(seasonId: Int? = 33_354, episodeId: Int? = 320_665) -> FeedItem {
        FeedItem(
            title: "夏洛特烦恼",
            subtitle: "马冬梅的排列组合",
            cover: "https://example.com/cover.png",
            rating: "9.5", badge: nil, link: nil,
            episodeId: episodeId, seasonId: seasonId,
            stat: nil, rank: nil, indexShow: nil, rankTag: nil,
            brief: "feed 简介", overlayImg: nil, logo: nil,
            ogvFusionInfo: OgvFusionInfo(category: "喜剧", tag: nil), newEp: nil, desc: nil
        )
    }

    private func makeSeasonDetail() -> PGCSeasonDetail {
        PGCSeasonDetail(
            seasonId: 33_354,
            seasonTitle: "夏洛特烦恼",
            title: "夏洛特烦恼",
            typeName: "电影",
            cover: "https://example.com/detail-cover.png",
            squareCover: nil,
            evaluate: "详情页简介：昔日校花秋雅的婚礼……",
            alias: nil,
            rating: PGCRating(score: 9.3, count: 2_000),
            areas: [],
            styles: ["喜剧", "青春", "穿越"],
            publish: PGCPublishInfo(pubTime: "2015-09-27 00:00:00", pubTimeShow: "2015年", isFinish: 1, isStarted: 1),
            stat: nil,
            actors: nil,
            staff: nil,
            episodes: [
                PGCEpisode(
                    parsedId: 1, epId: 320_665, aid: nil, cid: nil, bvid: nil,
                    title: "1", longTitle: "梦回青春", cover: nil, badge: nil,
                    duration: 6_000_000, link: nil, showTitle: nil
                ),
                PGCEpisode(
                    parsedId: 2, epId: 320_666, aid: nil, cid: nil, bvid: nil,
                    title: "2", longTitle: "婚礼风波", cover: nil, badge: nil,
                    duration: 6_000_000, link: nil, showTitle: nil
                )
            ],
            section: [],
            seasons: [],
            payment: nil,
            rights: nil,
            userStatus: nil
        )
    }

    // MARK: - 冒烟：idle 初始态

    @Test func idleState_doesNotIssueRequest() async {
        let service = MockMovieDetailService()
        let vm = MovieDetailViewModel(feedItem: makeFeedItem(), service: service)

        #expect(vm.state == .idle)
        #expect(vm.seasonDetail == nil)
        #expect(service.callCount == 0)
    }

    // MARK: - 成功路径：computed 属性与 seasonDetail 一致

    @Test func fetch_success_transitionsToLoadedAndComputedPropsMatchSeasonDetail() async {
        let service = MockMovieDetailService()
        service.result = .success(makeSeasonDetail())
        let vm = MovieDetailViewModel(feedItem: makeFeedItem(), service: service)

        await vm.fetchDetail()

        #expect(vm.state == .loaded)
        #expect(service.callCount == 1)
        #expect(vm.title == "夏洛特烦恼")
        #expect(vm.episodes.count == 2)
        #expect(vm.episodes.first?.epId == 320_665)
        #expect(vm.ratingText == "9.3")
        #expect(vm.stylesText == "喜剧 · 青春 · 穿越")
        #expect(vm.pubYear == "2015年")
        #expect(vm.description == "详情页简介：昔日校花秋雅的婚礼……")
        #expect(vm.typeNameText == "电影")
    }

    @Test func fetch_success_loadedState_usesSeasonDetailCoverNotFeedFallback() async {
        let service = MockMovieDetailService()
        service.result = .success(makeSeasonDetail())
        let vm = MovieDetailViewModel(feedItem: makeFeedItem(), service: service)

        await vm.fetchDetail()

        // seasonDetail.cover 非 nil 时优先 seasonDetail，且追加 3840w_2160h CDN 后缀
        let urlString = vm.coverURL?.absoluteString ?? ""
        #expect(urlString.hasPrefix("https://example.com/detail-cover.png@3840w_2160h_1e.webp"))
        #expect(vm.coverURL != URL(string: "https://example.com/cover.png"))
    }

    // MARK: - 失败路径

    @Test func fetch_failure_carriesExpectedErrorMessage() async {
        let service = MockMovieDetailService()
        let expected = URLError(.notConnectedToInternet)
        service.result = .failure(expected)
        let vm = MovieDetailViewModel(feedItem: makeFeedItem(), service: service)

        await vm.fetchDetail()

        #expect(vm.state == .failed(message: expected.localizedDescription))
        #expect(vm.seasonDetail == nil)
        // 失败态下 computed 属性回落到 feedItem
        #expect(vm.title == "夏洛特烦恼")
        #expect(vm.ratingText == "9.5")
        #expect(vm.description == "feed 简介")
        #expect(vm.episodes.isEmpty)
    }

    // MARK: - 失败后重试真的重新发起请求

    @Test func fetch_afterFailure_retryReissuesRequestAndRecovers() async {
        let service = MockMovieDetailService()
        service.result = .failure(URLError(.timedOut))
        let vm = MovieDetailViewModel(feedItem: makeFeedItem(), service: service)

        await vm.fetchDetail()
        #expect(vm.state == .failed(message: URLError(.timedOut).localizedDescription))
        #expect(service.callCount == 1)

        service.result = .success(makeSeasonDetail())

        await vm.fetchDetail()

        #expect(vm.state == .loaded)
        #expect(vm.episodes.count == 2)
        #expect(service.callCount == 2)
    }

    // MARK: - 幂等守卫

    @Test func fetch_whenLoading_doesNotReissueRequest() async {
        let service = MockMovieDetailService()
        service.result = .success(makeSeasonDetail())
        let vm = MovieDetailViewModel(feedItem: makeFeedItem(), service: service)
        vm.state = .loading

        await vm.fetchDetail()

        #expect(vm.state == .loading)
        #expect(vm.seasonDetail == nil)
        #expect(service.callCount == 0)
    }

    @Test func fetch_whenLoaded_doesNotReissueRequest() async {
        let service = MockMovieDetailService()
        service.result = .success(makeSeasonDetail())
        let vm = MovieDetailViewModel(feedItem: makeFeedItem(), service: service)
        vm.state = .loaded
        vm.seasonDetail = makeSeasonDetail()

        await vm.fetchDetail()

        #expect(vm.state == .loaded)
        #expect(vm.episodes.count == 2)
        #expect(service.callCount == 0)
    }

    // MARK: - 缺 id 不请求

    @Test func fetch_whenMissingBothIds_doesNotRequestAndStaysIdle() async {
        let service = MockMovieDetailService()
        let vm = MovieDetailViewModel(feedItem: makeFeedItem(seasonId: nil, episodeId: nil), service: service)

        await vm.fetchDetail()

        #expect(vm.state == .idle)
        #expect(service.callCount == 0)
    }

    @Test func fetch_whenMissingIdsButFailed_retryAlsoDoesNotRequest() async {
        let service = MockMovieDetailService()
        let vm = MovieDetailViewModel(feedItem: makeFeedItem(seasonId: nil, episodeId: nil), service: service)
        vm.state = .failed(message: "previous error")

        await vm.fetchDetail()

        // 缺 id 时即使处于可重试的 failed 态也不发起请求（保持原逻辑：仅打印警告）
        #expect(vm.state == .failed(message: "previous error"))
        #expect(service.callCount == 0)
    }

    // MARK: - mock 数据自检（供 snapshot / 焦点导航使用）

    @Test func mock_stateIsLoadedWithEpisodes() {
        let vm = MovieDetailViewModel.mock

        #expect(vm.state == .loaded)
        #expect(vm.episodes.count == 3)
        #expect(vm.title == "夏洛特烦恼")
    }
}
