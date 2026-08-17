//
//  CarouselPageBounceReproTests.swift
//  bilibili_tvUITests
//
//  回归：hero 轮播图在焦点导航与自动轮播时"弹回上一页"的问题。
//  - testUserPagingDoesNotSnapBack：用户方向键逐页翻页，目标页应保持(不弹回)。
//  - testAutoRotateKeepsNewPage：自动轮播翻页后，轮播应停在下一页且焦点跟随(不弹回)。
//  当前页判定用页 0 专属内容("热血 神魔" meta 文本)的可见性:
//  聚焦按钮的 frame.x 无法区分页码 —— 页面正常滚入后按钮都在屏幕坐标 ~x=86,
//  只有 bug 状态(焦点被拽到未滚动页)才会出现 1920+ 的虚拟坐标。
//

import XCTest

final class CarouselPageBounceReproTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testUserPagingDoesNotSnapBack() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uitestMockFeed", "-uitestFocusHeroPlay", "-uitestDisableRotation"]
        app.launch()

        let playButton = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "立即播放")).firstMatch
        XCTAssertTrue(playButton.waitForExistence(timeout: 15), "app 启动后 hero 应渲染出播放按钮(初始焦点在 Play,展开态)")

        XCTAssertTrue(waitForPage0Visible(in: app), "启动后应停在页 0")

        // 从 play(0) 右移到页 1:play → detail → bookmark → next → 页1 play,共 4 次
        press(.right, times: 4)
        XCTAssertTrue(waitForPage0Hidden(in: app), "按 4 次 → 后应翻到页 1(页 0 内容移出 a11y 树)")
        let playAfterForward = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "立即播放")).firstMatch
        XCTAssertTrue(playAfterForward.waitForExistence(timeout: 4), "页 1 的 Play 应获得焦点并展开")

        // 弹回可能在落位后延迟发生:再等 1.5s 复检仍在页 1
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        XCTAssertFalse(isPage0Visible(in: app), "页 1 落位后不应弹回页 0")

        // 从 play(1) 左移回页 0:共 4 次
        press(.left, times: 4)
        XCTAssertTrue(waitForPage0Visible(in: app), "按 4 次 ← 后应回到页 0(回退方向不弹回)")

        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        XCTAssertTrue(isPage0Visible(in: app), "回到页 0 后不应再弹去页 1")
    }

    @MainActor
    func testAutoRotateKeepsNewPage() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uitestMockFeed", "-uitestFocusHeroPlay"]
        app.launch()

        let playButton = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "立即播放")).firstMatch
        XCTAssertTrue(playButton.waitForExistence(timeout: 15), "app 启动后 hero 应渲染出播放按钮(初始焦点在 Play,展开态)")

        XCTAssertTrue(waitForPage0Visible(in: app), "启动后应停在页 0")

        // 等待自动轮播(8s 间隔)触发一次翻页:页 0 内容移出
        XCTAssertTrue(waitForPage0Hidden(in: app, timeout: 14), "自动轮播应翻到页 1")

        // 落位后再等 1.5s,确认没有弹回页 0,且焦点跟随到了新页的 Play
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        XCTAssertFalse(isPage0Visible(in: app), "自动轮播后不应弹回页 0")
        let playAfterRotate = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "立即播放")).firstMatch
        XCTAssertTrue(playAfterRotate.exists, "自动轮播后焦点应跟随到新页的 Play(展开态可见)")
    }

    @MainActor
    func testRapidBackPagingDoesNotSnapBack() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uitestMockFeed", "-uitestFocusHeroPlay", "-uitestDisableRotation"]
        app.launch()

        let playButton = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "立即播放")).firstMatch
        XCTAssertTrue(playButton.waitForExistence(timeout: 15), "app 启动后 hero 应渲染出播放按钮(初始焦点在 Play,展开态)")

        XCTAssertTrue(waitForPage0Visible(in: app), "启动后应停在页 0")

        // 慢速前进到页 1
        press(.right, times: 4)
        XCTAssertTrue(waitForPage0Hidden(in: app), "按 4 次 → 后应翻到页 1")

        // 快速连按 ←(约 50ms 间隔,按键落在翻页动画中途,逼近真实连按/按住连发):
        // 8 次足够跨回页 0 并有余量,多余的会被引擎按边界吞掉
        pressRapid(.left, times: 8, interval: 0.05)

        // 收敛断言:最终应稳定在页 0(允许动画/焦点整理时间)
        XCTAssertTrue(waitForPage0Visible(in: app, timeout: 6), "快速连按 ← 后应回到页 0")
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        XCTAssertTrue(isPage0Visible(in: app), "快速回退落位后不应弹回页 1")

        // 再来一轮:页 0 上快速连按 ←(边界处,应停在页 0 不越界、不弹跳)
        pressRapid(.left, times: 4, interval: 0.05)
        RunLoop.current.run(until: Date().addingTimeInterval(1.0))
        XCTAssertTrue(isPage0Visible(in: app), "页 0 边界快速连按 ← 不应引发异常翻页")
    }

    /// 单次 ← 回退(真实用户最常见操作):跨页回退应一次到位、不弹回。
    /// 历史:TabView(.page) 时代单次跨页 ← 会被引擎在 ~1.5-2s 后弹回(框架级
    /// 怪癖,应用层无解);改用持久页 ScrollView 轮播后已修复,本用例转绿守护。
    @MainActor
    func testSingleLeftPressFromPage1DoesNotBounce() throws {
        // 采样期间 a11y 树会随翻页裁剪变化,个别查询失败不应中断时间线采集
        continueAfterFailure = true
        let app = XCUIApplication()
        app.launchArguments = ["-uitestMockFeed", "-uitestFocusHeroPlay", "-uitestDisableRotation"]
        app.launch()

        // 按 identifier 找 Play 按钮(不依赖展开态文案,兼容展开被禁用的诊断构建)
        let playButton = app.buttons.matching(identifier: "play.fill").firstMatch
        XCTAssertTrue(playButton.waitForExistence(timeout: 15), "app 启动后 hero 应渲染出播放按钮")
        XCTAssertTrue(waitForPage0Visible(in: app), "启动后应停在页 0")

        press(.right, times: 4)
        XCTAssertTrue(waitForPage0Hidden(in: app), "按 4 次 → 后应翻到页 1")

        RunLoop.current.run(until: Date().addingTimeInterval(0.5))

        // 单次 ←:从页 1 Play 出发跨页回退,这是引擎独立完成的最小场景
        XCUIRemote.shared.press(.left)

        // 0.2s 间隔采样 4s:页面可见性 + 焦点归属(含屏幕坐标,区分是哪一页的按钮)
        var timeline: [String] = []
        let start = Date()
        var bouncedAfterSettledOnPage0 = false
        while Date().timeIntervalSince(start) < 4.0 {
            let t = Date().timeIntervalSince(start)
            let page0 = isPage0Visible(in: app)
            let page1 = isPage1Visible(in: app)
            let focusDesc = focusedButtonDescription(in: app)
            timeline.append(String(format: "t=%.1f page0=%@ page1=%@ focus=%@", t, page0 ? "Y" : "N", page1 ? "Y" : "N", focusDesc))
            if t > 1.5 && !page0 { bouncedAfterSettledOnPage0 = true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        let finalPage0 = isPage0Visible(in: app)
        if !finalPage0 || bouncedAfterSettledOnPage0 {
            XCTFail("单次 ← 后发生弹回。时间线:\n" + timeline.joined(separator: "\n"))
        }
    }

    /// 受守卫遍历找聚焦按钮(树中途变化时安全截断)
    @MainActor
    private func focusedButtonDescription(in app: XCUIApplication) -> String {
        var idx = 0
        while true {
            let button = app.buttons.element(boundBy: idx)
            guard button.exists else { break }
            if button.hasFocus {
                return String(format: "%@(x=%.0f)", button.label, button.frame.minX)
            }
            idx += 1
        }
        return "nil"
    }

    // MARK: - Helpers

    /// 页面判定探针:持久页 ScrollView 轮播的所有页面常驻 a11y 树(虚拟坐标,
    /// 页 N 内容 x ≈ N×1920),"存在性"无法区分当前页 —— 用页 0 meta 的
    /// frame.minX 判定:页 0 在视口时 x≈90,滚出视口(页 1 可见)后 x≈-1830。
    @MainActor
    private func isPage0Visible(in app: XCUIApplication) -> Bool {
        guard let minX = pageMetaMinX(in: app, labelKeyword: "热血 神魔") else { return false }
        return minX > -900
    }

    /// 页 1 可见性:页 1 meta 静止于视口时 x≈90;页 0 在视口时 x≈2010
    @MainActor
    private func isPage1Visible(in app: XCUIApplication) -> Bool {
        guard let minX = pageMetaMinX(in: app, labelKeyword: "战斗 奇幻") else { return false }
        return minX > -900 && minX < 1_000
    }

    @MainActor
    private func pageMetaMinX(in app: XCUIApplication, labelKeyword: String) -> CGFloat? {
        let meta = app.staticTexts
            .matching(NSPredicate(format: "label CONTAINS %@", labelKeyword))
            .firstMatch
        guard meta.exists else { return nil }
        return meta.frame.minX
    }

    @MainActor
    private func waitForPage0Visible(in app: XCUIApplication, timeout: TimeInterval = 6) -> Bool {
        poll(timeout: timeout) { isPage0Visible(in: app) }
    }

    @MainActor
    private func waitForPage0Hidden(in app: XCUIApplication, timeout: TimeInterval = 8) -> Bool {
        poll(timeout: timeout) { !isPage0Visible(in: app) }
    }

    @MainActor
    private func poll(timeout: TimeInterval, condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return condition()
    }

    @MainActor
    private func press(_ button: XCUIRemote.Button, times: Int) {
        for _ in 0..<times {
            XCUIRemote.shared.press(button)
            RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        }
    }

    /// 快速连按:极短间隔发送按键,让输入落在翻页/焦点动画中途(逼近连按/按住连发)
    @MainActor
    private func pressRapid(_ button: XCUIRemote.Button, times: Int, interval: TimeInterval) {
        for _ in 0..<times {
            XCUIRemote.shared.press(button)
            RunLoop.current.run(until: Date().addingTimeInterval(interval))
        }
    }
}
