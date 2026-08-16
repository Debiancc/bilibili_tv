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
        // CI 跳过:本测试以结尾 XCTFail 输出诊断 dump 为目的,必然红;
        // 仅在本地排查轮播问题时手动运行
        if ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true" {
            throw XCTSkip("diagnostics dump is a local-only tool (fails by design)")
        }
        // 容错模式:翻页裁剪会让 a11y 树在枚举中途变化,个别元素查询失败
        // 不应中断 dump —— 诊断输出(结尾 XCTFail)才是本测试的产物
        continueAfterFailure = true
        let app = XCUIApplication()
        app.launchArguments = ["-uitestMockFeed"]
        app.launch()

        sleep(3)  // 等 feed/焦点稳定

        var report = dumpStep(app, step: 0, label: "STEP0 初始状态")
        press(.right, times: 4, app: app)
        report += dumpStep(app, step: 1, label: "STEP1 按 4 次 → 后")
        press(.left, times: 4, app: app)
        report += dumpStep(app, step: 2, label: "STEP2 按 4 次 ← 后")

        // 无业务断言，诊断输出即结果
        XCTFail(report)
    }

    @MainActor
    private func dumpStep(_ app: XCUIApplication, step: Int, label: String) -> String {
        var lines: [String] = ["== \(label) =="]

        // 落盘截图到 /tmp:像素级地面真值(a11y 的 hasFocus 在部分环境不可靠)
        let shotURL = URL(fileURLWithPath: "/tmp/uitest_step\(step).png")
        try? app.screenshot().pngRepresentation.write(to: shotURL)
        lines.append("screenshot: \(shotURL.path)")

        // 单次受守卫遍历:翻页裁剪会让 a11y 树在枚举中途变化,
        // 逐个 exists 检查可在树收缩时安全截断,一次性收集 focused/play/全量行
        var focusedRows: [String] = []
        var playRows: [String] = []
        var allRows: [String] = []
        var idx = 0
        while true {
            let button = app.buttons.element(boundBy: idx)
            guard button.exists else { break }
            let row = "label='\(button.label)' f=\(button.hasFocus) frame=\(fmt(button.frame))"
            allRows.append("  \(row)")
            if button.hasFocus {
                focusedRows.append(row)
            }
            if button.label.contains("立即播放") {
                playRows.append(row)
            }
            idx += 1
        }
        lines.append("focused(\(focusedRows.count)): " + focusedRows.joined(separator: " | "))
        lines.append("play(\(playRows.count)): " + playRows.joined(separator: " | "))

        // 探针必须 nil 安全:弹回发生时目标页内容不在屏,a11y 查询为空,
        // 直接取 frame 会抛错中断 dump,丢失后续诊断信息
        let meta = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "热血 神魔")).firstMatch
        let metaExists = meta.exists
        lines.append("page0-meta exists=\(metaExists) frame=\(metaExists ? fmt(meta.frame) : "nil")")

        for title in ["近战五行神兽？这是一场单方面的碾压！", "嫌疑人畏罪潜逃27年终落网"] {
            let t = app.staticTexts.matching(NSPredicate(format: "label == %@", title)).firstMatch
            let tExists = t.exists
            lines.append("title'\(title.prefix(6))…' exists=\(tExists) frame=\(tExists ? fmt(t.frame) : "nil")")
        }

        lines.append("ALL buttons(\(idx)):")
        lines.append(contentsOf: allRows)
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
