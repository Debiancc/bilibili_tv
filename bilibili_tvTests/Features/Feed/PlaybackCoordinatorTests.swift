//
//  PlaybackCoordinatorTests.swift
//  bilibili_tvTests
//
//  Phase 1: PlaybackCoordinator 行为契约测试（TDD RED 先行）。
//  播放意图经环境注入直达根视图，本测试固化"触发后 activePlayback 状态正确"的契约，
//  替代原先"点击 → 闭包链 → @State 赋值"的黑盒路径。
//

import Foundation
import Testing

@testable import bilibili_tv

@MainActor
struct PlaybackCoordinatorTests {
    private func makeItem(
        title: String? = "测试影片",
        episodeId: Int? = 100,
        seasonId: Int? = 200
    ) -> FeedItem {
        FeedItem(
            title: title,
            subtitle: nil,
            cover: "https://example.com/cover.png",
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

    private func makeEntry(progress: Int = 925) -> LocalWatchHistoryEntry {
        LocalWatchHistoryEntry(
            seasonId: 200,
            epId: 100,
            cid: 123_456,
            title: "测试剧集",
            episodeTitle: "第1话",
            coverURLString: "https://example.com/cover.png",
            progress: progress,
            duration: 1_481,
            viewAt: 1_588_831_600
        )
    }

    @Test("给定 Hero 横幅播放请求 → play 后 activePlayback 携带上下文")
    func playBannerContextSetsActivePlayback() {
        // given
        let coordinator = PlaybackCoordinator()
        let context = PlaybackContext.banner(makeItem())

        // when
        coordinator.play(context)

        // then
        #expect(coordinator.activePlayback == context)
    }

    @Test("给定续播请求 → play 后 activePlayback 保留续播进度")
    func playResumeContextPreservesResumeTime() {
        // given
        let coordinator = PlaybackCoordinator()
        let context = PlaybackContext.resume(makeEntry(progress: 925))

        // when
        coordinator.play(context)

        // then
        #expect(coordinator.activePlayback?.epId == 100)
        #expect(coordinator.activePlayback?.seasonId == 200)
        #expect(coordinator.activePlayback?.resumeTime == 925.0)
    }

    @Test("给定连续两次播放请求 → 后一次覆盖前一次(单封面语义)")
    func secondPlayOverridesFirst() {
        // given
        let coordinator = PlaybackCoordinator()
        let first = PlaybackContext.banner(makeItem(title: "甲片"))
        let second = PlaybackContext.banner(makeItem(title: "乙片"))

        // when
        coordinator.play(first)
        coordinator.play(second)

        // then
        #expect(coordinator.activePlayback?.title == "乙片")
    }

    @Test("给定从未触发播放 → activePlayback 为 nil(无 cover 展示)")
    func initialActivePlaybackIsNil() {
        // given
        let coordinator = PlaybackCoordinator()

        // then
        #expect(coordinator.activePlayback == nil)
    }

    // MARK: - 阶段二:详情导航契约(openDetail)

    @Test("给定详情请求 → openDetail 后 activeDetail 携带对应 item 且归属发起 tab")
    func openDetailSetsActiveDetail() {
        // given
        let coordinator = PlaybackCoordinator()
        let item = makeItem(title: "甲片", episodeId: 100, seasonId: 200)

        // when
        coordinator.openDetail(item, owner: .channel(.movie))

        // then
        #expect(coordinator.activeDetail == item)
        #expect(coordinator.activeDetailOwner == .channel(.movie))
    }

    @Test("给定连续两次详情请求 → 后一次覆盖前一次(单详情语义)")
    func secondOpenDetailOverridesFirst() {
        // given
        let coordinator = PlaybackCoordinator()
        let first = makeItem(title: "甲片", episodeId: 100, seasonId: 200)
        let second = makeItem(title: "乙片", episodeId: 300, seasonId: 400)

        // when
        coordinator.openDetail(first, owner: .channel(.movie))
        coordinator.openDetail(second, owner: .channel(.anime))

        // then
        #expect(coordinator.activeDetail?.seasonId == 400)
        #expect(coordinator.activeDetailOwner == .channel(.anime))
    }

    @Test("给定从未触发详情 → activeDetail 为 nil(无详情页展示)")
    func initialActiveDetailIsNil() {
        // given
        let coordinator = PlaybackCoordinator()

        // then
        #expect(coordinator.activeDetail == nil)
        #expect(coordinator.activeDetailOwner == nil)
    }

    /// 回归：详情必须归属发起 tab。若 owner 不随 item 记录,切换 tab 后新 tab 的
    /// navigationDestination(item:) 绑定会拿到同一个 item,把旧详情 push 到新栈上。
    @Test("给定 A tab 详情在途 → clearDetail 清空 item 与归属(切换 tab 不泄漏)")
    func clearDetailResetsItemAndOwner() {
        // given
        let coordinator = PlaybackCoordinator()
        coordinator.openDetail(makeItem(), owner: .channel(.movie))

        // when
        coordinator.clearDetail()

        // then
        #expect(coordinator.activeDetail == nil)
        #expect(coordinator.activeDetailOwner == nil)
    }

    @Test("给定播放与详情相继触发 → 两通道互不覆盖(cover 与详情页可独立呈现)")
    func playAndOpenDetailAreIndependentChannels() {
        // given
        let coordinator = PlaybackCoordinator()
        let context = PlaybackContext.banner(makeItem(title: "甲片"))
        let item = makeItem(title: "乙片", episodeId: 300, seasonId: 400)

        // when:先播后详情
        coordinator.play(context)
        coordinator.openDetail(item, owner: .search)

        // then:详情不破坏播放通道
        #expect(coordinator.activePlayback == context)
        #expect(coordinator.activeDetail == item)

        // when:再播一次,详情通道不受影响
        let second = PlaybackContext.banner(makeItem(title: "丙片"))
        coordinator.play(second)

        // then
        #expect(coordinator.activePlayback == second)
        #expect(coordinator.activeDetail == item)
        #expect(coordinator.activeDetailOwner == .search)
    }
}
