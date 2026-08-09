//
//  bilibili_tvFocusNavigationTests.swift
//  bilibili_tvUITests
//
//  阶段 0.1：验证 tvOS XCUITest 遥控器模拟能力（XCUIRemote.press(_:)）。
//  本文件是后续阶段一/二/三焦点导航测试的参考模板：
//  - 启动 app 后，用 XCUIRemote 模拟 Siri Remote 方向键/Select 移动焦点
//  - 断言焦点能到达目标控件（通过 hasFocus 或控件可命中判断）
//  注意：UI 测试无法使用 Swift Testing（见 swift-snapshot-testing 文档），必须用 XCTest。
//

import XCTest

final class FocusNavigationTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// 验证 XCUIRemote 可用：启动后模拟 Select 键不崩溃，app 保持运行。
    @MainActor
    func testRemoteCanSendSelectKeyWithoutCrashing() throws {
        let app = XCUIApplication()
        app.launch()

        // 等待任一按钮出现（登录页的刷新按钮或首页卡片）
        let anyButton = app.buttons.firstMatch
        XCTAssertTrue(anyButton.waitForExistence(timeout: 15), "app 启动后应存在可聚焦按钮")

        XCUIRemote.shared.press(.right)
        XCUIRemote.shared.press(.left)
        XCUIRemote.shared.press(.select)

        XCTAssertEqual(app.state, .runningForeground, "发送遥控器按键后 app 应仍在运行")
    }
}
