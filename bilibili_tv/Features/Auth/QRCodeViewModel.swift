import Foundation
import Observation

/// 扫码登录所需的网络服务抽象，便于 ViewModel 注入 Mock 进行单元测试
@MainActor
protocol QRCodeAuthServicing {
    func generateQRCode() async throws -> QRCodeGenerateData
    func pollQRCodeStatus(qrcodeKey: String) async throws -> QRCodePollData
}

extension BilibiliService: QRCodeAuthServicing {}

/// 二维码登录流程的业务状态机（单一定义，杜绝布尔/可选拼接）
enum QRCodeState: Equatable {
    case initial
    case loading
    case ready(qrURL: String, qrcodeKey: String)
    case scanned(qrURL: String)
    case success
    case expired
    case error(message: String)
}

/// 🌟 特性 1：使用 Swift 6 原生 @Observable 宏的 QRCodeViewModel
@Observable
@MainActor
class QRCodeViewModel {
    var state: QRCodeState = .initial
    var statusText: String = "正在生成登录二维码..."

    @ObservationIgnored
    private nonisolated(unsafe) var pollTask: Task<Void, Never>?
    private var currentQrcodeKey: String?

    private let service: any QRCodeAuthServicing

    init(service: any QRCodeAuthServicing = BilibiliService.shared) {
        self.service = service
    }

    deinit {
        pollTask?.cancel()
    }

    /// 请求生成全新的二维码
    func generateQRCode() async {
        state = .loading
        statusText = "正在生成登录二维码..."
        stopPolling()

        do {
            print("🚀 [QRCodeVM] Requesting QR code generation...")
            let result = try await service.generateQRCode()

            let url = result.url
            let key = result.qrcodeKey

            self.currentQrcodeKey = key
            self.state = .ready(qrURL: url, qrcodeKey: key)
            self.statusText = "请使用 哔哩哔哩 手机 App 扫描二维码"
            print("✅ [QRCodeVM] QR code generated successfully")

            // 开始轮询扫码结果
            startPolling(qrcodeKey: key)
        } catch {
            print("❌ [QRCodeVM] Failed to generate QR code: \(error.localizedDescription)")
            self.state = .error(message: error.localizedDescription)
            self.statusText = "生成二维码失败，请重试"
        }
    }

    /// 启动后台轮询轮询任务 (每 2 秒查询一次)
    private func startPolling(qrcodeKey: String) {
        stopPolling()

        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)  // 2秒

                guard let self = self, !Task.isCancelled else { break }
                await self.pollStatus(qrcodeKey: qrcodeKey)
            }
        }
    }

    /// 取消轮询
    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// 执行单次 轮询请求
    func pollStatus(qrcodeKey: String) async {
        do {
            let pollResult = try await service.pollQRCodeStatus(qrcodeKey: qrcodeKey)
            let code = pollResult.code

            print("🔄 [QR Poll] Status code: \(code) - \(pollResult.message)")

            switch code {
            case 0:
                // 0: 扫码登录成功
                self.state = .success
                self.statusText = "登录成功！正在跳转..."
                self.stopPolling()

                // 处理 Cookie 与重定向 Token 保存
                persistCookies(from: pollResult.url)

                // 刷新 AuthManager 全局状态
                AuthManager.shared.checkStoredCookies()

            case 86_101:
                // 86101: 未扫码
                self.statusText = "请使用 哔哩哔哩 手机 App 扫描二维码"

            case 86_090:
                // 86090: 已扫码未确认
                if case .ready(let url, _) = state {
                    self.state = .scanned(qrURL: url)
                }
                self.statusText = "已扫码，请在手机上确认登录"

            case 86_038:
                // 86038: 二维码已失效
                self.state = .expired
                self.statusText = "二维码已失效，请点击刷新"
                self.stopPolling()

            default:
                break
            }
        } catch {
            print("⚠️ [QR Poll] Poll error: \(error.localizedDescription)")
        }
    }

    /// 从登录成功回调 URL 的 query items 中提取 SESSDATA 与 DedeUserID 落盘
    private func persistCookies(from urlString: String?) {
        guard let urlString = urlString,
              let components = URLComponents(string: urlString),
              let items = components.queryItems
        else { return }

        for item in items {
            switch item.name {
            case "SESSDATA":
                BilibiliNetworkConfig.shared.sessData = item.value
            case "DedeUserID":
                BilibiliNetworkConfig.shared.dedeUserId = item.value
            default:
                break
            }
        }
    }
}
