//
//  FeedDetailNavigationTests.swift
//  bilibili_tvUITests
//
//  阶段二：Feed `selectedMovie` 详情导航收敛（B）后的焦点回归测试。
//  改造前 selectedMovie 经 FeedContentScrollView → ShelvesSection → MovieShelfView 三层绑定
//  穿透；改造后卡片 Button 经环境 PlaybackCoordinator.openDetail 直达根视图
//  navigationDestination。本测试验证方向键到 shelf 卡片 → select 进入详情页 →
//  menu 返回后焦点仍落在 feed 卡片（导航链路未被环境触发改造破坏）。
//  注意：UI 测试无法使用 Swift Testing，必须用 XCTest。
//

import XCTest

final class FeedDetailNavigationTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// shelf 卡片 → select 进入详情页 → menu 返回 → 焦点不丢。
    @MainActor
    func testShelfCardSelectPresentsDetailAndFocusReturns() throws {
        let app = XCUIApplication()
        // -uitestFocusHeroPlay: 禁用侧栏入口聚焦,hero Play 为确定性初始焦点
        // -uitestDisableRotation: 暂停轮播自动旋转,防止测试序列中途翻页
        app.launchArguments = ["-uitestMockFeed", "-uitestFocusHeroPlay", "-uitestDisableRotation"]
        app.launch()

        let firstCardTitle = "秦牧化身月亮守，获得史诗级载具！"
        let firstCard = app.buttons.matching(NSPredicate(format: "label == %@", firstCardTitle)).firstMatch
        XCTAssertTrue(firstCard.waitForExistence(timeout: 15), "app 启动后应渲染出 mock feed 卡片")

        // hero 默认聚焦 Play 按钮;hero 高 1080pt,多按几次 ↓ 直到卡片行获得焦点
        var reachedFirstCard = false
        for _ in 0..<5 where !reachedFirstCard {
            XCUIRemote.shared.press(.down)
            reachedFirstCard = waitForAnyCardFocus(title: firstCardTitle, in: app)
        }
        XCTAssertTrue(reachedFirstCard, "按 ↓ 后焦点应落在首张卡片")

        // select 卡片 → NavigationStack push 详情页:feed 内容从 a11y 树移除(push 替换内容)。
        // 详情页加载中/失败/就绪态均接受,仅断言"已离开 feed"。
        XCUIRemote.shared.press(.select)
        let leaveFeed = waitForAnyCardGone(title: firstCardTitle, in: app)
        XCTAssertTrue(leaveFeed, "select 卡片后应进入详情页(feed 卡片移出 a11y 树)")

        // menu 返回 → feed 卡片重新出现。焦点恢复策略随详情页状态不定:
        // 详情页就绪态(初始焦点在 Play)对称映射回 feed hero Play;失败态则可能直接回卡片。
        // 两种路径都算"返回后焦点在 feed 内",卡片可重新聚焦即导航链路未破坏。
        XCUIRemote.shared.press(.menu)
        var backToFeed = waitForAnyCardFocus(title: firstCardTitle, in: app, timeout: 5.0)
        if !backToFeed {
            // 焦点落在 hero Play(或其它位置):按 ↓ 直到卡片行重新获得焦点(用户自然操作)
            for _ in 0..<6 where !backToFeed {
                XCUIRemote.shared.press(.down)
                backToFeed = waitForAnyCardFocus(title: firstCardTitle, in: app, timeout: 3.0)
            }
        }
        XCTAssertTrue(backToFeed, "menu 返回后应回到 feed 且焦点可重新落在卡片上")
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

    /// 轮询等待：标题匹配的卡片全部从 a11y 树消失（NavigationStack push 替换下层内容）
    @MainActor
    private func waitForAnyCardGone(title: String, in app: XCUIApplication, timeout: TimeInterval = 10) -> Bool {
        let cards = app.buttons.matching(NSPredicate(format: "label == %@", title))
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if cards.allElementsBoundByIndex.isEmpty {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return cards.allElementsBoundByIndex.isEmpty
    }
}
