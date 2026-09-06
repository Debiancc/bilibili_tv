//
//  DetailFocusNavigationTests.swift
//  bilibili_tvUITests
//
//  阶段二：DetailViewModel 状态枚举化（DetailState）重构后的焦点回归测试。
//  用 -uitestMockDetail 启动参数注入 DetailViewModel.mock（.loaded 态，含 3 集选集），
//  验证状态机消费端改造后，遥控器方向键仍能在详情页 Play 按钮与选集卡片之间正常移动焦点，
//  @FocusState/FocusGuide 绑定未被破坏。
//  冷启动 ~4.5s/次且同启动参数的用例两两同组，各链式合并为一次启动
//  （段间复位焦点 / 复用前置状态），见 issue #51。
//  注意：UI 测试无法使用 Swift Testing，必须用 XCTest。
//

import XCTest

final class DetailFocusNavigationTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// 链式合并 -uitestMockDetail 组（原 2 个独立用例共用一次冷启动）：
    /// 1. testFocusMovesFromPlayButtonToEpisodeCardsAndAcrossCards——Play ↓ 选集卡，向右移动并验证远端卡片 ↑
    /// 2. testSelectEpisodePresentsCoverAndFocusReturnsAfterDismiss——select 选集弹播放器 cover，
    ///    menu 关闭后焦点回到详情页
    @MainActor
    func testChainedMockDetailFocusNavigation() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uitestMockDetail"]
        app.launch()

        let firstEpisodeID = 1
        let firstEpisode = app.buttons[UITestAccessibilityIdentifier.episode(firstEpisodeID)]
        XCTAssertTrue(firstEpisode.waitForExistence(timeout: 15), "app 启动后应渲染出 mock 详情页选集卡片")

        focusMovesFromPlayButtonToEpisodeCardsAndAcross(in: app, firstEpisodeID: firstEpisodeID)

        selectEpisodePresentsCoverAndFocusReturnsAfterDismiss(in: app, firstEpisodeID: firstEpisodeID)
    }

    // MARK: - 段:Play ⇄ 选集卡片(原 testFocusMovesFromPlayButtonToEpisodeCardsAndAcrossCards)

    /// 验证 .loaded 态下焦点能从 Play 按钮下移到选集卡片，并能移动到远端卡片后返回操作行。
    @MainActor
    private func focusMovesFromPlayButtonToEpisodeCardsAndAcross(in app: XCUIApplication, firstEpisodeID: Int) {
        // mock 详情页 .loaded 态：播放按钮默认聚焦，选集卡片 a11y label 为「第N集 长标题」
        // Play 按钮默认聚焦；选集卡片在下方，按 ↓ 直到焦点落到第一集
        var reachedFirstEpisode = false
        for _ in 0..<8 where !reachedFirstEpisode {
            XCUIRemote.shared.press(.down)
            reachedFirstEpisode = waitForEpisodeFocus(id: firstEpisodeID, in: app)
        }
        XCTAssertTrue(reachedFirstEpisode, "按 ↓ 后焦点应落在第一集卡片")

        // 向右移动到第二集
        XCUIRemote.shared.press(.right)
        XCTAssertTrue(
            waitForEpisodeFocus(id: 2, in: app),
            "按 → 后焦点应落在第二集卡片"
        )

        // 只验证一个远端卡片能按 ↑ 返回操作行，替代长简介场景中逐一遍历全部卡片。
        XCUIRemote.shared.press(.right)
        XCTAssertTrue(waitForEpisodeFocus(id: 3, in: app), "连续按 → 后焦点应落在第三集卡片")
        XCUIRemote.shared.press(.up)
        XCTAssertTrue(waitForActionRowFocus(in: app), "第三集按 ↑ 后焦点应回到操作行")
    }

    // MARK: - 段:播放 cover 呈现与关闭(原 testSelectEpisodePresentsCoverAndFocusReturnsAfterDismiss)

    /// 阶段一：内联 fullScreenCover 收敛为根视图协调器 cover 后的播放回归——
    /// select 选集卡片应弹出播放器封面（加载中/失败文案任一出现），
    /// menu 关闭后焦点回到详情页（Play 按钮或选集卡片），详情页未被重建。
    @MainActor
    private func selectEpisodePresentsCoverAndFocusReturnsAfterDismiss(in app: XCUIApplication, firstEpisodeID: Int) {
        let firstEpisode = app.buttons[UITestAccessibilityIdentifier.episode(firstEpisodeID)]

        // 下移到第一集卡片
        var reachedFirstEpisode = false
        for _ in 0..<8 where !reachedFirstEpisode {
            XCUIRemote.shared.press(.down)
            reachedFirstEpisode = waitForEpisodeFocus(id: firstEpisodeID, in: app)
        }
        XCTAssertTrue(reachedFirstEpisode, "按 ↓ 后焦点应落在第一集卡片")

        // select 选集 → 播放器 cover 弹出(以 PlaybackCoverView 的稳定 identifier 为准)
        XCUIRemote.shared.press(.select)
        let cover = app.descendants(matching: .any).matching(identifier: "PlaybackCover").firstMatch
        let coverDeadline = Date().addingTimeInterval(10)
        var coverPresented = false
        while Date() < coverDeadline && !coverPresented {
            coverPresented = cover.exists
            if !coverPresented {
                RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            }
        }
        XCTAssertTrue(coverPresented, "select 选集后应弹出播放器封面（PlaybackCover）")

        // 关闭 cover:AVKit 控制层可见时 menu 先收起控制层,再按一次才关闭 cover。
        // 注意 fullScreenCover 下层详情页始终在 a11y 树中,必须用播放器特有的
        // PlaybackCover identifier 判断 cover 状态(加载/失败文案均不足以判定)。
        var menuPresses = 0
        let menuDeadline = Date().addingTimeInterval(15)
        while Date() < menuDeadline {
            if !cover.exists {
                RunLoop.current.run(until: Date().addingTimeInterval(0.3))
                continue
            }
            XCUIRemote.shared.press(.menu)
            menuPresses += 1
            RunLoop.current.run(until: Date().addingTimeInterval(0.7))
            if !cover.exists { break }
        }
        XCTAssertFalse(cover.exists, "按 menu 应能关闭播放器 cover(共按 \(menuPresses) 次)")

        // cover 关闭后详情页恢复,焦点回到 Play 按钮或选集卡片(不丢)
        XCTAssertTrue(firstEpisode.waitForExistence(timeout: 10), "关闭 cover 后应回到详情页")
        XCTAssertTrue(waitForFocusReturn(in: app), "关闭 cover 后焦点应回到详情页（Play 按钮或选集卡片）")
    }

    // MARK: - Helpers

    /// 轮询等待:焦点落在操作行(立即播放或追剧按钮)
    @MainActor
    private func waitForActionRowFocus(in app: XCUIApplication, timeout: TimeInterval = 3) -> Bool {
        let playButton = app.buttons.matching(
            NSPredicate(format: "label == '立即播放' OR identifier == 'play.fill'")
        ).firstMatch
        let bookmark = app.buttons.matching(
            NSPredicate(format: "label == '追剧' OR label == '已追剧'")
        ).firstMatch
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if playButton.exists, playButton.hasFocus { return true }
            if bookmark.exists, bookmark.hasFocus { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return false
    }

    /// 轮询等待：cover 关闭后焦点恢复（Play 按钮或任一选集卡片获得焦点）
    @MainActor
    private func waitForFocusReturn(in app: XCUIApplication, timeout: TimeInterval = 5) -> Bool {
        // tvOS 按钮未聚焦时 a11y label 为符号名（play.fill），聚焦展开后才变为文案
        let playButton = app.buttons.matching(
            NSPredicate(format: "label == '立即播放' OR identifier == 'play.fill'")
        ).firstMatch
        let episodeButtons = (1...3).map {
            app.buttons[UITestAccessibilityIdentifier.episode($0)]
        }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if playButton.exists, playButton.hasFocus { return true }
            if episodeButtons.contains(where: { $0.exists && $0.hasFocus }) { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return false
    }

    /// 轮询等待：稳定 identifier 对应的选集卡片获得焦点（tvOS 焦点更新有少量延迟）
    @MainActor
    private func waitForEpisodeFocus(id episodeID: Int, in app: XCUIApplication, timeout: TimeInterval = 5) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if episodeIsFocused(id: episodeID, in: app) { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return episodeIsFocused(id: episodeID, in: app)
    }

    /// 即时判定:稳定 identifier 对应的选集卡片是否持焦(供 pressUntil 轮询复用)
    @MainActor
    private func episodeIsFocused(id episodeID: Int, in app: XCUIApplication) -> Bool {
        let episode = app.buttons[UITestAccessibilityIdentifier.episode(episodeID)]
        return episode.exists && episode.hasFocus
    }

}
