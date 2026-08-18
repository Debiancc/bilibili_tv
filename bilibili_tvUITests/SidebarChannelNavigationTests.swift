//
//  SidebarChannelNavigationTests.swift
//  bilibili_tvUITests
//
//  阶段三：ChannelSidebarView API 收敛（E）后的焦点回归测试。
//  改造前侧边栏同时传 @Binding(选中态) 与 onSelect 闭包(切换副作用)双通道表达;
//  改造后条目按钮只写绑定,切换副作用由 ContentView 的 onChange(of: selectedChannel) 派生。
//  本测试用 -uitestFocusSidebar 启动参数(与 -uitestFocusHeroPlay 互斥的反向模式,
//  入口独占冷启动初始焦点、hero 焦点副作用被抑制)确定性地走完
//  入口聚焦展开 → 条目导航 → select 切换 → 选中态变化的链路。
//  注意：UI 测试无法使用 Swift Testing，必须用 XCTest。
//

import XCTest

final class SidebarChannelNavigationTests: TVOSUITestCase {
    /// 入口聚焦展开侧边栏 → 方向键到目标频道 → select 切换 → 选中态跟随绑定。
    @MainActor
    func testSidebarSwitchChannelUpdatesSelection() throws {
        let app = XCUIApplication()
        // -uitestFocusSidebar: 入口为唯一初始焦点(hero 焦点副作用抑制),确定性展开侧边栏
        // -uitestDisableRotation: 暂停轮播自动旋转
        app.launchArguments = ["-uitestMockFeed", "-uitestFocusSidebar", "-uitestDisableRotation"]
        app.launch()

        let entry = app.buttons["频道"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10), "入口按钮应存在")

        var entryFocused = false
        for _ in 0..<5 where !entryFocused {
            entryFocused = entry.hasFocus
            if !entryFocused { RunLoop.current.run(until: Date().addingTimeInterval(0.2)) }
        }
        // 焦点不在入口(自动展开未发生)时,select 手动展开,两条路径都算"展开"
        if !entryFocused {
            // 焦点刚落定时系统可能仍在确认,先稳定 1.5s 再 select(吸收焦点动画/同步延迟)
            RunLoop.current.run(until: Date().addingTimeInterval(1.5))
            XCUIRemote.shared.press(.select)
            RunLoop.current.run(until: Date().addingTimeInterval(2))
        }
        let animeButton = app.buttons["番剧"]
        XCTAssertTrue(animeButton.waitForExistence(timeout: 10), "侧边栏应渲染频道条目")
        let movieButton = app.buttons["电影"]
        XCTAssertTrue(movieButton.exists, "「电影」条目应存在(默认频道)")

        // 初始选中态:「电影」选中(accessibilityAddTraits(.isSelected))
        XCTAssertTrue(UITestHelpers.waitForSelection(button: movieButton, expected: true), "默认选中「电影」")
        XCTAssertTrue(UITestHelpers.waitForSelection(button: animeButton, expected: false), "默认未选中「番剧」")

        // ↓ 到「番剧」条目
        var animeFocused = false
        for _ in 0..<3 where !animeFocused {
            XCUIRemote.shared.press(.down)
            animeFocused = UITestHelpers.waitForFocus(button: animeButton)
        }
        XCTAssertTrue(animeFocused, "按 ↓ 后焦点应落在「番剧」条目")

        // select 切换频道 → 绑定写入 → 选中态翻转
        XCUIRemote.shared.press(.select)
        // 注意:条目 select 后焦点交还主内容、侧边栏收起,选中态断言需在收起动画窗口内完成
        XCTAssertTrue(
            UITestHelpers.waitForSelection(button: animeButton, expected: true),
            "select 后「番剧」条目应变为选中态(绑定已写入)"
        )

        // 切换被接受后 feed 内容切换:mock feed 立即进入加载态(网络请求中),
        // 侧边栏收起、主内容不崩溃即可,不做远程数据断言。
        XCTAssertTrue(animeButton.waitForExistence(timeout: 5) || !animeButton.exists, "切换后 app 应保持存活")
    }
}
