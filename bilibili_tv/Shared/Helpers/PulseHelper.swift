import SwiftUI
import Foundation
//#if DEBUG && canImport(Pulse)
import Pulse
//#endif
//#if DEBUG && canImport(PulseUI)
import PulseUI
//#endif

final class DummySessionDelegate: NSObject, URLSessionDelegate {}

/// Pulse 网络调试与全量抓包控制辅助类
@MainActor
final class PulseHelper {
    static let shared = PulseHelper()
    
    let logger = NetworkLogger(store: .shared)
    
    private init() {
        // 注意：不使用 enableAutomaticRegistration()，因为我们已手动指定 delegate，两者不能混用
    }
    
    /// 创建绑定 Pulse 拦截器的 Session Delegate
    /// - 必须传入 logger 实例，否则 URLSessionProxyDelegate 无处写入请求数据
    func makeSessionDelegate() -> URLSessionDelegate {
        #if DEBUG
        return URLSessionProxyDelegate(logger: logger)
        #else
        return DummySessionDelegate()
        #endif
    }
}

/// 适用于 tvOS 的 Pulse 调试抓包控制台大屏展示视图
struct PulseConsoleContainerView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ConsoleView(store: .shared)
                .navigationTitle("Pulse 抓包调试控制台")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(action: {
                            dismiss()
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "xmark.circle.fill")
                                Text("关闭调试控制台")
                            }
                            .font(.system(size: 20, weight: .bold))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.card)
                    }
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.95))
    }
}
