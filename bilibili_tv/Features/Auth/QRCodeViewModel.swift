import Foundation
import Observation
import SwiftUI

enum QRCodeState {
    case initial
    case loading
    case ready(qrURL: String, qrcodeKey: String)
    case scanned
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
    
    var isLoading: Bool {
        if case .loading = state { return true }
        return false
    }
    
    var qrCodeURL: String? {
        switch state {
        case .ready(let url, _): return url
        case .scanned: return "scanned"
        default: return nil
        }
    }
    
    var isExpired: Bool {
        if case .expired = state { return true }
        return false
    }
    
    var isScanned: Bool {
        if case .scanned = state { return true }
        return false
    }
    
    @ObservationIgnored
    private nonisolated(unsafe) var pollTask: Task<Void, Never>? = nil
    private var currentQrcodeKey: String? = nil
    
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
            let result = try await BilibiliService.shared.generateQRCode()
            
            let url = result.url
            let key = result.qrcodeKey
            
            self.currentQrcodeKey = key
            self.state = .ready(qrURL: url, qrcodeKey: key)
            self.statusText = "请使用 哔哩哔哩 手机 App 扫描二维码"
            print("✅ [QRCodeVM] QR code generated successfully: key=\(key)")
            
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
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2秒
                
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
    private func pollStatus(qrcodeKey: String) async {
        do {
            let pollResult = try await BilibiliService.shared.pollQRCodeStatus(qrcodeKey: qrcodeKey)
            let code = pollResult.code
            
            print("🔄 [QR Poll] Status code: \(code) - \(pollResult.message)")
            
            switch code {
            case 0:
                // 0: 扫码登录成功
                self.state = .success
                self.statusText = "登录成功！正在跳转..."
                self.stopPolling()
                
                // 处理 Cookie 与重定向 Token 保存
                if let urlString = pollResult.url, let components = URLComponents(string: urlString) {
                    if let items = components.queryItems {
                        for item in items {
                            if item.name == "SESSDATA" {
                                BilibiliNetworkConfig.shared.sessData = item.value
                            } else if item.name == "DedeUserID" {
                                BilibiliNetworkConfig.shared.dedeUserId = item.value
                            }
                        }
                    }
                }
                
                // 刷新 AuthManager 全局状态
                AuthManager.shared.checkStoredCookies()
                
            case 86101:
                // 86101: 未扫码
                self.statusText = "请使用 哔哩哔哩 手机 App 扫描二维码"
                
            case 86090:
                // 86090: 已扫码未确认
                self.state = .scanned
                self.statusText = "已扫码，请在手机上确认登录"
                
            case 86038:
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
}
