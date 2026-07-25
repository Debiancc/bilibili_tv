import Foundation
import Observation

/// 🌟 特性 1：使用 Swift 6 原生 @Observable 宏全量替换身份认证管理器
@Observable
@MainActor
class AuthManager {
    static let shared = AuthManager()
    
    var isLoggedIn: Bool = false
    var currentSessData: String? = nil
    var currentDedeUserId: String? = nil
    
    private init() {
        checkStoredCookies()
    }
    
    /// 检查本地 HTTPCookieStorage 或 UserDefaults 中持久化的登录态 Cookie
    func checkStoredCookies() {
        let storage = HTTPCookieStorage.shared
        let cookies = storage.cookies ?? []
        
        var sessData: String? = nil
        var dedeUserId: String? = nil
        
        for cookie in cookies {
            if cookie.name == "SESSDATA" && !cookie.value.isEmpty {
                sessData = cookie.value
            } else if cookie.name == "DedeUserID" && !cookie.value.isEmpty {
                dedeUserId = cookie.value
            }
        }
        
        // 尝试 fallback 从 BilibiliNetworkConfig 读取
        if sessData == nil {
            sessData = BilibiliNetworkConfig.shared.sessData
        }
        if dedeUserId == nil {
            dedeUserId = BilibiliNetworkConfig.shared.dedeUserId
        }
        
        self.currentSessData = sessData
        self.currentDedeUserId = dedeUserId
        
        // 只要能识别出有效 SESSDATA，即视为已通过扫码认证登录
        let authenticated = (sessData != nil && !sessData!.isEmpty)
        self.isLoggedIn = authenticated
        
        print("🔐 [AuthManager] Current Auth Status: isLoggedIn=\(authenticated), dedeUserId=\(dedeUserId ?? "None")")
    }
    
    /// 退出登录并清除持久化 Cookie 凭证
    func logout() {
        let storage = HTTPCookieStorage.shared
        if let cookies = storage.cookies {
            for cookie in cookies {
                if cookie.name == "SESSDATA" || cookie.name == "DedeUserID" || cookie.name == "bili_jct" {
                    storage.deleteCookie(cookie)
                }
            }
        }
        
        BilibiliNetworkConfig.shared.sessData = nil
        BilibiliNetworkConfig.shared.dedeUserId = nil
        
        self.currentSessData = nil
        self.currentDedeUserId = nil
        self.isLoggedIn = false
        print("🚪 [AuthManager] User logged out, cleared authentication cookies.")
    }
}
