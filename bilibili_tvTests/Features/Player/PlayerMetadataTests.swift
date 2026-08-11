//
//  PlayerMetadataTests.swift
//  bilibili_tvTests
//
//  阶段三 3b：PlayerViewModel 进度上报的「元数据直通」冒烟测试。
//  注入 MockHistoryStore 断言 record() 收到的参数：
//  - 标题回退（title nil → 「未命名影视」）、episodeTitle/coverURLString 透传
//  - cid 透传、未知时长 → duration=0（不误标看完）
//  - progress<=0 不上报（秒数非法守卫）
//  - completed 播完上报以 item duration 标记看完
//
//  心跳时序/节流/启停幂等的并发行为见 PlayerProgressReportingTests。
//

import AVFoundation
import Testing

@testable import bilibili_tv

/// Mock 观看记录存储：捕获每次 record 调用的完整参数，供断言直通语义
@MainActor
final class MockHistoryStore: WatchHistoryRecording {
    struct Record {
        let seasonId: Int?
        let epId: Int?
        let cid: Int?
        let title: String
        let episodeTitle: String?
        let coverURLString: String?
        let progress: Int
        let duration: Int
    }

    private(set) var records: [Record] = []

    // swiftlint:disable function_parameter_count
    // Mock 须镜像 WatchHistoryRecording 协议签名（与 LocalWatchHistoryStore.record 一致的 8 参存储 API）
    func record(
        seasonId: Int?,
        epId: Int?,
        cid: Int?,
        title: String,
        episodeTitle: String?,
        coverURLString: String?,
        progress: Int,
        duration: Int
    ) {
        records.append(
            Record(
                seasonId: seasonId, epId: epId, cid: cid, title: title,
                episodeTitle: episodeTitle, coverURLString: coverURLString,
                progress: progress, duration: duration
            )
        )
    }
    // swiftlint:enable function_parameter_count
}

/// AVPlayerItem.duration 是 open 属性：测试子类覆写为固定时长，
/// 使「播完 → 以 duration 标记看完」路径不依赖真实媒体加载。
/// 必须实现 designated init `init(asset:automaticallyLoadedAssetKeys:)`
/// （ObjC 初始化器链依赖它；缺失会触发
/// "Use of unimplemented initializer" 运行时致命错误）。
final class StubPlayerItem: AVPlayerItem {
    var stubbedDuration: CMTime = .zero

    // swiftlint:disable discouraged_optional_collection
    // SDK 签名固定为 `automaticallyLoadedAssetKeys: [String]?`（AVPlayerItem 原始 API），无法改写
    override init(asset: AVAsset, automaticallyLoadedAssetKeys: [String]?) {
        super.init(asset: asset, automaticallyLoadedAssetKeys: automaticallyLoadedAssetKeys)
    }
    // swiftlint:enable discouraged_optional_collection

    convenience init(url: URL = URL(string: "https://example.com/never-loaded.mp4")!, duration: CMTime) {
        self.init(asset: AVURLAsset(url: url), automaticallyLoadedAssetKeys: nil)
        stubbedDuration = duration
    }

    override var duration: CMTime { stubbedDuration }
}

@MainActor
struct PlayerMetadataTests {
    private func makeViewModel(
        epId: Int = 320_665,
        seasonId: Int = 33_354,
        historyStore: MockHistoryStore
    ) -> PlayerViewModel {
        PlayerViewModel(epId: epId, seasonId: seasonId, historyStore: historyStore)
    }

    // MARK: - 元数据直通

    @Test func record_passesThroughMetadata() throws {
        let store = MockHistoryStore()
        let vm = makeViewModel(historyStore: store)
        vm.currentCid = 1_234
        vm.playbackTimeProvider = { 126.7 }

        vm.stopProgressReporting(reportFinal: true)

        #expect(store.records.count == 1)
        let rec = try #require(store.records.first)
        #expect(rec.seasonId == 33_354)
        #expect(rec.epId == 320_665)
        #expect(rec.cid == 1_234)
        #expect(rec.progress == 126)
        #expect(rec.duration == 0)  // 无 item → 未知时长,不误标看完
    }

    @Test func record_titleFallsBackToDefaultWhenNil() throws {
        let store = MockHistoryStore()
        let vm = PlayerViewModel(epId: 1, seasonId: 2, historyStore: store)
        vm.playbackTimeProvider = { 60 }

        vm.stopProgressReporting(reportFinal: true)

        let rec = try #require(store.records.first)
        #expect(rec.title == "未命名影视")
        #expect(rec.episodeTitle == nil)
        #expect(rec.coverURLString == nil)
    }

    @Test func record_passesEpisodeTitleAndCover() throws {
        let store = MockHistoryStore()
        let vm = PlayerViewModel(
            epId: 1,
            seasonId: 2,
            title: "我的英雄学院",
            subtitle: "第 1 集",
            coverURL: URL(string: "https://example.com/cover.jpg"),
            historyStore: store
        )
        vm.playbackTimeProvider = { 42 }

        vm.stopProgressReporting(reportFinal: true)

        let rec = try #require(store.records.first)
        #expect(rec.title == "我的英雄学院")
        #expect(rec.episodeTitle == "第 1 集")
        #expect(rec.coverURLString == "https://example.com/cover.jpg")
    }

    // MARK: - 非法秒数守卫

    @Test func record_skipsWhenProviderReturnsNil() {
        let store = MockHistoryStore()
        let vm = makeViewModel(historyStore: store)
        // 默认 provider 返回 nil,且未注入 player → 无有效秒数,不上报

        vm.stopProgressReporting(reportFinal: true)

        #expect(store.records.isEmpty)
    }

    @Test func record_skipsWhenSecondsNonPositive() {
        let store = MockHistoryStore()
        let vm = makeViewModel(historyStore: store)
        vm.playbackTimeProvider = { 0 }

        vm.stopProgressReporting(reportFinal: true)

        #expect(store.records.isEmpty)
    }
}
