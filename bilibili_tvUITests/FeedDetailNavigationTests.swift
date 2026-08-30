//
//  FeedDetailNavigationTests.swift
//  bilibili_tvUITests
//
//  阶段二：Feed `selectedMovie` 详情导航收敛（B）后的焦点回归测试。
//  改造前 selectedMovie 经 FeedContentScrollView → ShelvesSection → MovieShelfView 三层绑定
//  穿透；改造后卡片 Button 经环境 PlaybackCoordinator.openDetail 直达根视图
//  navigationDestination。本测试验证：卡片 → select 进入详情页 → menu 返回后
//  焦点严格恢复到出发卡片实例（系统焦点恢复契约，不允许方向键补救）。
//
//  历史问题（2026-08 skip 解除调查结论）：
//  - 旧用例用「任意标题匹配实例」判定焦点（waitForAnyCardFocus），mock feed 中
//    hero 卡片与 shelf 卡片标题相同，且 menu 在 push 过渡动画期间按下时会触发
//    tvOS/SwiftUI 的系统级焦点竞态（feed 未重新 appear → 其 onAppear 兜底不重跑，
//    中断的过渡使恢复机制失效）→ 焦点全失（全树无持焦元素），↓ 无法移动（无焦点可移）。
//  - 实测确认：menu 在详情页完全呈现（详情按钮可见 + 1s 沉降）后按下，系统恢复
//    正常（焦点回到出发卡片）；过渡期内按下则是系统竞态，app 侧无状态残留可修
//    （activeDetail 正常清空，已用诊断日志验证），不做猜测式修补。
//  注意：UI 测试无法使用 Swift Testing，必须用 XCTest。
//

import XCTest

final class FeedDetailNavigationTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// shelf 卡片 → select 进入详情页 → menu 返回 → 焦点恢复到出发卡片实例。
    @MainActor
    func testShelfCardSelectPresentsDetailAndFocusReturns() throws {
        let app = XCUIApplication()
        // -uitestDisableRotation: 暂停轮播自动旋转,防止测试序列中途翻页
        app.launchArguments = ["-uitestMockFeed", "-uitestDisableRotation"]
        app.launch()

        let firstCardTitle = "秦牧化身月亮守，获得史诗级载具！"
        let cards = app.buttons.matching(NSPredicate(format: "label == %@", firstCardTitle))
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 15), "app 启动后应渲染出 mock feed 卡片")

        // ⚠️ sidebarAdaptable 冷启动焦点在系统侧边栏:先按 → 进内容区,再按 ↓ 落到
        // hero 卡片(mock feed 中 hero 与 shelf 卡片标题相同,↓ 首个命中是 hero 卡片)。
        XCUIRemote.shared.press(.right)
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        var reachedCard = false
        for _ in 0..<5 where !reachedCard {
            XCUIRemote.shared.press(.down)
            reachedCard = cards.allElementsBoundByIndex.contains { $0.hasFocus }
        }
        XCTAssertTrue(reachedCard, "按 ↓ 后焦点应落在 hero 卡片")

        // 记录出发卡片实例的几何位置:menu 返回后必须恢复到同一实例(同 Y 坐标)。
        // 容差 200 覆盖:聚焦缩放(±~15pt)与跨运行布局浮动(hero 卡片 Y 有 ~60pt 波动)
        guard let origin = cards.allElementsBoundByIndex.first(where: { $0.hasFocus }) else {
            XCTFail("未找到持焦卡片实例")
            return
        }
        let originY = origin.frame.minY

        // select 进入详情;等详情页完全呈现(追剧按钮可见 + 1s 沉降)再 menu ——
        // 在 push 过渡动画期间按 menu 会触发系统级焦点竞态(见文件头注释),真实用户
        // 也不会在过渡期间操作,故此处显式等待详情页稳定。
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(waitForAnyCardGone(title: firstCardTitle, in: app), "select 卡片后应进入详情页(feed 卡片移出 a11y 树)")
        let detailAnchor = app.buttons["追剧"].firstMatch
        _ = detailAnchor.waitForExistence(timeout: 5)
        RunLoop.current.run(until: Date().addingTimeInterval(1.0))

        XCUIRemote.shared.press(.menu)

        // 严格契约:焦点恢复到出发卡片实例(同 Y),不依赖方向键补救
        let deadline = Date().addingTimeInterval(6.0)
        var restored = false
        while Date() < deadline {
            if cards.allElementsBoundByIndex.contains(where: { $0.hasFocus && abs($0.frame.minY - originY) < 200 }) {
                restored = true
                break
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        if !restored {
            UITestHelpers.dumpTree(app: app, to: "/tmp/uitest_tree_detail_return.txt")
            let focused = Self.focusedButtonsReport(app: app)
            XCTFail("menu 返回后焦点未恢复到出发卡片(originY=\(originY))。持焦按钮: \(focused)")
        }
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

    /// 失败取证：列出当前持焦按钮（label + frame）
    @MainActor
    private static func focusedButtonsReport(app: XCUIApplication) -> [String] {
        var focusedButtons: [String] = []
        let deadline = Date().addingTimeInterval(1.0)
        while Date() < deadline {
            focusedButtons = app.buttons.allElementsBoundByIndex
                .filter { $0.exists && $0.hasFocus }
                .map { "\($0.label)@\($0.frame.origin)" }
            if !focusedButtons.isEmpty { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return focusedButtons
    }
}
