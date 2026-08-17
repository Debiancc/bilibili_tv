//
//  FeedFocusNavigationTests.swift
//  bilibili_tvUITests
//
//  阶段一：FeedViewModel 状态枚举化（FeedState）重构后的焦点回归测试。
//  用 -uitestMockFeed 启动参数注入 FeedViewModel.mock（.loaded 态，含 hero + 卡片），
//  验证 switch 消费端改造后，遥控器方向键仍能在 feed 卡片之间正常移动焦点，
//  @FocusState/FocusGuide 绑定未被破坏。
//  注意：UI 测试无法使用 Swift Testing，必须用 XCTest。
//

import XCTest

final class FeedFocusNavigationTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// 验证 .loaded 态下焦点能从 hero 下移到首张卡片，并能在卡片间左右移动。
    @MainActor
    func testFocusMovesFromHeroToFirstCardAndAcrossCards() throws {
        let app = XCUIApplication()
        // -uitestFocusHeroPlay: 禁用侧栏入口聚焦，消除冷启动初始焦点竞态
        // （详见 ContentView.isUITestHeroFocusMode），hero Play 为确定性初始焦点
        app.launchArguments = ["-uitestMockFeed", "-uitestFocusHeroPlay", "-uitestDisableRotation"]
        app.launch()

        // mock 各 shelf（rank/exclusive/comingSoon）复用同一批标题，a11y 树中存在多个
        // 同名 button。不能用 app.buttons["..."] 精确匹配（会抛 multiple matches），
        // 需用 matching + 轮询任一实例 hasFocus，并按下移直到焦点落到卡片行。
        let firstCardTitle = "秦牧化身月亮守，获得史诗级载具！"
        let firstCard = app.buttons.matching(NSPredicate(format: "label == %@", firstCardTitle)).firstMatch
        XCTAssertTrue(firstCard.waitForExistence(timeout: 15), "app 启动后应渲染出 mock feed 卡片")

        // hero 默认聚焦 Play 按钮；hero 高 1080pt，焦点引擎需滚动才能落到卡片行，
        // 多按几次 ↓ 直到任一同名卡片获得焦点
        var reachedFirstCard = false
        for _ in 0..<5 where !reachedFirstCard {
            XCUIRemote.shared.press(.down)
            reachedFirstCard = waitForAnyCardFocus(title: firstCardTitle, in: app)
        }
        XCTAssertTrue(reachedFirstCard, "按 ↓ 后焦点应落在首张卡片")

        // 向右移动到第二张卡片
        let secondCardTitle = "近战五行神兽？这是一场单方面的碾压！"
        XCUIRemote.shared.press(.right)
        XCTAssertTrue(
            waitForAnyCardFocus(title: secondCardTitle, in: app),
            "按 → 后焦点应落在第二张卡片"
        )

        // 向左回到第一张卡片
        XCUIRemote.shared.press(.left)
        XCTAssertTrue(
            waitForAnyCardFocus(title: firstCardTitle, in: app),
            "按 ← 后焦点应回到第一张卡片"
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
