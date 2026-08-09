//
//  FeedItemTests.swift
//  bilibili_tvTests
//
//  Tests for the `desc` field added to FeedItem (Codable + CodingKeys),
//  making sure JSON decode/encode round-trips correctly and that
//  backward compatibility with payloads missing "desc" is preserved.
//

import Foundation
import Testing

@testable import bilibili_tv

struct FeedItemTests {
    private func decode(_ json: String) throws -> FeedItem {
        try JSONDecoder().decode(FeedItem.self, from: Data(json.utf8))
    }

    // MARK: - Decoding `desc`

    @Test func decode_emptyJSON_allFieldsIncludingDescAreNil() throws {
        let item = try decode("{}")

        #expect(item.title == nil)
        #expect(item.desc == nil)
    }

    @Test func decode_missingDescKey_defaultsToNil() throws {
        let json = """
            {
                "title": "夏洛特烦恼",
                "sub_title": "马冬梅的排列组合"
            }
            """
        let item = try decode(json)

        #expect(item.title == "夏洛特烦恼")
        #expect(item.desc == nil)
    }

    @Test func decode_withDescKey_populatesValue() throws {
        let json = """
            {
                "title": "近战五行神兽？这是一场单方面的碾压！",
                "desc": "一段精彩的剧情简介"
            }
            """
        let item = try decode(json)

        #expect(item.desc == "一段精彩的剧情简介")
    }

    @Test func decode_withExplicitNullDesc_resultsInNil() throws {
        let json = """
            {
                "title": "Test",
                "desc": null
            }
            """
        let item = try decode(json)

        #expect(item.desc == nil)
    }

    @Test func decode_withEmptyStringDesc_preservesEmptyString() throws {
        let json = """
            {
                "desc": ""
            }
            """
        let item = try decode(json)

        #expect(item.desc?.isEmpty == true)
    }

    @Test func decode_realisticPayload_mapsDescAlongsideOtherSnakeCaseKeys() throws {
        let json = """
            {
                "title": "秦牧化身月亮守，获得史诗级载具！",
                "sub_title": "放牛少年，放牧诸神",
                "cover": "//i0.hdslb.com/bfs/tvcover/cover.png",
                "rating": "9.6",
                "badge": "独播",
                "link": "",
                "episode_id": 4983242,
                "season_id": 45969,
                "stat": { "view": 1990000000, "danmaku": 0 },
                "rank": 1,
                "index_show": "更新至第93话",
                "rank_tag": null,
                "brief": null,
                "overlay_img": null,
                "logo": "//i0.hdslb.com/bfs/tvcover/logo.png",
                "ogv_fusion_info": { "category": "国创", "tag": "热血 神魔 奇幻" },
                "new_ep": { "index_show": "更新至第93话" },
                "desc": "放牛少年意外获得史诗级载具的奇幻冒险故事"
            }
            """
        let item = try decode(json)

        #expect(item.title == "秦牧化身月亮守，获得史诗级载具！")
        #expect(item.subtitle == "放牛少年，放牧诸神")
        #expect(item.episodeId == 4_983_242)
        #expect(item.seasonId == 45_969)
        #expect(item.ogvFusionInfo?.category == "国创")
        #expect(item.newEp?.indexShow == "更新至第93话")
        #expect(item.desc == "放牛少年意外获得史诗级载具的奇幻冒险故事")
    }

    // MARK: - Encoding / round-trip

    @Test func encodeAndDecode_desc_roundTripsCorrectly() throws {
        let original = FeedItem(
            title: "Test Title", subtitle: nil, cover: nil, rating: nil, badge: nil,
            link: nil, episodeId: 42, seasonId: nil, stat: nil, rank: nil,
            indexShow: nil, rankTag: nil, brief: nil, overlayImg: nil, logo: nil,
            ogvFusionInfo: nil, newEp: nil, desc: "Round trip description"
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(FeedItem.self, from: data)

        #expect(decoded.desc == "Round trip description")
        #expect(decoded == original)
    }

    @Test func encodeAndDecode_nilDesc_roundTripsAsNil() throws {
        let original = FeedItem(
            title: "Test Title", subtitle: nil, cover: nil, rating: nil, badge: nil,
            link: nil, episodeId: 43, seasonId: nil, stat: nil, rank: nil,
            indexShow: nil, rankTag: nil, brief: nil, overlayImg: nil, logo: nil,
            ogvFusionInfo: nil, newEp: nil, desc: nil
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(FeedItem.self, from: data)

        #expect(decoded.desc == nil)
    }
}

struct PGCEpisodeTests {
    @Test func testFormattedDuration() {
        // Test nil duration
        let ep1 = PGCEpisode(
            parsedId: nil, epId: 1, aid: nil, cid: nil, bvid: nil, title: nil, longTitle: nil, cover: nil, badge: nil, duration: nil, link: nil, showTitle: nil)
        #expect(ep1.formattedDuration == nil)

        // Test under 1 hour (e.g. 5 minutes 30 seconds = 330 seconds = 330000 ms)
        let ep2 = PGCEpisode(
            parsedId: nil, epId: 2, aid: nil, cid: nil, bvid: nil, title: nil, longTitle: nil, cover: nil, badge: nil, duration: 330_000, link: nil,
            showTitle: nil)
        #expect(ep2.formattedDuration == "05:30")

        // Test exactly 1 hour (3600 seconds = 3600000 ms)
        let ep3 = PGCEpisode(
            parsedId: nil, epId: 3, aid: nil, cid: nil, bvid: nil, title: nil, longTitle: nil, cover: nil, badge: nil, duration: 3_600_000, link: nil,
            showTitle: nil)
        #expect(ep3.formattedDuration == "01:00:00")

        // Test over 1 hour (e.g. 1 hour 57 minutes 18 seconds = 7038 seconds = 7038000 ms)
        let ep4 = PGCEpisode(
            parsedId: nil, epId: 4, aid: nil, cid: nil, bvid: nil, title: nil, longTitle: nil, cover: nil, badge: nil, duration: 7_038_000, link: nil,
            showTitle: nil)
        #expect(ep4.formattedDuration == "01:57:18")
    }

    @Test func testFormattedTitle() {
        // Test with showTitle (takes priority)
        let ep1 = PGCEpisode(
            parsedId: nil, epId: 1, aid: nil, cid: nil, bvid: nil, title: "1", longTitle: "Subtitle", cover: nil, badge: nil, duration: nil, link: nil,
            showTitle: "Priority Title")
        #expect(ep1.formattedTitle == "Priority Title")

        // Test with numeric title and longTitle
        let ep2 = PGCEpisode(
            parsedId: nil, epId: 2, aid: nil, cid: nil, bvid: nil, title: "10", longTitle: "Princess", cover: nil, badge: nil, duration: nil, link: nil,
            showTitle: nil)
        #expect(ep2.formattedTitle == "第10集 Princess")

        // Test with non-numeric title
        let ep3 = PGCEpisode(
            parsedId: nil, epId: 3, aid: nil, cid: nil, bvid: nil, title: "SP1", longTitle: "Special", cover: nil, badge: nil, duration: nil, link: nil,
            showTitle: nil)
        #expect(ep3.formattedTitle == "SP1 Special")

        // Test with only longTitle
        let ep4 = PGCEpisode(
            parsedId: nil, epId: 4, aid: nil, cid: nil, bvid: nil, title: nil, longTitle: "Only Long Title", cover: nil, badge: nil, duration: nil, link: nil,
            showTitle: nil)
        #expect(ep4.formattedTitle == "Only Long Title")
    }
}
