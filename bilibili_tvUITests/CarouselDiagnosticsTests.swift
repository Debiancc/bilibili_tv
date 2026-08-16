//
//  CarouselDiagnosticsTests.swift
//  bilibili_tvUITests
//
//  诊断用：在 -uitestMockFeed 下 dump hero 轮播各页按钮/标题的 a11y 树状态与 frame，
//  供确认"当前页判定"的正确信号。所有 dump 汇总到结尾一次 XCTFail 输出。
//

import XCTest

final class CarouselDiagnosticsTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testDumpA11yStateAtEachStep() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uitestMockFeed"]
        app.launch()

        sleep(3)  // 等 feed/焦点稳定

        var report = dumpStep(app, label: "STEP0 初始状态")
        press(.right, times: 4, app: app)
        report += dumpStep(app, label: "STEP1 按 4 次 → 后")
        press(.left, times: 4, app: app)
        report += dumpStep(app, label: "STEP2 按 4 次 ← 后")

        // 无业务断言，诊断输出即结果
        XCTFail(report)
    }

    @MainActor
    private func dumpStep(_ app: XCUIApplication, label: String) -> String {
        var lines: [String] = ["== \(label) =="]

        let allButtons = app.buttons.allElementsBoundByIndex
        let focused = allButtons.filter { $0.hasFocus }
        lines.append("focused(\(focused.count)): " + focused.map { "label='\($0.label)' frame=\(fmt($0.frame))" }.joined(separator: " | "))

        let plays = allButtons.filter { $0.label.contains("立即播放") }
        lines.append("play(\(plays.count)): " + plays.map { "f=\($0.hasFocus) frame=\(fmt($0.frame))" }.joined(separator: " | "))

        let meta = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "热血 神魔")).firstMatch
        lines.append("page0-meta exists=\(meta.exists) frame=\(fmt(meta.frame))")

        for title in ["近战五行神兽？这是一场单方面的碾压！", "嫌疑人畏罪潜逃27年终落网"] {
            let t = app.staticTexts.matching(NSPredicate(format: "label == %@", title)).firstMatch
            lines.append("title'\(title.prefix(6))…' exists=\(t.exists) frame=\(fmt(t.frame))")
        }

        lines.append("ALL buttons(\(allButtons.count)):")
        lines.append(contentsOf: allButtons.map { "  label='\($0.label)' f=\($0.hasFocus) frame=\(fmt($0.frame))" })
        return lines.joined(separator: "\n") + "\n"
    }

    @MainActor
    private func press(_ button: XCUIRemote.Button, times: Int, app: XCUIApplication) {
        for _ in 0..<times {
            XCUIRemote.shared.press(button)
            RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        }
    }

    private func fmt(_ rect: CGRect) -> String {
        String(format: "(%.0f,%.0f %.0fx%.0f)", rect.minX, rect.minY, rect.width, rect.height)
    }
}
