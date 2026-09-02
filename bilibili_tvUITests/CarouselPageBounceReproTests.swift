//
//  CarouselPageBounceReproTests.swift
//  bilibili_tvUITests
//
//  回归：hero 轮播图在焦点导航与自动轮播时"弹回上一页"的问题。
//  - testChainedCarouselPagingDoesNotSnapBack：链式合并 4 个同启动参数用例
//    （用户逐页翻页 / 末页右缘回绕 / 快速连按回退 / 单次跨页回退），段间自复位到页 0。
//  - testAutoRotateKeepsNewPage：自动轮播翻页后，轮播应停在下一页且焦点跟随(不弹回)。
//    用 -uitestRotationInterval=2 把"等真实 8s 轮播"压到 ~2s(issue #51)。
//  当前页判定用页 0 专属内容("热血 神魔" meta 文本)的可见性:
//  聚焦按钮的 frame.x 无法区分页码 —— 页面正常滚入后按钮都在屏幕坐标 ~x=86,
//  只有 bug 状态(焦点被拽到未滚动页)才会出现 1920+ 的虚拟坐标。
//

import XCTest

final class CarouselPageBounceReproTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// 链式合并（原 4 个独立用例共用一次冷启动 -uitestMockFeed -uitestDisableRotation，
    /// 每段结束都自复位到「页 0 + Play 持焦」，故段间无需显式复位）：
    /// 1. testUserPagingDoesNotSnapBack——用户方向键逐页翻页，目标页应保持
    /// 2. testRightFromLastPageBookmarkWrapsToFirstPagePlay——末页收藏按 → 回绕页 0
    /// 3. testRapidBackPagingDoesNotSnapBack——快速连按 ← 不弹回、边界不越界
    /// 4. testSingleLeftPressFromPage1DoesNotBounce——单次跨页 ← 不弹回（时间线采样）
    @MainActor
    func testChainedCarouselPagingDoesNotSnapBack() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uitestMockFeed", "-uitestDisableRotation"]
        app.launch()

        let playButton = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "立即播放")).firstMatch
        XCTAssertTrue(playButton.waitForExistence(timeout: 15), "app 启动后 hero 应渲染出播放按钮(初始焦点在 Play,展开态)")
        XCTAssertTrue(waitForPage0Visible(in: app), "启动后应停在页 0")

        userPagingDoesNotSnapBack(in: app)
        rightFromLastPageBookmarkWrapsToFirstPagePlay(in: app)
        rapidBackPagingDoesNotSnapBack(in: app)
        // 放最后:采样期间临时放开 continueAfterFailure(a11y 树随翻页裁剪变化,
        // 个别查询失败不应中断时间线采集)
        singleLeftPressFromPage1DoesNotBounce(in: app)
    }

    /// 自动轮播翻页后,轮播应停在下一页且焦点跟随(不弹回)。
    /// -uitestRotationInterval=2 把 8s 轮播间隔压到 2s,等待翻页从 ~8-9s 降到 ~2s。
    @MainActor
    func testAutoRotateKeepsNewPage() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uitestMockFeed", "-uitestRotationInterval=2"]
        app.launch()

        let playButton = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "立即播放")).firstMatch
        XCTAssertTrue(playButton.waitForExistence(timeout: 15), "app 启动后 hero 应渲染出播放按钮(初始焦点在 Play,展开态)")

        XCTAssertTrue(waitForPage0Visible(in: app), "启动后应停在页 0")

        // 等待自动轮播(2s 间隔)触发一次翻页:页 0 内容移出
        XCTAssertTrue(waitForPage0Hidden(in: app, timeout: 8), "自动轮播应翻到页 1")

        // 落位后再等 1.5s,确认没有弹回页 0,且焦点跟随到了新页的 Play
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        XCTAssertFalse(isPage0Visible(in: app), "自动轮播后不应弹回页 0")
        let playAfterRotate = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "立即播放")).firstMatch
        XCTAssertTrue(playAfterRotate.exists, "自动轮播后焦点应跟随到新页的 Play(展开态可见)")
    }

    // MARK: - 链式段（各段前置状态:页 0 在视口 + Play 持焦;结束状态相同）

    /// 段 1(原 testUserPagingDoesNotSnapBack):从 play(0) 逐次 → 直到正向确认页 1 落位,
    /// 落位后复检不弹回;再逐次 ← 回到页 0(回退方向不弹回)。
    @MainActor
    private func userPagingDoesNotSnapBack(in app: XCUIApplication) {
        // 「下一部」停用后页内只剩 3 个按钮，硬编码 4 次会多按一格落到页 1 的「详情」，
        // 后续 ← 序列就不再是跨页回退
        XCTAssertTrue(pressRightUntilPage1PlayFocused(in: app), "连续 → 应翻到页 1 且页 1 Play 获得焦点")

        // 弹回可能在落位后延迟发生：再等 1.5s 复检仍在页 1
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        XCTAssertFalse(isPage0Visible(in: app), "页 1 落位后不应弹回页 0")

        // 从 play(1) 逐次 ← 直到回到页 0（回退方向不弹回）
        XCTAssertTrue(pressLeftUntilPage0Visible(in: app), "连续 ← 应回到页 0")

        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        XCTAssertTrue(isPage0Visible(in: app), "回到页 0 后不应再弹去页 1")
    }

    /// 段 2(原 testRightFromLastPageBookmarkWrapsToFirstPagePlay):末页最后一个按钮
    /// (收藏)按 → 必须回绕到页 0 Play。焦点从末页按钮落上回绕锚点的交接期,
    /// focusedButton 短暂为 nil——isWrapAnchorEnabled 若不含 isWrapAnchorFocused,
    /// 锚点会在交接中途失去焦点资格,回绕被引擎掐断(历史缺陷,PR #46 review)。
    @MainActor
    private func rightFromLastPageBookmarkWrapsToFirstPagePlay(in app: XCUIApplication) {
        // 前进到页 1(正向落位探针,理由见 pressRightUntilPage1PlayFocused)
        XCTAssertTrue(pressRightUntilPage1PlayFocused(in: app), "连续 → 应翻到页 1 且页 1 Play 获得焦点")

        // 继续逐次 →,直到末页(页 2)的收藏按钮持焦点:
        // 「下一部」停用后页内按钮为 [play, detail, bookmark],跨页落点必是新页
        // play,故不硬编码次数;识别条件=末页可见+收藏获焦+屏内坐标
        XCTAssertTrue(
            pressRightUntilLastPageBookmarkFocused(in: app, maxPresses: 8),
            "连续 → 应到达末页收藏按钮"
        )

        // 末页收藏按 →:落上回绕锚点 → 重锚页 0 Play(含跨页回滚滚动,窗口放宽)
        XCUIRemote.shared.press(.right)
        XCTAssertTrue(waitForPage0PlayFocused(in: app, timeout: 4), "末页按 → 应回绕到页 0 且 Play 持焦点")
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        XCTAssertTrue(isPage0Visible(in: app), "回绕后不应弹回末页")
    }

    /// 段 3(原 testRapidBackPagingDoesNotSnapBack):页 1 上快速连按 ←(约 50ms 间隔,
    /// 按键落在翻页动画中途)应稳定回页 0;页 0 边界快速连按 ← 不越界、不弹跳。
    @MainActor
    private func rapidBackPagingDoesNotSnapBack(in app: XCUIApplication) {
        // 慢速前进到页 1（正向确认页 1 Play 落位，理由同段 1）
        XCTAssertTrue(pressRightUntilPage1PlayFocused(in: app), "连续 → 应翻到页 1 且页 1 Play 获得焦点")

        // 快速连按 ←:8 次足够跨回页 0 并有余量,多余的会被引擎按边界吞掉
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

    /// 段 4(原 testSingleLeftPressFromPage1DoesNotBounce):单次 ← 回退(真实用户最常见
    /// 操作)跨页回退应一次到位、不弹回。
    /// 历史:TabView(.page) 时代单次跨页 ← 会被引擎在 ~1.5-2s 后弹回(框架级
    /// 怪癖,应用层无解);改用持久页 ScrollView 轮播后已修复,本用例转绿守护。
    @MainActor
    private func singleLeftPressFromPage1DoesNotBounce(in app: XCUIApplication) {
        continueAfterFailure = true

        // 逐次 → 直到跨页并正向确认页 1 落位(停手条件与理由见 pressRightUntilPage1PlayFocused)
        XCTAssertTrue(pressRightUntilPage1PlayFocused(in: app), "连续 → 应翻到页 1(页 1 Play 获得焦点)")

        RunLoop.current.run(until: Date().addingTimeInterval(0.5))

        // 单次 ←:从页 1 Play 出发跨页回退,这是引擎独立完成的最小场景
        XCUIRemote.shared.press(.left)

        // 0.2s 间隔采样 3s(历史弹回发生在 1.5-2.0s,留 1s 检出窗):
        // 页面可见性逐采样记录;持焦按钮的全树遍历开销大,只在捕获到弹回时记一次
        var timeline: [String] = []
        let start = Date()
        var bouncedAfterSettledOnPage0 = false
        var focusAtBounce: String?
        while Date().timeIntervalSince(start) < 3.0 {
            let t = Date().timeIntervalSince(start)
            let page0 = isPage0Visible(in: app)
            let page1 = isPage1Visible(in: app)
            timeline.append(String(format: "t=%.1f page0=%@ page1=%@", t, page0 ? "Y" : "N", page1 ? "Y" : "N"))
            if t > 1.5 && !page0 {
                bouncedAfterSettledOnPage0 = true
                if focusAtBounce == nil {
                    focusAtBounce = focusedButtonDescription(in: app)
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        let finalPage0 = isPage0Visible(in: app)
        if !finalPage0 || bouncedAfterSettledOnPage0 {
            let focusDesc = focusAtBounce ?? focusedButtonDescription(in: app)
            XCTFail("单次 ← 后发生弹回。弹回时焦点: \(focusDesc)。时间线:\n" + timeline.joined(separator: "\n"))
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
        poll(timeout: timeout) { self.isPage0Visible(in: app) }
    }

    @MainActor
    private func waitForPage0Hidden(in app: XCUIApplication, timeout: TimeInterval = 8) -> Bool {
        poll(timeout: timeout) { !self.isPage0Visible(in: app) }
    }

    @MainActor
    private func poll(timeout: TimeInterval, condition: @MainActor () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return condition()
    }

    /// 正向落位探针：页 1 在视口内且其「立即播放」持焦点（屏内坐标，排除未滚入页的虚拟坐标）。
    /// 跨页那一刻焦点必然落在新页的 Play，以此作停手条件可避免 a11y 树重建瞬态
    /// （meta 短暂查不到使 isPage0Visible 误报 false）造成的提前退出。
    @MainActor
    private func isPage1PlayFocused(in app: XCUIApplication) -> Bool {
        guard isPage1Visible(in: app) else { return false }
        var idx = 0
        while true {
            let button = app.buttons.element(boundBy: idx)
            guard button.exists else { break }
            if button.hasFocus,
                button.label.contains("立即播放"),
                button.frame.minX < 900
            {
                return true
            }
            idx += 1
        }
        return false
    }

    /// 逐次 → 直到正向确认页 1 落位（可见且其 Play 持焦点）即停（不硬编码按键次数）。
    /// 页内按钮数量随产品调整会变（「下一部」停用后由 4 个变 3 个），硬编码次数会
    /// 多按一格把焦点带到页 1 的「详情」，使后续 ← 退化成页内移动而非跨页回退。
    /// 不能用「页 0 不可见」作停手条件 —— a11y 树重建瞬态会让 meta 短暂查不到、
    /// 被误判为已跨页。maxPresses 只作防死循环上限，达上限仍未确认则返回 false。
    @MainActor
    private func pressRightUntilPage1PlayFocused(in app: XCUIApplication, maxPresses: Int = 8) -> Bool {
        for _ in 0..<maxPresses {
            XCUIRemote.shared.press(.right)
            RunLoop.current.run(until: Date().addingTimeInterval(0.4))
            if isPage1PlayFocused(in: app) { return true }
        }
        return isPage1PlayFocused(in: app)
    }

    /// 对称的反向导航：逐次 ← 直到页 0 回到视口。isPage0Visible 为真即正向信号，
    /// 瞬态误报（false）只会多按一次而不会提前停手。
    @MainActor
    private func pressLeftUntilPage0Visible(in app: XCUIApplication, maxPresses: Int = 8) -> Bool {
        for _ in 0..<maxPresses {
            XCUIRemote.shared.press(.left)
            RunLoop.current.run(until: Date().addingTimeInterval(0.4))
            if isPage0Visible(in: app) { return true }
        }
        return isPage0Visible(in: app)
    }

    /// 快速连按:极短间隔发送按键,让输入落在翻页/焦点动画中途(逼近连按/按住连发)
    @MainActor
    private func pressRapid(_ button: XCUIRemote.Button, times: Int, interval: TimeInterval) {
        for _ in 0..<times {
            XCUIRemote.shared.press(button)
            RunLoop.current.run(until: Date().addingTimeInterval(interval))
        }
    }

    // MARK: - 右缘回绕(PR #46 review 2026-09)

    /// 页 2 可见性:页 2 meta 独有"罪案",静止于视口时 x≈90
    @MainActor
    private func isPage2Visible(in app: XCUIApplication) -> Bool {
        guard let minX = pageMetaMinX(in: app, labelKeyword: "罪案") else { return false }
        return minX > -900 && minX < 1_000
    }

    /// 逐次 → 直到末页收藏按钮持焦点(末页可见 + 收藏获焦 + 屏内坐标)。
    /// 屏内坐标判定排除非可见页同名按钮的虚拟坐标(x≈±1920 的倍数)。
    @MainActor
    private func pressRightUntilLastPageBookmarkFocused(in app: XCUIApplication, maxPresses: Int) -> Bool {
        for _ in 0..<maxPresses {
            XCUIRemote.shared.press(.right)
            RunLoop.current.run(until: Date().addingTimeInterval(0.4))
            if isLastPageBookmarkFocused(in: app) { return true }
        }
        return isLastPageBookmarkFocused(in: app)
    }

    @MainActor
    private func isLastPageBookmarkFocused(in app: XCUIApplication) -> Bool {
        guard isPage2Visible(in: app) else { return false }
        return isFocusedButton(in: app, label: "收藏")
    }

    /// 页 0 可见且其 Play 持焦点——回绕终态探针
    @MainActor
    private func waitForPage0PlayFocused(in app: XCUIApplication, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if isPage0Visible(in: app), isFocusedButton(in: app, label: "立即播放", contains: true) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return isPage0Visible(in: app) && isFocusedButton(in: app, label: "立即播放", contains: true)
    }

    /// 遍历按钮找获焦且位于屏内(minX < 900,排除翻页瞬间的虚拟坐标)的指定标签按钮
    @MainActor
    private func isFocusedButton(in app: XCUIApplication, label: String, contains: Bool = false) -> Bool {
        var idx = 0
        while true {
            let button = app.buttons.element(boundBy: idx)
            guard button.exists else { break }
            let labelMatches = contains ? button.label.contains(label) : button.label == label
            if button.hasFocus, labelMatches, button.frame.minX < 900 {
                return true
            }
            idx += 1
        }
        return false
    }
}
