//
//  DetailFocusNavigationTests.swift
//  bilibili_tvUITests
//
//  阶段二：DetailViewModel 状态枚举化（DetailState）重构后的焦点回归测试。
//  用 -uitestMockDetail 启动参数注入 DetailViewModel.mock（.loaded 态，含 3 集选集），
//  验证状态机消费端改造后，遥控器方向键仍能在详情页 Play 按钮与选集卡片之间正常移动焦点，
//  @FocusState/FocusGuide 绑定未被破坏。
//  注意：UI 测试无法使用 Swift Testing，必须用 XCTest。
//

import XCTest

final class DetailFocusNavigationTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// 验证 .loaded 态下焦点能从 Play 按钮下移到选集卡片，并能在卡片间左右移动。
    @MainActor
    func testFocusMovesFromPlayButtonToEpisodeCardsAndAcrossCards() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uitestMockDetail"]
        app.launch()

        // mock 详情页 .loaded 态：播放按钮默认聚焦，选集卡片 a11y label 为「第N集 长标题」
        let firstEpisodeTitle = "第1集 梦回青春"
        let firstEpisode = app.buttons.matching(NSPredicate(format: "label == %@", firstEpisodeTitle)).firstMatch
        XCTAssertTrue(firstEpisode.waitForExistence(timeout: 15), "app 启动后应渲染出 mock 详情页选集卡片")

        // Play 按钮默认聚焦；选集卡片在下方，按 ↓ 直到焦点落到第一集
        var reachedFirstEpisode = false
        for _ in 0..<8 where !reachedFirstEpisode {
            XCUIRemote.shared.press(.down)
            reachedFirstEpisode = waitForAnyCardFocus(title: firstEpisodeTitle, in: app)
        }
        XCTAssertTrue(reachedFirstEpisode, "按 ↓ 后焦点应落在第一集卡片")

        // 向右移动到第二集
        let secondEpisodeTitle = "第2集 婚礼风波"
        XCUIRemote.shared.press(.right)
        XCTAssertTrue(
            waitForAnyCardFocus(title: secondEpisodeTitle, in: app),
            "按 → 后焦点应落在第二集卡片"
        )

        // 向左回到第一集
        XCUIRemote.shared.press(.left)
        XCTAssertTrue(
            waitForAnyCardFocus(title: firstEpisodeTitle, in: app),
            "按 ← 后焦点应回到第一集卡片"
        )
    }

    /// 阶段一：内联 fullScreenCover 收敛为根视图协调器 cover 后的播放回归——
    /// select 选集卡片应弹出播放器封面（加载中/失败文案任一出现），
    /// menu 关闭后焦点回到详情页（Play 按钮或选集卡片），详情页未被重建。
    @MainActor
    func testSelectEpisodePresentsCoverAndFocusReturnsAfterDismiss() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uitestMockDetail"]
        app.launch()

        // mock 详情页 .loaded 态：播放按钮默认聚焦，选集卡片 a11y label 为「第N集 长标题」
        let firstEpisodeTitle = "第1集 梦回青春"
        let firstEpisode = app.buttons.matching(NSPredicate(format: "label == %@", firstEpisodeTitle)).firstMatch
        XCTAssertTrue(firstEpisode.waitForExistence(timeout: 15), "app 启动后应渲染出 mock 详情页选集卡片")

        // 下移到第一集卡片
        var reachedFirstEpisode = false
        for _ in 0..<8 where !reachedFirstEpisode {
            XCUIRemote.shared.press(.down)
            reachedFirstEpisode = waitForAnyCardFocus(title: firstEpisodeTitle, in: app)
        }
        XCTAssertTrue(reachedFirstEpisode, "按 ↓ 后焦点应落在第一集卡片")

        // select 选集 → 播放器 cover 弹出(以 PlaybackCoverView 的稳定 identifier 为准)
        XCUIRemote.shared.press(.select)
        let cover = app.descendants(matching: .any).matching(identifier: "PlaybackCover").firstMatch
        let coverDeadline = Date().addingTimeInterval(10)
        var coverPresented = false
        while Date() < coverDeadline && !coverPresented {
            coverPresented = cover.exists
            if !coverPresented {
                RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            }
        }
        XCTAssertTrue(coverPresented, "select 选集后应弹出播放器封面（PlaybackCover）")

        // 关闭 cover:AVKit 控制层可见时 menu 先收起控制层,再按一次才关闭 cover。
        // 注意 fullScreenCover 下层详情页始终在 a11y 树中,必须用播放器特有的
        // PlaybackCover identifier 判断 cover 状态(加载/失败文案均不足以判定)。
        var menuPresses = 0
        let menuDeadline = Date().addingTimeInterval(15)
        while Date() < menuDeadline {
            if !cover.exists {
                RunLoop.current.run(until: Date().addingTimeInterval(0.3))
                continue
            }
            XCUIRemote.shared.press(.menu)
            menuPresses += 1
            RunLoop.current.run(until: Date().addingTimeInterval(0.7))
            if !cover.exists { break }
        }
        XCTAssertFalse(cover.exists, "按 menu 应能关闭播放器 cover(共按 \(menuPresses) 次)")

        // cover 关闭后详情页恢复,焦点回到 Play 按钮或选集卡片(不丢)
        XCTAssertTrue(firstEpisode.waitForExistence(timeout: 10), "关闭 cover 后应回到详情页")
        XCTAssertTrue(waitForFocusReturn(in: app), "关闭 cover 后焦点应回到详情页（Play 按钮或选集卡片）")
    }

    /// 回归(2026-09):长简介展开把「选集」横向行整体推下首屏折线后,焦点在简介
    /// 按钮上按 ↓ 必须能进入选集卡片行(垂直揭示经外层垂直 ScrollView 原生完成)。
    /// 用多选集 mock 确保横向几何差异不会干扰 ↓ 落点。
    @MainActor
    func testDownFromExpandedSynopsisReachesEpisodeRowBelowFold() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uitestMockDetail", "-uitestMockDetailLongSynopsis"]
        app.launch()

        // 长简介按钮(a11y label = 全文,取前缀匹配)
        let description = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "夏洛特烦恼是一部让人笑中带泪")
        ).firstMatch
        XCTAssertTrue(description.waitForExistence(timeout: 15), "app 启动后应渲染出长简介按钮")

        let firstEpisodeTitle = "第1集 梦回青春"
        let firstEpisode = app.buttons.matching(NSPredicate(format: "label == %@", firstEpisodeTitle)).firstMatch
        XCTAssertTrue(firstEpisode.waitForExistence(timeout: 15), "app 启动后应渲染出选集卡片")

        // Play 为初始焦点;简介按钮在操作行上方,按 ↑ 聚焦简介
        var focusedDescription = false
        for _ in 0..<3 where !focusedDescription {
            XCUIRemote.shared.press(.up)
            focusedDescription = UITestHelpers.waitForFocus(button: description, timeout: 1.5)
        }
        XCTAssertTrue(focusedDescription, "按 ↑ 后焦点应落在剧情简介按钮")

        // select 展开简介:选集行被推下首屏折线
        XCUIRemote.shared.press(.select)
        let expandedDeadline = Date().addingTimeInterval(5)
        var expanded = false
        while Date() < expandedDeadline && !expanded {
            expanded = description.value as? String == "已展开"
            if !expanded {
                RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            }
        }
        XCTAssertTrue(expanded, "select 后简介应展开")
        // 展开动画(spring response 0.4)把选集行推下首屏折线:轮询到位即止,
        // 替代固定 0.5s settle + 即时断言(防浅布局虚过)
        let pushedBelowFold = pollUntil(timeout: 3) { firstEpisode.frame.minY >= 1_080 }
        XCTAssertTrue(pushedBelowFold, "展开后选集行应整体位于首屏之下")

        // 按 ↓:焦点必须进入选集卡片行(揭示请求经外层垂直 ScrollView)
        var reachedEpisode = false
        for _ in 0..<5 where !reachedEpisode {
            XCUIRemote.shared.press(.down)
            reachedEpisode = waitForAnyCardFocus(title: firstEpisodeTitle, in: app)
        }
        XCTAssertTrue(reachedEpisode, "按 ↓ 后焦点应落在第一集卡片")
    }

    /// 回归(B4,手动验证发现):从选集行的任意卡片按 ↑,焦点必须回到操作行
    /// (立即播放/追剧),不能因横向几何失配落到简介按钮或完全被吞。
    /// 根因:焦点引擎的 ↑ 搜索只看"卡片正上方竖直带",而 Play/追剧/简介都在
    /// 屏幕左侧——卡1 正上方是播放、卡2 偏到追剧、卡3 偏到简介、卡4+ 无候选
    /// ↑ 被吞;选集行可左右滚动,落点随滚动位置漂移。
    /// 修复:选集行 onMoveCommand 在引擎处理前同步写焦点到播放按钮。
    /// 长简介展开让选集行在折线下,同时覆盖垂直揭示路径。
    @MainActor
    func testUpFromAnyEpisodeCardReturnsToActionRow() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uitestMockDetail", "-uitestMockDetailLongSynopsis"]
        app.launch()

        let firstEpisodeTitle = "第1集 梦回青春"
        let firstEpisode = app.buttons.matching(NSPredicate(format: "label == %@", firstEpisodeTitle)).firstMatch
        XCTAssertTrue(firstEpisode.waitForExistence(timeout: 15), "app 启动后应渲染出选集卡片")
        XCTAssertTrue(
            app.buttons.matching(NSPredicate(format: "label == %@", "第6集 梦醒时分")).firstMatch
                .waitForExistence(timeout: 15),
            "app 启动后应渲染出第 6 集卡片(多选集 mock)"
        )

        // 展开长简介:选集行推下首屏折线,↑ 必须同时完成垂直揭示与横向选位
        expandSynopsis(in: app, firstEpisode: firstEpisode)

        // ↓ 进入选集行(折线下,需垂直揭示)
        var reachedEpisode = false
        for _ in 0..<5 where !reachedEpisode {
            XCUIRemote.shared.press(.down)
            reachedEpisode = waitForAnyCardFocus(title: firstEpisodeTitle, in: app)
        }
        XCTAssertTrue(reachedEpisode, "按 ↓ 后焦点应落在第一集卡片")

        // 对卡 1..6 逐张验证:↑ 必须回到操作行(立即播放或追剧)
        for card in 1...6 {
            if card > 1 {
                // 逐次 → 直到目标卡持焦即停(press-then-short-poll,替代固定次数
                // 按键 + 固定 0.15s sleep;焦点跟手时少按,落位慢时由兜底宽限吸收)
                let title = "第\(card)集 \(episodeTitles[card - 1])"
                let reached = UITestHelpers.pressUntil(key: .right, maxPresses: card - 1, pollPerPress: 0.35) {
                    self.anyCardFocused(title: title, in: app)
                }
                XCTAssertTrue(reached, "应能右移到第 \(card) 张卡")
            }

            XCUIRemote.shared.press(.up)
            XCTAssertTrue(
                waitForActionRowFocus(in: app, timeout: 2.5),
                "第 \(card) 张卡按 ↑ 后焦点应回到操作行(立即播放/追剧)"
            )

            // 回落选集行:↓ 会几何落回操作按钮正下方的卡片(追剧→卡2、播放→卡1),
            // 故连按 ← 收敛回最左首卡,为下一轮做准备。每按一次即短轮询首卡焦点,
            // 收敛即早停——卡 N 只需 N-1 次 ←,无需对每张卡无条件按满 6 次
            XCUIRemote.shared.press(.down)
            var converged = waitForAnyCardFocus(title: firstEpisodeTitle, in: app, timeout: 0.5)
            for _ in 0..<6 where !converged {
                XCUIRemote.shared.press(.left)
                converged = waitForAnyCardFocus(title: firstEpisodeTitle, in: app, timeout: 0.35)
            }
            XCTAssertTrue(
                converged,
                "第 \(card) 张卡:↓ 回落选集行后应能收敛回首卡"
            )
        }
    }

    /// 展开长简介:↑ 聚焦简介按钮 → select 展开 → 选集行推下折线
    @MainActor
    private func expandSynopsis(in app: XCUIApplication, firstEpisode: XCUIElement) {
        let description = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "夏洛特烦恼是一部让人笑中带泪")
        ).firstMatch
        var focusedDescription = false
        for _ in 0..<3 where !focusedDescription {
            XCUIRemote.shared.press(.up)
            focusedDescription = UITestHelpers.waitForFocus(button: description, timeout: 1.5)
        }
        XCTAssertTrue(focusedDescription, "按 ↑ 后焦点应落在剧情简介按钮")
        XCUIRemote.shared.press(.select)
        let expandedDeadline = Date().addingTimeInterval(5)
        var expanded = false
        while Date() < expandedDeadline && !expanded {
            expanded = description.value as? String == "已展开"
            if !expanded {
                RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            }
        }
        XCTAssertTrue(expanded, "select 后简介应展开")
        // 展开动画(spring response 0.4)把选集行推下首屏折线:轮询到位即止,
        // 替代固定 0.5s settle + 即时断言(防浅布局虚过)
        let pushedBelowFold = pollUntil(timeout: 3) { firstEpisode.frame.minY >= 1_080 }
        XCTAssertTrue(pushedBelowFold, "展开后选集行应整体位于首屏之下")
    }

    /// 轮询等待:焦点落在操作行(立即播放或追剧按钮)
    @MainActor
    private func waitForActionRowFocus(in app: XCUIApplication, timeout: TimeInterval = 3) -> Bool {
        let playButton = app.buttons.matching(
            NSPredicate(format: "label == '立即播放' OR identifier == 'play.fill'")
        ).firstMatch
        let bookmark = app.buttons.matching(
            NSPredicate(format: "label == '追剧' OR label == '已追剧'")
        ).firstMatch
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if playButton.exists, playButton.hasFocus { return true }
            if bookmark.exists, bookmark.hasFocus { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return false
    }

    /// 选集长标题(与 DetailViewModel.mock 的 episodeLongTitles 对齐)
    private let episodeTitles = ["梦回青春", "婚礼风波", "梦想成真", "天王巨星", "时光倒流", "梦醒时分"]

    /// 轮询等待：cover 关闭后焦点恢复（Play 按钮或任一带"集"标签的选集卡片获得焦点）
    @MainActor
    private func waitForFocusReturn(in app: XCUIApplication, timeout: TimeInterval = 5) -> Bool {
        // tvOS 按钮未聚焦时 a11y label 为符号名（play.fill），聚焦展开后才变为文案
        let playButton = app.buttons.matching(
            NSPredicate(format: "label == '立即播放' OR identifier == 'play.fill'")
        ).firstMatch
        let cards = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "集"))
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if playButton.exists, playButton.hasFocus { return true }
            if cards.allElementsBoundByIndex.contains(where: { $0.hasFocus }) { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return false
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

    /// 即时判定:标题匹配的任意卡片实例是否持焦(供 pressUntil 轮询复用)
    @MainActor
    private func anyCardFocused(title: String, in app: XCUIApplication) -> Bool {
        app.buttons.matching(NSPredicate(format: "label == %@", title))
            .allElementsBoundByIndex.contains { $0.hasFocus }
    }

    /// 在 timeout 秒内以 0.1s 间隔轮询条件,命中即返回 true
    @MainActor
    private func pollUntil(timeout: TimeInterval, _ condition: @MainActor () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return condition()
    }
}
