import XCTest

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
