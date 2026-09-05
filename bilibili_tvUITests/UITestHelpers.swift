import XCTest

enum UITestAccessibilityIdentifier {
    static func feedCard(shelfID: String, itemID: String) -> String {
        "feed.\(shelfID).card.\(itemID)"
    }

    static func episode(_ episodeID: Int) -> String {
        "detail.episode.\(episodeID)"
    }
}

/// tvOS UI 测试常用 helper：统一诊断取证与等待逻辑，避免各测试文件重复手写。
/// （test_case_accessibility 要求 XCTestCase 子类只含 private 非测试成员，
/// 故独立成枚举而非基类方法。）
@MainActor
enum UITestHelpers {
    /// 清空 app 侧诊断日志（/tmp/uitest_diag.log），保证读取时只含本次运行的记录
    static func clearDiagnostics() {
        try? Data().write(to: URL(fileURLWithPath: "/tmp/uitest_diag.log"))
    }

    /// 轮询等待按钮获得焦点
    static func waitForFocus(button: XCUIElement, timeout: TimeInterval = 3.0) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if button.exists, button.hasFocus {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return button.exists && button.hasFocus
    }

    /// 边按边轮询：每按一次 `key` 就短轮询 `condition`，命中立即返回。
    /// 替代"按一次 + 长超时等待"的串行写法——长超时在未命中的按键上全额烧掉
    /// （实测焦点落位多发生在下一次按键后 ~0.3s 内），是深滚类 UI 测试的最大耗时源。
    /// - Parameters:
    ///   - key: 每轮按下的遥控键
    ///   - button: 等待获得焦点的目标元素
    ///   - maxPresses: 最多按键次数
    ///   - pollPerPress: 每次按键后的轮询窗口
    ///   - graceAfterLastPress: 按键用尽后的兜底等待，防止最后一次按键的落位被截断而误判失败
    /// - Returns: 是否在预算内观察到焦点落位
    @MainActor
    static func pressUntilFocus(
        key: XCUIRemote.Button,
        button: XCUIElement,
        maxPresses: Int,
        pollPerPress: TimeInterval = 0.45,
        graceAfterLastPress: TimeInterval = 1.0
    ) -> Bool {
        pressUntil(
            key: key,
            maxPresses: maxPresses,
            pollPerPress: pollPerPress,
            graceAfterLastPress: graceAfterLastPress
        ) {
            button.exists && button.hasFocus
        }
    }

    /// pressUntilFocus 的通用化：每按一次 `key` 就短轮询任意目标状态 `condition`，
    /// 命中立即返回（如深滚到目标元素滚出视口、横向行军到指定卡片持焦）。
    /// 固定次数按键 + 固定 sleep 的写法在目标提前达成时烧掉多余按键与 settle，
    /// 在最后一次按键晚落位时又可能截断——轮询命中即止 + 兜底宽限两头都省。
    /// - Parameters:
    ///   - key: 每轮按下的遥控键
    ///   - maxPresses: 最多按键次数（防死循环上限）
    ///   - pollPerPress: 每次按键后的轮询窗口
    ///   - graceAfterLastPress: 按键用尽后的兜底轮询窗口（如滚动/焦点动画收尾）
    ///   - condition: 目标状态判定（每轮按键后及兜底期内反复求值）
    /// - Returns: 是否在预算内观察到目标状态
    @MainActor
    static func pressUntil(
        key: XCUIRemote.Button,
        maxPresses: Int,
        pollPerPress: TimeInterval = 0.45,
        graceAfterLastPress: TimeInterval = 1.0,
        condition: @MainActor () -> Bool
    ) -> Bool {
        for _ in 0..<maxPresses {
            XCUIRemote.shared.press(key)
            if poll(while: condition, window: pollPerPress) { return true }
        }
        return poll(while: condition, window: graceAfterLastPress)
    }

    /// 在 `window` 秒内以 0.1s 间隔反复求值 `condition`，命中即返回 true
    @MainActor
    private static func poll(while condition: @MainActor () -> Bool, window: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(window)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return condition()
    }

    /// 轮询等待选中态与预期一致（isSelected trait 由 accessibilityAddTraits 暴露）
    static func waitForSelection(button: XCUIElement, expected: Bool, timeout: TimeInterval = 5.0) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if button.exists, button.isSelected == expected {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return button.exists && button.isSelected == expected
    }

    /// 落盘当前 a11y 树（默认 /tmp/uitest_tree.txt），调试用
    static func dumpTree(app: XCUIApplication, to path: String = "/tmp/uitest_tree.txt") {
        try? app.debugDescription.write(toFile: path, atomically: true, encoding: .utf8)
    }
}
