import SwiftUI
import Foundation
#if DEBUG && canImport(Pulse)
import Pulse
#endif
#if DEBUG && canImport(PulseUI)
import PulseUI
#endif

/// Pulse 网络调试与全量抓包控制辅助类
final class PulseHelper {
    static let shared = PulseHelper()
    
    private init() {}
    
    /// 启用 URLSession 的 Pulse 全量自动抓包扩展
    func configureURLSessionConfiguration(_ configuration: URLSessionConfiguration) {
        #if DEBUG && canImport(Pulse)
        // 自动将 Pulse 代理关联到 URLSession 实例
        URLSessionProxyDelegate.enableAutomaticRegistration()
        #endif
    }
}

/// 适用于 tvOS 的 Pulse 调试抓包控制台展示视图
struct PulseConsoleContainerView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        #if DEBUG && canImport(PulseUI)
        NavigationView {
            ConsoleView()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("关闭抓包面板") {
                            dismiss()
                        }
                    }
                }
        }
        #else
        VStack(spacing: 20) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 60))
                .foregroundColor(.blue)
            Text("Pulse 调试模块")
                .font(.title)
            Text("当前未在 Debug 环境下或未导入 PulseUI 库")
                .foregroundColor(.secondary)
            Button("关闭") {
                dismiss()
            }
            .buttonStyle(.card)
        }
        .padding(50)
        #endif
    }
}
