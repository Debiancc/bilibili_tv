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

import Testing
import SwiftUI
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

    // MARK: - HeroBannerView

    @Test func heroBannerView_withLogoAndDescriptionAndMeta_buildsBody() {
        let item = makeItem(
            logo: "https://example.com/logo.png",
            ogvFusionInfo: OgvFusionInfo(category: "Action", tag: "Thrilling"),
            desc: "A short synopsis of the movie."
        )
        let view = HeroBannerView(item: item)
        _ = view.body
    }

    @Test func heroBannerView_withoutLogo_fallsBackToTitleTextWithoutCrashing() {
        let item = makeItem(logo: nil)
        let view = HeroBannerView(item: item)
        _ = view.body
    }

    @Test func heroBannerView_withEmptyDescription_skipsDescriptionBlockWithoutCrashing() {
        let item = makeItem(desc: "")
        let view = HeroBannerView(item: item)
        _ = view.body
    }

    @Test func heroBannerView_withNilTitleAndNoLogo_usesPlaceholderWithoutCrashing() {
        let item = makeItem(title: nil, logo: nil)
        let view = HeroBannerView(item: item)
        _ = view.body
    }

    @Test func heroBannerView_withEmptyFusionInfoFields_omitsMetaLineWithoutCrashing() {
        let item = makeItem(ogvFusionInfo: OgvFusionInfo(category: "", tag: nil))
        let view = HeroBannerView(item: item)
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

    @Test func contentView_loadingStateWithNoData_buildsBody() {
        let vm = FeedViewModel()
        vm.isLoading = true
        let view = ContentView(viewModel: vm)
        _ = view.body
    }

    @Test func contentView_errorState_buildsBody() {
        let vm = FeedViewModel()
        vm.errorMessage = "network error"
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