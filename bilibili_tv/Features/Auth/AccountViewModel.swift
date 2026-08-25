import Foundation
import Observation

/// 账号页状态机（互斥 enum，杜绝 isLoading/info/errorMessage 布尔可选拼接的非法态）
enum AccountState {
    case idle
    case loading
    case loaded(UserAccountInfo)
    /// 拉取失败（Cookie 失效 / 网络异常），携带用户可读文案
    case failed(String)
}

/// 账号页 ViewModel：拉取 nav 用户信息 + 退出登录
@Observable
@MainActor
class AccountViewModel {
    var state: AccountState = .loading

    private let service: BilibiliService

    init(service: BilibiliService = .shared) {
        self.service = service
    }

    /// 拉取登录用户信息；Cookie 失效时同步刷新 AuthManager 登录态，
    /// 让根视图自然回到登录页（而非停留在账号页报错）
    func loadUserInfo() async {
        state = .loading
        do {
            let info = try await service.fetchUserInfo()
            state = .loaded(info)
        } catch {
            AuthManager.shared.checkStoredCookies()
            if !AuthManager.shared.isLoggedIn {
                // Cookie 已失效:根视图将切回登录页,此处给终结态避免残留 loading 转圈
                state = .idle
                return
            }
            state = .failed("获取账号信息失败，请稍后重试")
        }
    }
}
