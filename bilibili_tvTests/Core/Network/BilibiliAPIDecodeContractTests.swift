//
//  BilibiliAPIDecodeContractTests.swift
//  bilibili_tvTests
//
//  JSON 解码契约测试：用真实抓包夹具逐端点断言
//  「重构后响应仍能解码为对应 Model」，防止字段/结构漂移。
//

import Foundation
import Testing

@testable import bilibili_tv

struct BilibiliAPIDecodeContractTests {
    private func fixtureData(_ name: String) throws -> Data {
        let bundle = Bundle(for: BundleAnchor.self)
        let url = try #require(bundle.url(forResource: name, withExtension: "json"))
        return try Data(contentsOf: url)
    }

    // MARK: - movieFeed → FeedResponse

    @Test func movieFeedFixture_decodesToFeedResponse() throws {
        let response = try JSONDecoder().decode(FeedResponse.self, from: fixtureData("movieFeed"))

        #expect(response.code == 0)
        let data = try #require(response.data)
        #expect((data.items ?? []).isEmpty == false)
        #expect((data.items ?? []).count == 14)
    }

    // MARK: - seasonDetail → PGCSeasonDetailResponse

    @Test func seasonDetailFixture_decodesToPGCSeasonDetail() throws {
        let response = try JSONDecoder().decode(PGCSeasonDetailResponse.self, from: fixtureData("seasonDetail"))

        #expect(response.code == 0)
        let detail = try #require(response.result)
        #expect(detail.seasonId == 33_354)
        #expect(detail.title == "夏洛特烦恼")
        #expect((detail.episodes ?? []).isEmpty == false)
        #expect(detail.episodes?.first?.epId == 320_665)
        #expect(detail.rating?.score == 9.5)
    }

    // MARK: - playURL → PlayURLResponse

    @Test func playURLFixture_decodesToPlayURLResponse() throws {
        let response = try JSONDecoder().decode(PlayURLResponse.self, from: fixtureData("playURL"))

        #expect(response.code == 0)
        let result = try #require(response.activeResult)
        #expect(result.isPreview == 1)
        #expect(result.errorCode == -10_403)
        #expect(result.isPreviewOnly == true)
        #expect((result.durl ?? []).isEmpty == false)
    }
}

/// Bundle 定位锚点（Swift Testing 无 NSObject 锚，用此类取测试 Bundle）
private final class BundleAnchor {}
