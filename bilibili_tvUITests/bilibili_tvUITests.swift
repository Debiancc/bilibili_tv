//
//  bilibili_tvUITests.swift
//  bilibili_tvUITests
//
//  Created by debiancc on 2026/4/18.
//

import XCTest

final class bilibili_tvUITests: XCTestCase {
    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    @MainActor
    func testExample() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()

        // Use XCTAssert and related functions to verify your tests produce the correct results.
        // XCUIAutomation Documentation
        // https://developer.apple.com/documentation/xcuiautomation
    }

    @MainActor
    func testLaunchPerformance() throws {
        // 性能测试会反复冷启动 app 多次，在 CI 与本地全量回归中耗时最长，
        // 且对阶段一/二/三的纯重构无回归价值，阶段 0.1 起禁用。
        throw XCTSkip("启动性能测试耗时过长，已禁用")
    }
}
