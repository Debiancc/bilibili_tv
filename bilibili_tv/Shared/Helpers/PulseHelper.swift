import Foundation
import SwiftUI

#if DEBUG
import Pulse
import PulseUI
#endif

/// Pulse 网络调试与全量抓包控制辅助类 (仅 DEBUG 构建生效)
@MainActor
final class PulseHelper {
    static let shared = PulseHelper()

    #if DEBUG
    let logger = NetworkLogger(store: .shared)
    #endif

    private init() {
        // 注意：不使用 enableAutomaticRegistration()，因为我们已手动指定 delegate，两者不能混用
    }

    #if DEBUG
    /// 创建绑定 Pulse 拦截器的 Session Proxy (支持 Async/Await API 完整捕获)
    /// 说明：URLSessionProxy 内部为 URLSession 注入 URLSessionProxyDelegate，
    /// 并在 async `data(for:)` 中显式记录任务完成，避免请求永远停留在 Pending 状态。
    func makeSession(configuration: URLSessionConfiguration) -> any URLSessionProtocol {
        URLSessionProxy(configuration: configuration, logger: logger)
    }
    #endif

    #if DEBUG
    /// 启动 Pulse RemoteLogger 远程日志服务
    func startRemoteLogging() {
        RemoteLogger.shared.isAutomaticConnectionEnabled = true

        LoggerStore.shared.storeMessage(
            label: "auth",
            level: .debug,
            message: "Will login user",
            metadata: ["userId": .string("uid-1")]
        )
    }
    #endif
}

#if DEBUG
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
#endif
