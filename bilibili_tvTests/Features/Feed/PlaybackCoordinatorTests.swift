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

    // MARK: - 阶段三:辅助覆盖(账号页/调试控制台)呈现状态

    @Test("给定任一辅助覆盖呈现 → isAuxiliaryOverlayPresented 为 true")
    func auxiliaryOverlayORSemantics() {
        // given
        let coordinator = PlaybackCoordinator()

        // when:账号页覆盖呈现
        coordinator.isAccountOverlayPresented = true
        #expect(coordinator.isAuxiliaryOverlayPresented)

        // when:调试控制台覆盖也呈现(双 cover 同时打开)
        coordinator.isPulseConsoleOverlayPresented = true
        #expect(coordinator.isAuxiliaryOverlayPresented)

        // when:只关闭账号页(后写 false 不得因共享标志而误恢复播放)
        coordinator.isAccountOverlayPresented = false
        #expect(coordinator.isAuxiliaryOverlayPresented)

        // when:两个覆盖全部关闭
        coordinator.isPulseConsoleOverlayPresented = false
        #expect(!coordinator.isAuxiliaryOverlayPresented)
    }

    // MARK: - 阶段四:feed 遮挡聚合(isFeedCovered(for:))

    /// 回归 issue #52:详情页 push 必须纳入轮播视频门控。
    /// 此前详情路径被豁免、依赖不可靠的 onDisappear,导致详情页下预告片持续出声。
    @Test("给定全新协调器 → 任意 Tab 的 isFeedCovered 均为 false(feed 未被遮挡)")
    func initialIsFeedCoveredIsFalse() {
        // given
        let coordinator = PlaybackCoordinator()

        // then
        #expect(!coordinator.isFeedCovered(for: .channel(.movie)))
        #expect(!coordinator.isFeedCovered(for: .channel(.anime)))
        #expect(!coordinator.isFeedCovered(for: .search))
    }

    @Test("给定四个遮挡来源各自单独开启 → isFeedCovered(for:) 均为 true(OR 聚合)")
    func eachSourceAloneCoversFeed() {
        /// 单来源断言:开启时 expectedCoveredTabs 内的 Tab 必须全部遮挡,关闭后全部恢复
        /// (逐源验证,不用元组数组避免 large_tuple)。
        /// 播放 cover/辅助覆盖为全局 → 传全部 Tab;详情按 owner 判定 → 只传 owner Tab,
        /// 非 owner Tab 的 feed 不得被误冻(见 staleDetailFromNonOwnerTabDoesNotCoverOtherTab)。
        func assertCovers(
            _ source: String,
            expectedCoveredTabs: [HomeTab] = [HomeTab.channel(.movie), .channel(.anime), .search],
            open: (PlaybackCoordinator) -> Void,
            close: (PlaybackCoordinator) -> Void
        ) {
            // when:单个来源开启
            let coordinator = PlaybackCoordinator()
            open(coordinator)

            // then
            for tab in expectedCoveredTabs {
                #expect(coordinator.isFeedCovered(for: tab), "\(source) 开启时 \(tab) 必须视为遮挡")
            }

            // when:关闭后恢复
            close(coordinator)
            for tab in expectedCoveredTabs {
                #expect(!coordinator.isFeedCovered(for: tab), "\(source) 关闭后 \(tab) 不得残留遮挡")
            }
        }

        assertCovers(
            "播放 cover",
            open: {
                $0.play(.banner(self.makeItem()))
            }, close: { $0.activePlayback = nil })
        assertCovers(
            "详情页",
            expectedCoveredTabs: [.channel(.movie)],
            open: {
                $0.openDetail(self.makeItem(), owner: .channel(.movie))
            }, close: { $0.clearDetail() })
        assertCovers(
            "账号页",
            open: {
                $0.isAccountOverlayPresented = true
            }, close: { $0.isAccountOverlayPresented = false })
        assertCovers(
            "调试控制台",
            open: {
                $0.isPulseConsoleOverlayPresented = true
            }, close: { $0.isPulseConsoleOverlayPresented = false })
    }

    @Test("给定播放与详情同时在途 → 只关详情不得恢复播放(叠加语义)")
    func closingOneOverlayMustNotResumeWhileAnotherOpen() {
        // given:播放 cover 与详情页叠加(详情页内再点播放的合法路径)
        let coordinator = PlaybackCoordinator()
        coordinator.play(.banner(makeItem()))
        coordinator.openDetail(makeItem(), owner: .channel(.movie))
        #expect(coordinator.isFeedCovered(for: .channel(.movie)))

        // when:只关闭详情(pop 回 feed,播放 cover 仍在)
        coordinator.clearDetail()

        // then:不得误恢复
        #expect(coordinator.isFeedCovered(for: .channel(.movie)))

        // when:播放 cover 也关闭
        coordinator.activePlayback = nil

        // then
        #expect(!coordinator.isFeedCovered(for: .channel(.movie)))
    }

    /// 回归 PR #53 review:切 Tab 不会清除旧 Tab 的 activeDetail(各 Tab 的
    /// NavigationStack 各自保留详情页),聚合判定若不按 owner 域内化,
    /// A Tab 的详情会把 B Tab 的轮播误冻(视频不播、轮播不走)。
    @Test("给定 A Tab 详情在途且已切到 B Tab → 仅 A Tab 视为遮挡,B Tab 轮播不受影响")
    func staleDetailFromNonOwnerTabDoesNotCoverOtherTab() {
        // given:电影 Tab 打开详情(未关闭),随后用户切到番剧 Tab
        let coordinator = PlaybackCoordinator()
        coordinator.openDetail(makeItem(), owner: .channel(.movie))

        // then:电影 Tab 被遮挡,番剧 Tab 不受牵连
        #expect(coordinator.isFeedCovered(for: .channel(.movie)))
        #expect(!coordinator.isFeedCovered(for: .channel(.anime)))

        // when:用户切回电影 Tab(详情仍在栈上)
        // then:遮挡恢复(轮播视频保持暂停,等待返回后的断点续播)
        #expect(coordinator.isFeedCovered(for: .channel(.movie)))

        // when:详情 pop(clearDetail)
        coordinator.clearDetail()
        // then:两个 Tab 均恢复
        #expect(!coordinator.isFeedCovered(for: .channel(.movie)))
        #expect(!coordinator.isFeedCovered(for: .channel(.anime)))
    }
}
