import XCTest

/// tvOS UI 测试基类：失败自动取证（a11y 树落盘 /tmp/uitest_failure_tree.txt）。
/// 配合 app 侧 UITestDiagnostics（/tmp/uitest_diag.log）与 UITestHelpers 使用。
/// @MainActor：XCUIApplication 等 XCUI API 为 MainActor 隔离。
/// 注意：test_case_accessibility 要求测试类成员必须 private，故基类不持有
/// app 成员（各测试在方法内创建局部 XCUIApplication）。
@MainActor
class TVOSUITestCase: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        UITestHelpers.clearDiagnostics()
    }

    override func tearDown() {
        if let failureCount = testRun?.failureCount, failureCount > 0 {
            let tree = XCUIApplication().debugDescription
            try? tree.write(toFile: "/tmp/uitest_failure_tree.txt", atomically: true, encoding: .utf8)
        }
        super.tearDown()
    }
}
