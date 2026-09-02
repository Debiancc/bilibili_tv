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
        // hero Play 为确定性初始焦点（defaultFocus + onAppear 兜底 Task）
        app.launchArguments = ["-uitestMockFeed", "-uitestDisableRotation"]
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

    /// 回归(2026-09):焦点停在 shelf 卡片、hero 完全滚出视口时,↑ 必须能把焦点
    /// 带回 hero(立即播放)。该场景下 tvOS 焦点引擎原本不会跨"双层嵌套 + 离屏"
    /// 自动揭示 hero 按钮(揭示请求发往水平容器,无垂直滚动能力),↑ 会被消费;
    /// 修复:hero 区块注册 .focusSection(),引擎经外层垂直 ScrollView 原生揭示。
    /// 落点为 hero 环境记忆的按钮(从 Play 下探后返回仍落 Play)。
    /// 循环 3 轮深滚→↑,覆盖"第一次能回、第二三次回不去"的历史退化场景。
    @MainActor
    func testUpFromDeepScrolledCardsReturnsFocusToHeroAcrossCycles() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uitestMockFeed", "-uitestDisableRotation"]
        app.launch()

        let firstCardTitle = "秦牧化身月亮守，获得史诗级载具！"
        let heroPlay = app.buttons["立即播放"].firstMatch
        XCTAssertTrue(heroPlay.waitForExistence(timeout: 15), "app 启动后应渲染出 hero 立即播放按钮")

        // 焦点下探到卡片行(先确认 ↓ 链路可用;起始焦点在 Play,故返回落点预期为 Play)
        var reachedCard = false
        for _ in 0..<5 where !reachedCard {
            XCUIRemote.shared.press(.down)
            reachedCard = waitForAnyCardFocus(title: firstCardTitle, in: app)
        }
        XCTAssertTrue(reachedCard, "按 ↓ 后焦点应落在卡片行")

        // 3 轮深滚→↑ 循环:每轮按 ↓ 直到 hero 完全滚出视口(frame.maxY <= 0)即停
        // (实测 hero Play minY≈-1250,完全离屏;轮询命中即止,替代固定 6 次 ↓ +
        // 0.35s sleep + 0.5s settle),再连续 ↑,焦点必须每轮都能回到 hero 立即播放
        for cycle in 1...3 {
            let scrolledOut = UITestHelpers.pressUntil(
                key: .down, maxPresses: 8, pollPerPress: 0.45, graceAfterLastPress: 0.5
            ) {
                heroPlay.frame.maxY <= 0
            }
            XCTAssertTrue(scrolledOut, "第 \(cycle) 轮深滚后 hero 应完全滚出视口")

            let returned = UITestHelpers.pressUntilFocus(key: .up, button: heroPlay, maxPresses: 5)
            XCTAssertTrue(returned, "第 \(cycle) 轮:连续 ↑ 后焦点应回到 hero 立即播放按钮")
        }
    }

    /// 回归(2026-09):焦点停在下方 shelf 卡片、上方 shelf 整体滚出视口时,↑ 必须
    /// 能把焦点逐级带回顶部 shelf。该场景与 hero 回归(#45)同型——目标卡片所在
    /// shelf 的揭示请求原本止步于其内层水平容器(无垂直滚动能力),↑ 被消费;
    /// 修复:每个 shelf 块注册 .focusSection(),引擎经外层垂直 ScrollView 原生揭示。
    /// 循环 3 轮深滚→↑,覆盖"第一次能回、第二三次回不去"的历史退化场景。
    @MainActor
    func testUpFromDeepScrolledShelfReturnsFocusToTopShelfAcrossCycles() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uitestMockFeed", "-uitestDisableRotation"]
        app.launch()

        // mock 各 shelf 复用同一批标题(rank/exclusive/comingSoon 均有「秦牧…」卡),
        // 必须以树序首个实例(= 顶部热播榜 shelf 的卡片)作为顶部锚点:
        // 若 ↑ 只回到中部 shelf(死区),树序首卡不会获得焦点,断言不会虚过。
        let firstCardTitle = "秦牧化身月亮守，获得史诗级载具！"
        let topShelfCard = app.buttons.matching(NSPredicate(format: "label == %@", firstCardTitle)).firstMatch
        XCTAssertTrue(topShelfCard.waitForExistence(timeout: 15), "app 启动后应渲染出 mock feed 卡片")

        // 焦点下探到卡片行(起始焦点在 hero Play)
        var reachedCard = false
        for _ in 0..<5 where !reachedCard {
            XCUIRemote.shared.press(.down)
            reachedCard = waitForAnyCardFocus(title: firstCardTitle, in: app)
        }
        XCTAssertTrue(reachedCard, "按 ↓ 后焦点应落在卡片行")

        // 3 轮深滚→↑:每轮按 ↓ 直到顶部 shelf 卡片完全滚出视口(frame.maxY <= 0;
        // 6 次只够把 hero 滚出、顶部 shelf 卡片仍部分在屏,故轮询条件直接以
        // 「顶部 shelf 离屏」为准),再连续 ↑,焦点必须每轮都能回到顶部 shelf 卡片。
        for cycle in 1...3 {
            let scrolledOut = UITestHelpers.pressUntil(
                key: .down, maxPresses: 10, pollPerPress: 0.45, graceAfterLastPress: 0.5
            ) {
                topShelfCard.frame.maxY <= 0
            }
            XCTAssertTrue(scrolledOut, "第 \(cycle) 轮深滚后顶部 shelf 应完全滚出视口")

            let returned = UITestHelpers.pressUntilFocus(key: .up, button: topShelfCard, maxPresses: 8)
            XCTAssertTrue(returned, "第 \(cycle) 轮:连续 ↑ 后焦点应回到顶部 shelf 卡片")
        }
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
