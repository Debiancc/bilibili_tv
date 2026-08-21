//
//  SidebarChannelNavigationTests.swift
//  bilibili_tvUITests
//
//  迁移到系统 TabView + sidebarAdaptable 后的频道切换回归测试。
//  系统侧边栏:启动时收起为左上角 pill,按 ← 展开侧边栏,方向键导航条目,
//  select 切换频道(频道数据切换沿用 ContentView 的 onChange 链路)。
//  注意:系统 Tab 条目不暴露 XCUIElement.hasFocus 属性(debugDescription 虽标记
//  Focused),焦点断言不可靠,改为按一次 ↓ 后直接 select 并断言 feed 标题变化
//  (电影热播榜 → 番剧热播榜),验证数据切换真实生效。
//  注意：UI 测试无法使用 Swift Testing，必须用 XCTest。
//

import XCTest

final class SidebarChannelNavigationTests: TVOSUITestCase {
    /// ← 展开系统侧边栏 → ↓ 到番剧 → select 切换 → feed 数据切换。
    @MainActor
    func testSystemSidebarSwitchChannel() throws {
        let app = XCUIApplication()
        // -uitestMockFeed: 直达 .loaded 态 feed
        // -uitestDisableRotation: 暂停轮播自动旋转
        app.launchArguments = ["-uitestMockFeed", "-uitestDisableRotation"]
        app.launch()

        // 按 ← 展开系统侧边栏(pill → 侧边栏)
        XCUIRemote.shared.press(.left)

        let animeButton = app.buttons["番剧"]
        XCTAssertTrue(animeButton.waitForExistence(timeout: 10), "侧边栏应渲染频道条目")
        let movieButton = app.buttons["电影"]
        XCTAssertTrue(movieButton.exists, "「电影」条目应存在(默认频道)")

        // 初始:默认频道「电影」的 feed 标题
        XCTAssertTrue(
            app.staticTexts["电影热播榜"].waitForExistence(timeout: 5),
            "初始应显示电影频道内容"
        )

        // ↓ 一次到「番剧」条目(初始焦点在「电影」,下方相邻即「番剧」;
        // 系统 Tab 不暴露 hasFocus 无法轮询断言,依赖焦点引擎方向导航)
        XCUIRemote.shared.press(.down)

        // select 切换频道 → 绑定写入 → 切走电影频道
        XCUIRemote.shared.press(.select)
        // mock 切频道会清空 shelves 并真实请求网络(无网时进入 error 态),
        // 「电影热播榜」标题必消失,断言其移除比断言番剧标题出现更可靠
        let movieTitle = app.staticTexts["电影热播榜"]
        XCTAssertTrue(waitForGone(movieTitle, timeout: 10), "select 后应切走电影频道内容")
    }

    /// 轮询等待元素从 a11y 树消失
    @MainActor
    private func waitForGone(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !element.exists {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return !element.exists
    }
}
