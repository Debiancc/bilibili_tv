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
        #expect(data.items.isEmpty == false)
        #expect(data.items.count == 14)
    }

    // MARK: - tvModPage → TVModPageResponse（真实抓包 fixture）

    @Test func tvModPageFixture_decodesToTVModPageResponse() throws {
        let response = try JSONDecoder().decode(TVModPageResponse.self, from: fixtureData("tvModPage"))

        #expect(response.code == 0)
        #expect(response.data.isEmpty == false)
        // 覆盖 banner(61)/rank(39)/exclusive(63)/comingSoon(64) 模块类型
        let types = Set(response.data.map(\.type))
        #expect(types.contains(TVModuleType.banner.rawValue) || types.contains(TVModuleType.exclusive.rawValue) || types.contains(TVModuleType.rank.rawValue))
        #expect(response.data.contains { $0.data.isEmpty == false })
    }

    // MARK: - movieRankList → PGCListResponse（真实抓包 fixture）

    @Test func movieRankListFixture_decodesToPGCListResponse() throws {
        let response = try JSONDecoder().decode(PGCListResponse.self, from: fixtureData("movieRankList"))

        #expect(response.code == 0)
        let data = try #require(response.data)
        #expect(data.list.isEmpty == false)
        // 榜单条目应含排名与剧集信息
        #expect(data.list.contains { $0.seasonId != nil })
        #expect(data.list.contains { $0.rank != nil })
    }

    // MARK: - seasonDetail → PGCSeasonDetailResponse（真实抓包 fixture）

    @Test func seasonDetailFixture_decodesToPGCSeasonDetail() throws {
        let response = try JSONDecoder().decode(PGCSeasonDetailResponse.self, from: fixtureData("seasonDetail"))

        #expect(response.code == 0)
        let detail = try #require(response.result)
        // 真实抓包数据:season_id=157324《昭阳公主》,首集 ep_id=4697996(与 playurl 抓包一致)
        #expect(detail.seasonId == 157_324)
        #expect(detail.title == "昭阳公主")
        #expect(detail.episodes.isEmpty == false)
        #expect(detail.episodes.first?.epId == 4_697_996)
    }

    // MARK: - playURL → PlayURLResponse

    @Test func playURLFixture_decodesToPlayURLResponse() throws {
        let response = try JSONDecoder().decode(PlayURLResponse.self, from: fixtureData("playURL"))

        #expect(response.code == 0)
        let result = try #require(response.activeResult)
        #expect(result.isPreview == 1)
        #expect(result.errorCode == -10_403)
        #expect(result.isPreviewOnly == true)
        #expect(result.durl.isEmpty == false)
    }

    @Test func playURLRealCapture_decodesSuccessfully() throws {
        // 真实抓包响应（108KB,含 18 个 DASH 视频轨 + clip_info_list）:
        // 保证完整 DASH 响应可解码,防止新增字段破坏契约
        let response = try JSONDecoder().decode(PlayURLResponse.self, from: fixtureData("playURL_real_capture"))

        #expect(response.code == 0)
        let result = try #require(response.activeResult)
        #expect(result.isPreviewOnly == false)
        #expect(result.dash?.video.isEmpty == false)
        #expect(result.clipInfoList.count == 2)
        #expect(result.clipInfoList.contains { $0.clipType == "CLIP_TYPE_OP" })
        #expect(result.clipInfoList.contains { $0.clipType == "CLIP_TYPE_ED" })
    }

    // MARK: - playURL clip_info_list（跳过片头/片尾配置，UI 尚未消费）

    @Test func playURLFixture_decodesClipInfoList() throws {
        let response = try JSONDecoder().decode(PlayURLResponse.self, from: fixtureData("playURL"))
        let result = try #require(response.activeResult)

        // 抓包实测结构：clipType 为字符串枚举，start/end 为秒，toastText 为提示文案
        let opClips = result.clipInfoList.filter { $0.clipType == "CLIP_TYPE_OP" }
        let edClips = result.clipInfoList.filter { $0.clipType == "CLIP_TYPE_ED" }
        if !opClips.isEmpty {
            #expect(opClips.allSatisfy { ($0.start ?? -1) <= ($0.end ?? 0) })
            #expect(opClips.allSatisfy { $0.toastText?.isEmpty == false })
        }
        if !edClips.isEmpty {
            #expect(edClips.allSatisfy { ($0.start ?? -1) <= ($0.end ?? 0) })
            #expect(edClips.allSatisfy { $0.start != nil })
        }
        #expect(result.clipInfoList.allSatisfy { $0.clipType != nil })
    }

    @Test func playURLFixture_withoutClipInfo_decodesEmptyList() throws {
        let response = try JSONDecoder().decode(
            PlayURLResponse.self,
            from: Data(#"{"code":0,"message":"success","result":{"durl":[]}}"#.utf8)
        )
        let result = try #require(response.activeResult)
        #expect(result.clipInfoList.isEmpty)
    }

    @Test func playURLFixture_withClipInfoList_decodesRealPacket() throws {
        // 抓包实测的真实 playurl clip_info_list 结构
        let response = try JSONDecoder().decode(
            PlayURLResponse.self,
            from: Data(
                #"""
                {"code":0,"message":"success","result":{"durl":[],"clip_info_list":[
                    {"materialNo":0,"start":0,"end":26,"toastText":"即将跳过片头","clipType":"CLIP_TYPE_OP"},
                    {"materialNo":0,"start":1864,"end":1936,"toastText":"即将跳过片尾","clipType":"CLIP_TYPE_ED"}
                ]}}
                """#.utf8)
        )
        let result = try #require(response.activeResult)
        #expect(result.clipInfoList.count == 2)
        #expect(result.clipInfoList[0].clipType == "CLIP_TYPE_OP")
        #expect(result.clipInfoList[0].start == 0)
        #expect(result.clipInfoList[0].end == 26)
        #expect(result.clipInfoList[0].toastText == "即将跳过片头")
        #expect(result.clipInfoList[1].clipType == "CLIP_TYPE_ED")
        #expect(result.clipInfoList[1].start == 1_864)
        #expect(result.clipInfoList[1].end == 1_936)
    }
}

/// Bundle 定位锚点（Swift Testing 无 NSObject 锚，用此类取测试 Bundle）
private final class BundleAnchor {}
