//
//  PlayerFocusNavigationTests.swift
//  bilibili_tvUITests
//
//  阶段三 3c：DanmakuTransportBarItems 移出 View 后，播放器 transport bar 焦点回归测试。
//  用 -uitestMockPlayer 启动参数注入 .ready 态 PlayerViewModel + 本地生成视频
//  （无网络依赖，AVKit 有真实播放流才会渲染 transport bar）。
//  验证遥控器焦点能到达 transport bar 上的弹幕控制按钮（AVKit 公开 API
//  transportBarCustomMenuItems 渲染，焦点路径由 AVKit 管理——本测试兜底验证
//  菜单项可聚焦、可激活，重构后未被破坏）。
//  注意：UI 测试无法使用 Swift Testing，必须用 XCTest。
//

import XCTest

final class PlayerFocusNavigationTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// 验证 transport bar 的弹幕控制按钮可达：起播后遥控器 → 方向键能从播放/暂停
    /// 移动到弹幕控制按钮并获得焦点，Select 激活后菜单弹出（app 保持运行、焦点仍在按钮上）。
    @MainActor
    func testRemoteCanReachDanmakuControlButtonOnTransportBar() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uitestMockPlayer"]
        app.launch()

        // 本地 mock 视频自动起播；等 AVKit 播放器视图出现。
        // transportBarCustomMenuItems 在 a11y 树里是 CollectionView 的 Cell（非 Button），
        // 必须用 .any 后代查询 + label 匹配。
        let danmakuButton = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@", "弹幕")
        ).firstMatch

        // 起播后 transport bar 短暂自动出现；未出现时按 Select 手动唤出
        if !waitForExistence(danmakuButton, in: app, timeout: 8) {
            XCUIRemote.shared.press(.select)
        }
        XCTAssertTrue(
            waitForExistence(danmakuButton, in: app, timeout: 8),
            "transport bar 应包含弹幕控制按钮（transportBarCustomMenuItems 渲染）"
        )

        // 焦点导航：AVKit 的焦点路径在不同运行环境（本机/CI 模拟器）有差异，
        // 图标行可能在播放/暂停上方或同排。循环尝试 ↑ / → / ← 直到聚焦；
        // 若 transport bar 中途收起（a11y 树中按钮消失），按 Select 重新唤出。
        var reachedDanmaku = false
        let directions: [XCUIRemote.Button] = [.up, .right, .right, .right, .left, .left, .left, .up, .up]
        var presses = 0
        while !reachedDanmaku, presses < directions.count * 2 {
            if !danmakuButton.exists {
                XCUIRemote.shared.press(.select)
                _ = waitForExistence(danmakuButton, in: app, timeout: 2)
            }
            XCUIRemote.shared.press(directions[presses % directions.count])
            presses += 1
            reachedDanmaku = waitForFocus(danmakuButton, in: app)
        }
        XCTAssertTrue(reachedDanmaku, "方向键后焦点应落在弹幕控制按钮上")

        // 激活弹出子菜单:焦点仍在按钮上,app 保持前台运行
        XCUIRemote.shared.press(.select)
        XCTAssertEqual(app.state, .runningForeground, "激活弹幕控制菜单后 app 应仍在运行")
        // 弹幕控制按钮是 UIMenu:Select 后 AVKit 弹出菜单,子项(网络诊断等)进入 a11y 树
        let menuItem = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@", "网络诊断")
        ).firstMatch
        XCTAssertTrue(
            waitForExistence(menuItem, in: app, timeout: 5),
            "激活弹幕控制后应弹出子菜单(含网络诊断)"
        )
    }

    /// 轮询等待：按钮出现在 a11y 树中
    @MainActor
    private func waitForExistence(_ element: XCUIElement, in app: XCUIApplication, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.exists {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return element.exists
    }

    /// 轮询等待：按钮获得焦点（tvOS 焦点更新有少量延迟）
    /// 注意：元素可能因 transport bar 收起而离开 a11y 树——先判 exists 再查
    /// hasFocus，避免对不存在的元素取快照抛 "Failed to get matching snapshot"。
    @MainActor
    private func waitForFocus(_ element: XCUIElement, in app: XCUIApplication, timeout: TimeInterval = 1.5) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            guard element.exists else { return false }
            if element.hasFocus {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return element.exists && element.hasFocus
    }
}
