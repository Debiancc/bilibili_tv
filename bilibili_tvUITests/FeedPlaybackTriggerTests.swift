//
//  FeedPlaybackTriggerTests.swift
//  bilibili_tvUITests
//
//  Phase 1: 播放触发链路回归测试（XCUIRemote）。
//  重构后 Hero"立即播放"经环境 coordinator → 根视图单一 fullScreenCover 呈现。
//
//  焦点确定性：冷启动初始焦点在「侧栏入口」与「hero Play」之间存在竞态，
//  本测试用 -uitestFocusHeroPlay 启动参数禁用侧栏入口聚焦能力，使 hero 播放按钮
//  成为唯一初始焦点（详见 ContentView.isUITestHeroFocusMode），导航路径稳定：
//  下移 1 次到首张卡片，上移 1 次回到播放按钮，select 触发播放。
//
//  cover 呈现断言：加载/失败文案任一出现在的即可证明 BiliPlayerContainerView 已弹出
//  （实际视频加载依赖网络，不做成功断言）。
//

import XCTest

final class FeedPlaybackTriggerTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testHeroPlayNowButtonPresentsPlayerCover() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uitestMockFeed", "-uitestFocusHeroPlay", "-uitestDisableRotation"]
        app.launch()

        let firstCardTitle = "秦牧化身月亮守，获得史诗级载具！"
        let firstCards = app.buttons.matching(NSPredicate(format: "label == %@", firstCardTitle))
        XCTAssertTrue(firstCards.firstMatch.waitForExistence(timeout: 15), "app 启动后应渲染出 mock feed 卡片")
        // 等待焦点安置稳定（defaultFocus/兜底 Task 就绪）
        RunLoop.current.run(until: Date().addingTimeInterval(1))

        // 确定性初始焦点 = hero 播放按钮（聚焦展开时标签为"立即播放"，未聚焦时为符号名）
        let playButton = app.buttons
            .matching(NSPredicate(format: "label == '立即播放' OR identifier == 'play.fill'"))
            .firstMatch
        let deadline = Date().addingTimeInterval(5)
        var playFocused = false
        while Date() < deadline && !playFocused {
            playFocused = playButton.hasFocus
            if !playFocused {
                RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            }
        }
        XCTAssertTrue(playFocused, "确定性模式下初始焦点应落在播放按钮")

        // 下移 1 次到首张卡片（长轮询吸收焦点动画/滚动同步延迟）
        XCUIRemote.shared.press(.down)
        let cardDeadline = Date().addingTimeInterval(2)
        var cardFocused = false
        while Date() < cardDeadline && !cardFocused {
            cardFocused = firstCards.allElementsBoundByIndex.contains { $0.hasFocus }
            if !cardFocused {
                RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            }
        }
        XCTAssertTrue(cardFocused, "下移后焦点应落在首张卡片")
        XCTAssertTrue(navigateUpToPlay(playButton, in: app), "上移后焦点应回到播放按钮")

        XCUIRemote.shared.press(.select)

        // cover 呈现断言：加载中或失败文案任一出现在的即可证明播放器已弹出
        let loadingText = app.staticTexts["正在自适应加载高清视频流..."]
        let errorText = app.staticTexts["视频加载失败"]
        let coverDeadline = Date().addingTimeInterval(10)
        var coverPresented = false
        while Date() < coverDeadline && !coverPresented {
            coverPresented = loadingText.exists || errorText.exists
            if !coverPresented {
                RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            }
        }
        XCTAssertTrue(coverPresented, "select 播放按钮后应弹出播放器封面（加载中或失败态）")
    }

    /// 上移直到播放按钮获得焦点（卡片上方隔着一个续播 shelf，可能需要 1~2 次上移）。
    /// 无 shelf 时上移可能先落在 hero 区右侧按钮（详情/追剧/下一集），补向左横移找 play。
    /// 每次按压后长轮询，吸收焦点动画/滚动同步的延迟差异。
    @MainActor
    private func navigateUpToPlay(_ playButton: XCUIElement, in app: XCUIApplication) -> Bool {
        var playFocused = false
        for _ in 0..<3 where !playFocused {
            XCUIRemote.shared.press(.up)
            let deadline = Date().addingTimeInterval(2)
            while Date() < deadline && !playFocused {
                playFocused = playButton.hasFocus
                if !playFocused {
                    RunLoop.current.run(until: Date().addingTimeInterval(0.1))
                }
            }
            if !playFocused {
                for _ in 0..<3 where !playFocused {
                    XCUIRemote.shared.press(.left)
                    let leftDeadline = Date().addingTimeInterval(1.5)
                    while Date() < leftDeadline && !playFocused {
                        playFocused = playButton.hasFocus
                        if !playFocused {
                            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
                        }
                    }
                }
            }
        }
        return playFocused
    }
}
