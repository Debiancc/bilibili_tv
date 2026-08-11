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
