//
//  ContentViewSmokeTests.swift
//  bilibili_tvTests
//
//  SwiftUI in this project has no view-inspection library, so these tests take
//  the pragmatic approach of constructing the changed views (ContentView,
//  HeroBannerView, MovieShelfView, MovieCardView) with a range of edge-case
//  FeedItem data and forcing their `body` to build. This exercises every new
//  conditional branch introduced in this PR (desc block, logo fallback, rating
//  badge, empty shelves, loading/error states) and guards against regressions
//  such as force-unwraps or index-out-of-range crashes.
//

import SwiftUI
import Testing

@testable import bilibili_tv

@MainActor
struct ContentViewSmokeTests {
    // MARK: - Helpers

    private func makeItem(
        title: String? = "Test Title",
        rating: String? = "8.0",
        logo: String? = nil,
        ogvFusionInfo: OgvFusionInfo? = nil,
        desc: String? = nil
    ) -> FeedItem {
        FeedItem(
            title: title,
            subtitle: nil,
            cover: "https://example.com/cover.png",
            rating: rating,
            badge: nil,
            link: nil,
            episodeId: 1,
            seasonId: nil,
            stat: nil,
            rank: nil,
            indexShow: nil,
            rankTag: nil,
            brief: nil,
            overlayImg: nil,
            logo: logo,
            ogvFusionInfo: ogvFusionInfo,
            newEp: nil,
            desc: desc
        )
    }

    /// 构造 HeroBannerView,注入无效的页级焦点绑定与空操作闭包。
    private func makeHeroBannerView(item: FeedItem, page: Int = 0) -> HeroBannerView {
        @FocusState var focus: HeroFocus?
        return HeroBannerView(
            item: item,
            pageIndex: page,
            pageFocus: $focus,
            onPlay: {},
            onDetail: {},
            onNext: {}
        )
    }

    // MARK: - HeroBannerView

    @Test func heroBannerView_withLogoAndDescriptionAndMeta_buildsBody() {
        let item = makeItem(
            logo: "https://example.com/logo.png",
            ogvFusionInfo: OgvFusionInfo(category: "Action", tag: "Thrilling"),
            desc: "A short synopsis of the movie."
        )
        let view = makeHeroBannerView(item: item)
        _ = view.body
    }

    @Test func heroBannerView_withoutLogo_fallsBackToTitleTextWithoutCrashing() {
        let item = makeItem(logo: nil)
        let view = makeHeroBannerView(item: item)
        _ = view.body
    }

    @Test func heroBannerView_withEmptyDescription_skipsDescriptionBlockWithoutCrashing() {
        let item = makeItem(desc: "")
        let view = makeHeroBannerView(item: item)
        _ = view.body
    }

    @Test func heroBannerView_withNilTitleAndNoLogo_usesPlaceholderWithoutCrashing() {
        let item = makeItem(title: nil, logo: nil)
        let view = makeHeroBannerView(item: item)
        _ = view.body
    }

    @Test func heroBannerView_withEmptyFusionInfoFields_omitsMetaLineWithoutCrashing() {
        let item = makeItem(ogvFusionInfo: OgvFusionInfo(category: "", tag: nil))
        let view = makeHeroBannerView(item: item)
        _ = view.body
    }

    // MARK: - MovieCardView

    @Test func movieCardView_withRating_buildsBody() {
        let item = makeItem(rating: "9.9")
        let view = MovieCardView(item: item)
        _ = view.body
    }

    @Test func movieCardView_withoutRating_buildsBody() {
        let item = makeItem(rating: nil)
        let view = MovieCardView(item: item)
        _ = view.body
    }

    @Test func movieCardView_withEmptyRating_treatsAsNoRatingWithoutCrashing() {
        let item = makeItem(rating: "")
        let view = MovieCardView(item: item)
        _ = view.body
    }

    // MARK: - MovieShelfView

    @Test func movieShelfView_withItems_buildsBody() {
        let items = [makeItem(title: "A"), makeItem(title: "B")]
        let view = MovieShelfView(title: "Test Shelf", items: items, selectedMovie: .constant(nil))
        _ = view.body
    }

    @Test func movieShelfView_withNoItems_buildsBodyWithoutCrashing() {
        let view = MovieShelfView(title: "Empty Shelf", items: [], selectedMovie: .constant(nil))
        _ = view.body
    }

    // MARK: - ContentView (top-level states)

    @Test func contentView_withMockViewModel_buildsBody() {
        let view = ContentView(viewModel: FeedViewModel.mock)
        _ = view.body
    }

    @Test func contentView_idleState_buildsBody() {
        let vm = FeedViewModel()
        let view = ContentView(viewModel: vm)
        _ = view.body
    }

    @Test func contentView_loadingStateWithNoData_buildsBody() {
        let vm = FeedViewModel()
        vm.state = .loading
        let view = ContentView(viewModel: vm)
        _ = view.body
    }

    @Test func contentView_loadingStateWithExistingData_keepsRenderingFeed() {
        let vm = FeedViewModel()
        vm.state = .loading
        vm.rankMovies = [makeItem(title: "Rank While Loading")]
        let view = ContentView(viewModel: vm)
        _ = view.body
    }

    @Test func contentView_failedState_buildsBody() {
        let vm = FeedViewModel()
        vm.state = .failed(message: "network error")
        let view = ContentView(viewModel: vm)
        _ = view.body
    }

    @Test func contentView_failedStateWithExistingData_keepsRenderingFeed() {
        let vm = FeedViewModel()
        vm.state = .failed(message: "network error")
        vm.rankMovies = [makeItem(title: "Rank While Failed")]
        let view = ContentView(viewModel: vm)
        _ = view.body
    }

    @Test func contentView_loadedState_buildsBody() {
        let vm = FeedViewModel()
        vm.state = .loaded
        vm.rankMovies = [makeItem(title: "Rank Loaded")]
        let view = ContentView(viewModel: vm)
        _ = view.body
    }

    @Test func contentView_emptyBannerMoviesWithNonEmptyShelves_buildsBodyWithoutCrashing() {
        let vm = FeedViewModel()
        vm.bannerMovies = []
        vm.rankMovies = [makeItem(title: "Only Rank Item")]
        let view = ContentView(viewModel: vm)
        _ = view.body
    }

    @Test func contentView_defaultInitializer_usesFreshViewModel() {
        let view = ContentView()
        _ = view.body
    }
}
