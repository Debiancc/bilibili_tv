//
//  PlayURLModelCodecSelectionTests.swift
//  bilibili_tvTests
//
//  bestVideoTrack 编码选择策略测试：
//  - 抹掉 AV1 (codecid=13)：当前 Apple TV 全系无 AV1 硬解，4K 软解吃力
//  - 同清晰度优先 HEVC (codecid=12)，其次 H.264 (codecid=7)
//  - codec 过滤后为空时回退全部轨道，保证不因偏好逻辑丢流
//

import Foundation
import Testing

@testable import bilibili_tv

struct PlayURLModelCodecSelectionTests {
    private func fixtureData(_ name: String) throws -> Data {
        let bundle = Bundle(for: CodecTestBundleAnchor.self)
        let url = try #require(bundle.url(forResource: name, withExtension: "json"))
        return try Data(contentsOf: url)
    }

    private func decodeResult(json: String) throws -> PlayURLResult {
        let response = try JSONDecoder().decode(PlayURLResponse.self, from: Data(json.utf8))
        return try #require(response.activeResult)
    }

    /// 真实抓包 fixture（18 轨 = 6 清晰度 × 3 编码）：应选中 4K HEVC，而非 H.264 或 AV1
    @Test func realCapture_prefersHEVC4K() throws {
        let response = try JSONDecoder().decode(PlayURLResponse.self, from: fixtureData("playURL_real_capture"))
        let result = try #require(response.activeResult)

        let best = try #require(result.bestVideoTrack(maxQn: 120))
        #expect(best.qualityId == 120)
        #expect(best.codecId == 12)  // HEVC
        #expect(best.codecs?.hasPrefix("hvc1") == true || best.codecs?.hasPrefix("hev1") == true)
    }

    /// 同清晰度 3 编码并存：HEVC 胜出；AV1 与更高码率的 H.264 均被跳过
    @Test func sameQuality_prefersHEVCOverH264AndAV1() throws {
        let result = try decodeResult(
            json: makeTracksJSON(
                track(quality: 120, codecId: 13, bandwidth: 4_950_000),  // AV1（应被排除）
                track(quality: 120, codecId: 12, bandwidth: 6_260_000),  // HEVC（应选中）
                track(quality: 120, codecId: 7, bandwidth: 12_600_000)  // H.264（码率最高但编码次选）
            ))

        let best = try #require(result.bestVideoTrack(maxQn: 120))
        #expect(best.qualityId == 120)
        #expect(best.codecId == 12)
    }

    /// 4K 仅剩 AV1；1080P 有 HEVC/H.264：宁可降清晰度也不用 AV1
    @Test func av1Excluded_evenIfItMeansLowerQuality() throws {
        let result = try decodeResult(
            json: makeTracksJSON(
                track(quality: 120, codecId: 13, bandwidth: 4_950_000),
                track(quality: 80, codecId: 12, bandwidth: 2_500_000),
                track(quality: 80, codecId: 7, bandwidth: 4_000_000)
            ))

        let best = try #require(result.bestVideoTrack(maxQn: 120))
        #expect(best.qualityId == 80)
        #expect(best.codecId == 12)
    }

    /// 极端情况仅剩 AV1：回退选择，不返回 nil（保证播放不中断）
    @Test func av1Only_fallsBackToAV1Track() throws {
        let result = try decodeResult(
            json: makeTracksJSON(
                track(quality: 120, codecId: 13, bandwidth: 4_950_000)
            ))

        let best = try #require(result.bestVideoTrack(maxQn: 120))
        #expect(best.codecId == 13)
    }

    /// 同编码同清晰度：码率高的胜出（保持原有带宽次排序）
    @Test func hevcTracks_tieBrokenByBandwidth() throws {
        let result = try decodeResult(
            json: makeTracksJSON(
                track(quality: 80, codecId: 12, bandwidth: 2_500_000),
                track(quality: 80, codecId: 12, bandwidth: 3_200_000)
            ))

        let best = try #require(result.bestVideoTrack(maxQn: 120))
        #expect(best.bandwidth == 3_200_000)
    }

    // MARK: - Fixture 构造

    private func track(quality: Int, codecId: Int, bandwidth: Int) -> String {
        """
        {"id":\(quality),"codecid":\(codecId),"bandwidth":\(bandwidth),"baseUrl":"https://example.com/v.m4s","backupUrl":[]}
        """
    }

    private func makeTracksJSON(_ tracks: String...) -> String {
        let joined = tracks.joined(separator: ",")
        return #"{"code":0,"message":"success","result":{"durl":[],"dash":{"video":[\#(joined)]}}}"#
    }
}

/// Bundle 定位锚点（独立文件独立锚，避免跨文件依赖）
private final class CodecTestBundleAnchor {}
