//
//  PlaybackContextTests.swift
//  bilibili_tvTests
//
//  Phase 1: PlaybackContext 工厂契约测试（TDD RED 先行）。
//  覆盖 banner(_:)/resume(_:) 的逐字段映射、可选字段容错、resumeTime 换算与
//  实例 id 唯一性（同一内容重复触发播放需生成新 id，fullScreenCover(item:) 才能重新呈现）。
//

import Foundation
import Testing

@testable import bilibili_tv

@MainActor
struct PlaybackContextTests {
    // MARK: - Helpers

    private func makeItem(
        title: String? = "测试影片",
        subtitle: String? = "副标题",
        cover: String? = "https://example.com/cover.png",
        episodeId: Int? = 100,
        seasonId: Int? = 200
    ) -> FeedItem {
        FeedItem(
            title: title,
            subtitle: subtitle,
            cover: cover,
            rating: nil,
            badge: nil,
            link: nil,
            episodeId: episodeId,
            seasonId: seasonId,
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

    private func makeEntry(
        seasonId: Int? = 200,
        epId: Int? = 100,
        title: String = "测试剧集",
        episodeTitle: String? = "第1话",
        coverURLString: String? = "https://example.com/cover.png",
        progress: Int = 925
    ) -> LocalWatchHistoryEntry {
        LocalWatchHistoryEntry(
            seasonId: seasonId,
            epId: epId,
            cid: 123_456,
            title: title,
            episodeTitle: episodeTitle,
            coverURLString: coverURLString,
            progress: progress,
            duration: 1_481,
            viewAt: 1_588_831_600
        )
    }

    // MARK: - banner(_:)

    @Test("给定 Hero 横幅 item → banner 工厂逐字段映射")
    func bannerFactoryMapsAllFeedItemFields() {
        // given
        let item = makeItem()

        // when
        let context = PlaybackContext.banner(item)

        // then
        #expect(context.epId == item.episodeId)
        #expect(context.seasonId == item.seasonId)
        #expect(context.title == item.title)
        #expect(context.subtitle == item.subtitle)
        #expect(context.coverURL == item.secureCoverURL)
        #expect(context.coverURL != nil)
        #expect(context.resumeTime == 0)
    }

    @Test("给定可选字段全为 nil 的 Hero item → banner 工厂产出全 nil 上下文且不崩溃")
    func bannerFactoryHandlesNilFields() {
        // given
        let item = makeItem(title: nil, subtitle: nil, cover: nil, episodeId: nil, seasonId: nil)

        // when
        let context = PlaybackContext.banner(item)

        // then
        #expect(context.epId == nil)
        #expect(context.seasonId == nil)
        #expect(context.title == nil)
        #expect(context.subtitle == nil)
        #expect(context.coverURL == nil)
        #expect(context.resumeTime == 0)
    }

    // MARK: - resume(_:)

    @Test("给定续播记录 → resume 工厂逐字段映射,进度换算为秒级 Double")
    func resumeFactoryMapsAllEntryFields() {
        // given
        let entry = makeEntry(progress: 925)

        // when
        let context = PlaybackContext.resume(entry)

        // then
        #expect(context.epId == entry.epId)
        #expect(context.seasonId == entry.seasonId)
        #expect(context.title == entry.title)
        #expect(context.subtitle == entry.episodeTitle)
        #expect(context.coverURL == entry.secureCoverURL)
        #expect(context.coverURL != nil)
        #expect(context.resumeTime == 925.0)
    }

    @Test("给定可选字段全为 nil 的续播记录 → resume 工厂产出全 nil 上下文(标题除外)且不崩溃")
    func resumeFactoryHandlesNilFields() {
        // given
        let entry = makeEntry(seasonId: nil, epId: nil, episodeTitle: nil, coverURLString: nil, progress: 0)

        // when
        let context = PlaybackContext.resume(entry)

        // then
        #expect(context.epId == nil)
        #expect(context.seasonId == nil)
        #expect(context.title == entry.title)
        #expect(context.subtitle == nil)
        #expect(context.coverURL == nil)
        #expect(context.resumeTime == 0.0)
    }

    // MARK: - 换算与标识

    @Test("给定进度为 0 的记录 → resumeTime 精确为 0.0(续播起点=从头播放)")
    func resumeTimeConvertsZeroProgressExactly() {
        // given
        let entry = makeEntry(progress: 0)

        // when
        let context = PlaybackContext.resume(entry)

        // then
        #expect(context.resumeTime == 0.0)
    }

    @Test("给定同一数据两次构造 → 两个上下文 id 互不相同(重复播放可重新呈现)")
    func factoryProducesUniqueIDsPerCall() {
        // given
        let item = makeItem()

        // when
        let first = PlaybackContext.banner(item)
        let second = PlaybackContext.banner(item)

        // then
        #expect(first.id != second.id)
    }
}
