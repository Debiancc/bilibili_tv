//
//  MovieDetailFocusNavigationTests.swift
//  bilibili_tvUITests
//
//  阶段二：MovieDetailViewModel 状态枚举化（MovieDetailState）重构后的焦点回归测试。
//  用 -uitestMockDetail 启动参数注入 MovieDetailViewModel.mock（.loaded 态，含 3 集选集），
//  验证状态机消费端改造后，遥控器方向键仍能在详情页 Play 按钮与选集卡片之间正常移动焦点，
//  @FocusState/FocusGuide 绑定未被破坏。
//  注意：UI 测试无法使用 Swift Testing，必须用 XCTest。
//

import XCTest

final class MovieDetailFocusNavigationTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// 验证 .loaded 态下焦点能从 Play 按钮下移到选集卡片，并能在卡片间左右移动。
    @MainActor
    func testFocusMovesFromPlayButtonToEpisodeCardsAndAcrossCards() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uitestMockDetail"]
        app.launch()

        // mock 详情页 .loaded 态：播放按钮默认聚焦，选集卡片 a11y label 为「第N集 长标题」
        let firstEpisodeTitle = "第1集 梦回青春"
        let firstEpisode = app.buttons.matching(NSPredicate(format: "label == %@", firstEpisodeTitle)).firstMatch
        XCTAssertTrue(firstEpisode.waitForExistence(timeout: 15), "app 启动后应渲染出 mock 详情页选集卡片")

        // Play 按钮默认聚焦；选集卡片在下方，按 ↓ 直到焦点落到第一集
        var reachedFirstEpisode = false
        for _ in 0..<8 where !reachedFirstEpisode {
            XCUIRemote.shared.press(.down)
            reachedFirstEpisode = waitForAnyCardFocus(title: firstEpisodeTitle, in: app)
        }
        XCTAssertTrue(reachedFirstEpisode, "按 ↓ 后焦点应落在第一集卡片")

        // 向右移动到第二集
        let secondEpisodeTitle = "第2集 婚礼风波"
        XCUIRemote.shared.press(.right)
        XCTAssertTrue(
            waitForAnyCardFocus(title: secondEpisodeTitle, in: app),
            "按 → 后焦点应落在第二集卡片"
        )

        // 向左回到第一集
        XCUIRemote.shared.press(.left)
        XCTAssertTrue(
            waitForAnyCardFocus(title: firstEpisodeTitle, in: app),
            "按 ← 后焦点应回到第一集卡片"
        )
    }

    /// 阶段一：内联 fullScreenCover 收敛为根视图协调器 cover 后的播放回归——
    /// select 选集卡片应弹出播放器封面（加载中/失败文案任一出现），
    /// menu 关闭后焦点回到详情页（Play 按钮或选集卡片），详情页未被重建。
    @MainActor
    func testSelectEpisodePresentsCoverAndFocusReturnsAfterDismiss() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uitestMockDetail"]
        app.launch()

        // mock 详情页 .loaded 态：播放按钮默认聚焦，选集卡片 a11y label 为「第N集 长标题」
        let firstEpisodeTitle = "第1集 梦回青春"
        let firstEpisode = app.buttons.matching(NSPredicate(format: "label == %@", firstEpisodeTitle)).firstMatch
        XCTAssertTrue(firstEpisode.waitForExistence(timeout: 15), "app 启动后应渲染出 mock 详情页选集卡片")

        // 下移到第一集卡片
        var reachedFirstEpisode = false
        for _ in 0..<8 where !reachedFirstEpisode {
            XCUIRemote.shared.press(.down)
            reachedFirstEpisode = waitForAnyCardFocus(title: firstEpisodeTitle, in: app)
        }
        XCTAssertTrue(reachedFirstEpisode, "按 ↓ 后焦点应落在第一集卡片")

        // select 选集 → 播放器 cover 弹出（加载中或失败文案任一出现在的即可证明已呈现）
        XCUIRemote.shared.press(.select)
        let loadingText = app.staticTexts["正在自适应加载高清视频流..."]
        let errorText = app.staticTexts["视频加载失败"]
        let coverDeadline = Date().addingTimeInterval(10)
        var coverPresented = false
        while Date() < coverDeadline && !coverPresented {
            coverPresented = loadingText.exists || errorText.exists
            if !coverPresented {
                RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            }
        }
        XCTAssertTrue(coverPresented, "select 选集后应弹出播放器封面（加载中或失败态）")

        // 关闭 cover:AVKit 控制层可见时 menu 先收起控制层,再按一次才关闭 cover。
        // 注意 fullScreenCover 下层详情页始终在 a11y 树中,必须用播放器特有元素
        // (加载/失败文案、跳过片头/Info/From Beginning)判断 cover 状态。
        // 视频可能加载失败(错误视图无控制层元素),故 cover 存在 = 上述任一元素在树。
        let playerMarker = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS '跳过' OR label CONTAINS 'From Beginning' OR label CONTAINS 'Info'")
        ).firstMatch
        var menuPresses = 0
        let menuDeadline = Date().addingTimeInterval(15)
        while Date() < menuDeadline {
            let coverVisible = loadingText.exists || errorText.exists || playerMarker.exists
            if !coverVisible {
                // cover 弹出初期为 loading 态,播放器元素尚未出现,等待其出现
                RunLoop.current.run(until: Date().addingTimeInterval(0.3))
                continue
            }
            XCUIRemote.shared.press(.menu)
            menuPresses += 1
            RunLoop.current.run(until: Date().addingTimeInterval(0.7))
            if !(loadingText.exists || errorText.exists || playerMarker.exists) { break }
        }
        XCTAssertFalse(
            loadingText.exists || errorText.exists || playerMarker.exists,
            "按 menu 应能关闭播放器 cover(共按 \(menuPresses) 次)")

        // cover 关闭后详情页恢复,焦点回到 Play 按钮或选集卡片(不丢)
        XCTAssertTrue(firstEpisode.waitForExistence(timeout: 10), "关闭 cover 后应回到详情页")
        XCTAssertTrue(waitForFocusReturn(in: app), "关闭 cover 后焦点应回到详情页（Play 按钮或选集卡片）")
    }

    /// 轮询等待：cover 关闭后焦点恢复（Play 按钮或任一带"集"标签的选集卡片获得焦点）
    @MainActor
    private func waitForFocusReturn(in app: XCUIApplication, timeout: TimeInterval = 5) -> Bool {
        // tvOS 按钮未聚焦时 a11y label 为符号名（play.fill），聚焦展开后才变为文案
        let playButton = app.buttons.matching(
            NSPredicate(format: "label == '立即播放' OR identifier == 'play.fill'")
        ).firstMatch
        let cards = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "集"))
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if playButton.exists, playButton.hasFocus { return true }
            if cards.allElementsBoundByIndex.contains(where: { $0.hasFocus }) { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return false
    }

    /// 轮询等待：标题匹配的任意卡片实例获得焦点（tvOS 焦点更新有少量延迟）
    @MainActor
    private func waitForAnyCardFocus(title: String, in app: XCUIApplication, timeout: TimeInterval = 5) -> Bool {
        let cards = app.buttons.matching(NSPredicate(format: "label == %@", title))
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if cards.allElementsBoundByIndex.contains(where: { $0.hasFocus }) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return cards.allElementsBoundByIndex.contains(where: { $0.hasFocus })
    }
}
