//
//  FeedViewModelMockTests.swift
//  bilibili_tvTests
//
//  Tests for FeedViewModel.mock, ensuring the mock data set (updated in this PR
//  to also populate the new `desc: nil` argument on every FeedItem) still builds
//  a consistent, well-formed preview/mock state.
//

import Testing

@testable import bilibili_tv

@MainActor
struct FeedViewModelMockTests {
    @Test func mock_stateIsLoaded() {
        let vm = FeedViewModel.mock

        #expect(vm.state == .loaded)
    }

    @Test func mock_populatesAllShelvesWithExpectedCounts() {
        let vm = FeedViewModel.mock

        #expect(vm.rankMovies.count == 3)
        #expect(vm.exclusiveMovies.count == 2)
        #expect(vm.comingSoonMovies.count == 2)
        #expect(vm.bannerMovies.count == 3)
    }

    @Test func mock_allItemsAcrossShelves_haveNilDesc() {
        let vm = FeedViewModel.mock
        let allItems = vm.rankMovies + vm.exclusiveMovies + vm.comingSoonMovies + vm.bannerMovies

        #expect(!allItems.isEmpty)
        for item in allItems {
            #expect(item.desc == nil)
        }
    }

    @Test func mock_allItemsAcrossShelves_haveNilNewEp() {
        let vm = FeedViewModel.mock
        let allItems = vm.rankMovies + vm.exclusiveMovies + vm.comingSoonMovies + vm.bannerMovies

        for item in allItems {
            #expect(item.newEp == nil)
        }
    }

    @Test func mock_firstRankItem_retainsExpectedCoreFields() {
        let vm = FeedViewModel.mock
        let first = vm.rankMovies[0]

        #expect(first.title == "秦牧化身月亮守，获得史诗级载具！")
        #expect(first.rating == "9.6")
        #expect(first.episodeId == 4_983_242)
        #expect(first.seasonId == 45_969)
        #expect(first.ogvFusionInfo?.category == "国创")
    }
}
