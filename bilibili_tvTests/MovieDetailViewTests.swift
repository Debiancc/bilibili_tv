//
//  MovieDetailViewTests.swift
//  bilibili_tvTests
//
//  MovieDetailView's own body logic was not changed by this PR; the only
//  change was its #Preview passing the newly-added `newEp`/`desc` FeedItem
//  parameters. These tests confirm MovieDetailView still builds correctly
//  when given a FeedItem constructed with those new fields (mirroring the
//  updated preview), and with them entirely nil.
//

import Testing
import SwiftUI
@testable import bilibili_tv

@MainActor
struct MovieDetailViewTests {

    @Test func movieDetailView_withNewEpAndDescFields_buildsBodyWithoutCrashing() {
        let item = FeedItem(
            title: "夏洛特烦恼", subtitle: "马冬梅的排列组合",
            cover: "https://example.com/cover.png@3840w_2160h_1e.webp",
            rating: "9.5", badge: "DRM", link: "", episodeId: 320665, seasonId: 33354,
            stat: FeedStat(view: 34320099, danmaku: 0), rank: 1, indexShow: nil, rankTag: nil,
            brief: "剧情简介", overlayImg: nil, logo: nil, ogvFusionInfo: nil,
            newEp: NewEpInfo(indexShow: "更新至第1集"), desc: "一段全新的剧情描述"
        )

        let view = MovieDetailView(item: item)
        _ = view.body
    }

    @Test func movieDetailView_withAllOptionalFieldsNil_buildsBodyWithoutCrashing() {
        let item = FeedItem(
            title: nil, subtitle: nil, cover: nil, rating: nil, badge: nil, link: nil,
            episodeId: nil, seasonId: nil, stat: nil, rank: nil, indexShow: nil, rankTag: nil,
            brief: nil, overlayImg: nil, logo: nil, ogvFusionInfo: nil, newEp: nil, desc: nil
        )

        let view = MovieDetailView(item: item)
        _ = view.body
    }
}