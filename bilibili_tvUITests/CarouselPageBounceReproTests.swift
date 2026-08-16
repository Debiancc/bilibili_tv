//
//  CarouselPageBounceReproTests.swift
//  bilibili_tvUITests
//
//  复现/回归：hero 轮播图在焦点导航与自动轮播时"弹回上一页"的问题。
//  - testUserPagingDoesNotSnapBack：用户方向键逐页翻页，焦点应停留在目标页（不弹回）。
//  - testAutoRotateKeepsNewPage：自动轮播翻页后，轮播应停在下一页且焦点跟随（不弹回）。
//  用 -uitestMockFeed 注入 3 页 mock banner；通过"聚焦按钮的 frame.x"判断当前页
//  （tvOS .page TabView 各页横向排布，页宽 = 屏幕宽度 1920pt）。
//

import XCTest

final class CarouselPageBounceReproTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testUserPagingDoesNotSnapBack() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uitestMockFeed"]
        app.launch()

        let playButton = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "立即播放")).firstMatch
        XCTAssertTrue(playButton.waitForExistence(timeout: 15), "app 启动后 hero 应渲染出播放按钮")

        // 记录首页(页 0)聚焦播放按钮的 frame
        guard let page0Frame = waitForFocusedPlayFrame(in: app) else {
            XCTFail("初始焦点应落在 hero 播放按钮上")
            return
        }

        // 从 play(0) 右移到页 1：play → detail → bookmark → next → 页1 play，共 4 次
        press(.right, times: 4)
        guard let page1Frame = waitForFocusedPlayFrame(in: app) else {
            XCTFail("按 4 次 → 后焦点应落在页 1 播放按钮上")
            return
        }
        XCTAssertGreaterThan(page1Frame.minX, page0Frame.maxX + 1_000, "页 1 播放按钮应在页 0 右侧约一屏处")

        // 从 play(1) 左移回页 0：play → detail → bookmark → next → 页0 next，共 4 次
        press(.left, times: 4)
        guard let backFrame = waitForFocusedButtonFrame(in: app) else {
            XCTFail("按 4 次 ← 后应存在聚焦按钮")
            return
        }
        XCTAssertLessThan(backFrame.minX, 1_000, "按 ← 回退后焦点应在页 0（若弹回页 1 则 minX 接近 1920+）")

        // 弹回可能在落位后延迟发生：再等 1.5s 复检焦点没有跳回页 1
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        if let settledFrame = focusedPlayOrAnyButtonFrame(in: app) {
            XCTAssertLessThan(settledFrame.minX, 1_000, "焦点应停留在页 0，不应弹回页 1")
        }
    }

    @MainActor
    func testAutoRotateKeepsNewPage() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uitestMockFeed"]
        app.launch()

        let playButton = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "立即播放")).firstMatch
        XCTAssertTrue(playButton.waitForExistence(timeout: 15), "app 启动后 hero 应渲染出播放按钮")

        guard let page0Frame = waitForFocusedPlayFrame(in: app) else {
            XCTFail("初始焦点应落在 hero 播放按钮上")
            return
        }

        // 等待自动轮播(8s 间隔)触发一次翻页 + 过渡完成
        guard let rotatedFrame = waitForFocusedPlayFrame(in: app, timeout: 12, predicate: { $0.minX > page0Frame.minX + 1_000 }) else {
            XCTFail("自动轮播后焦点应跟随到页 1 的播放按钮")
            return
        }
        XCTAssertGreaterThan(rotatedFrame.minX, page0Frame.minX + 1_000, "自动轮播后应停留在页 1")

        // 复检：落位后再等 1.5s，确认没有弹回页 0
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        if let settledFrame = focusedPlayOrAnyButtonFrame(in: app) {
            XCTAssertGreaterThan(settledFrame.minX, page0Frame.minX + 1_000, "自动轮播后焦点不应弹回页 0")
        }
    }

    // MARK: - Helpers

    @MainActor
    private func press(_ button: XCUIRemote.Button, times: Int) {
        for _ in 0..<times {
            XCUIRemote.shared.press(button)
            RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        }
    }

    /// 轮询直到某个"立即播放"按钮获得焦点（展开态才有该文案），返回其 frame
    @MainActor
    private func waitForFocusedPlayFrame(
        in app: XCUIApplication,
        timeout: TimeInterval = 6,
        predicate: ((CGRect) -> Bool)? = nil
    ) -> CGRect? {
        let playButtons = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "立即播放"))
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let frame = playButtons.allElementsBoundByIndex.first(where: { $0.hasFocus })?.frame,
                predicate?(frame) ?? true
            {
                return frame
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return nil
    }

    /// 任意聚焦按钮的 frame（弹回后焦点可能落在图标按钮上，无"立即播放"文案）
    @MainActor
    private func waitForFocusedButtonFrame(in app: XCUIApplication, timeout: TimeInterval = 6) -> CGRect? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let frame = app.buttons.allElementsBoundByIndex.first(where: { $0.hasFocus })?.frame {
                return frame
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return nil
    }

    /// 当前聚焦按钮 frame（播放按钮优先），无轮询
    @MainActor
    private func focusedPlayOrAnyButtonFrame(in app: XCUIApplication) -> CGRect? {
        let playButtons = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "立即播放"))
        if let frame = playButtons.allElementsBoundByIndex.first(where: { $0.hasFocus })?.frame {
            return frame
        }
        return app.buttons.allElementsBoundByIndex.first(where: { $0.hasFocus })?.frame
    }
}
