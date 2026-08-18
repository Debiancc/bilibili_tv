#if DEBUG
import Foundation

/// UI 测试诊断通道（仅 DEBUG 构建编译）：
/// app 侧状态（焦点/状态机/onChange/按钮动作）以追加方式写入固定文件
/// `/tmp/uitest_diag.log`（带时间戳），测试失败后可直接 `cat` 查看，
/// 无需临时改代码插 FileHandle 再重编译。测试侧可先 `clear()` 再跑。
enum UITestDiagnostics {
    /// 诊断日志路径（模拟器文件系统与宿主共享 /tmp）
    static let logURL = URL(fileURLWithPath: "/tmp/uitest_diag.log")

    private static let queue = DispatchQueue(label: "uitest-diagnostics")

    /// 追加一条诊断记录：`[HH:mm:ss.SSS] message`（每行）
    static func log(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        let line = "[\(formatter.string(from: Date()))] \(message)\n"
        queue.sync {
            guard let data = line.data(using: .utf8) else { return }
            if FileManager.default.fileExists(atPath: logURL.path) {
                if let handle = try? FileHandle(forWritingTo: logURL) {
                    defer { try? handle.close() }
                    _ = try? handle.seekToEnd()
                    try? handle.write(contentsOf: data)
                }
            } else {
                try? data.write(to: logURL)
            }
        }
    }

    /// 清空诊断日志（测试前置调用，保证读取时只含本次运行的记录）
    static func clear() {
        queue.sync {
            try? Data().write(to: logURL)
        }
    }
}
#endif
