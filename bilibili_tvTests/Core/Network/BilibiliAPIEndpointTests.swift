//
//  BilibiliAPIEndpointTests.swift
//  bilibili_tvTests
//
//  BilibiliAPI 端点枚举契约测试：
//  锁定 host + path + queryItems 的组装结果，防止重构后端点语义漂移。
//

import Foundation
import Testing

@testable import bilibili_tv

struct BilibiliAPIEndpointTests {
    private func queryItems(_ api: BilibiliAPI) -> [String: String] {
        Dictionary(uniqueKeysWithValues: api.queryItems.map { ($0.name, $0.value ?? "") })
    }

    // MARK: - host / path 契约

    @Test func feedEndpoints_useAPIHost() {
        #expect(BilibiliAPI.feed(cursor: 0).urlString == "https://api.bilibili.com/pgc/page/web/feed")
        #expect(BilibiliAPI.tvModPage(pageId: 1).urlString == "https://api.bilibili.com/x/tv/modpage_v2")
        #expect(BilibiliAPI.rankList(day: 3, seasonType: 2).urlString == "https://api.bilibili.com/pgc/season/rank/web/list")
    }

    @Test func pgcDetailEndpoints_useAPIHost() {
        #expect(BilibiliAPI.seasonDetail(seasonId: 33_354, epId: nil).urlString == "https://api.bilibili.com/pgc/view/web/season")
        #expect(BilibiliAPI.epDetail(epId: 320_665).urlString == "https://api.bilibili.com/pgc/view/web/ep")
    }

    @Test func playbackEndpoints_useAPIHost() {
        #expect(BilibiliAPI.playURL(epId: 320_665, cid: nil, qn: 80).urlString == "https://api.bilibili.com/pgc/player/web/playurl")
        #expect(BilibiliAPI.drmCheck(epId: 320_665, cid: nil, qn: 80).urlString == "https://api.bilibili.com/ogv/player/pre/check/drm")
    }

    @Test func loginEndpoints_usePassportHost() {
        #expect(BilibiliAPI.qrGenerate.urlString == "https://passport.bilibili.com/x/passport-login/web/qrcode/generate")
        #expect(BilibiliAPI.qrPoll(qrcodeKey: "key").urlString == "https://passport.bilibili.com/x/passport-login/web/qrcode/poll")
    }

    @Test func historyAndDanmakuEndpoints_useAPIHost() {
        #expect(BilibiliAPI.history(ps: 20).urlString == "https://api.bilibili.com/x/v2/history")
        #expect(BilibiliAPI.heartbeat.urlString == "https://api.bilibili.com/x/click-interface/web/heartbeat")
        #expect(BilibiliAPI.danmakuSegment(cid: 183_896_111, segmentIndex: 1).urlString == "https://api.bilibili.com/x/v2/dm/list/seg.so")
    }

    // MARK: - queryItems 契约

    @Test func movieFeed_queryItems_matchOriginalSemantics() {
        let items = queryItems(.feed(cursor: 0))
        #expect(items["name"] == "movie")
        #expect(items["coursor"] == "0")
        #expect(items["new_cursor_status"] == "true")
    }

    @Test func tvModPage_queryItems_areExact() {
        let items = queryItems(.tvModPage(pageId: 531))
        #expect(items["page_id"] == "531")
        #expect(items["fourk"] == "1")
        #expect(items["build"] == "108700")
        #expect(items["mobi_app"] == "android_tv_yst")
        #expect(items["platform"] == "android")
    }

    @Test func seasonDetail_onlyEmitsProvidedIDs() {
        let seasonOnly = queryItems(.seasonDetail(seasonId: 33_354, epId: nil))
        #expect(seasonOnly["season_id"] == "33354")
        #expect(seasonOnly["ep_id"] == nil)

        let epOnly = queryItems(.seasonDetail(seasonId: nil, epId: 320_665))
        #expect(epOnly["season_id"] == nil)
        #expect(epOnly["ep_id"] == "320665")
    }

    @Test func playURL_queryItems_includeQnAndOptionalIDs() {
        let items = queryItems(.playURL(epId: 320_665, cid: nil, qn: 80))
        #expect(items["qn"] == "80")
        #expect(items["fnval"] == "4048")
        #expect(items["fnver"] == "0")
        #expect(items["fourk"] == "1")
        #expect(items["ep_id"] == "320665")

        let cidOnly = queryItems(.playURL(epId: nil, cid: 183_896_111, qn: 80))
        #expect(cidOnly["ep_id"] == nil)
        #expect(cidOnly["cid"] == "183896111")
    }

    @Test func drmCheck_queryItems_includeDrmTechType() {
        let items = queryItems(.drmCheck(epId: 320_665, cid: nil, qn: 80))
        #expect(items["drm_tech_type"] == "2")
        #expect(items["qn"] == "80")
        #expect(items["ep_id"] == "320665")
    }

    @Test func qrPoll_queryItems_carryKey() {
        #expect(queryItems(.qrPoll(qrcodeKey: "abc123"))["qrcode_key"] == "abc123")
        #expect(queryItems(.qrGenerate).isEmpty)
    }

    @Test func danmakuSegment_queryItems_carryOidAndIndex() {
        let items = queryItems(.danmakuSegment(cid: 183_896_111, segmentIndex: 2))
        #expect(items["type"] == "1")
        #expect(items["oid"] == "183896111")
        #expect(items["segment_index"] == "2")
    }
}
