import Foundation

extension BilibiliService {
    /// 请求生成全新扫码登录二维码数据
    func generateQRCode() async throws -> QRCodeGenerateData {
        let api = BilibiliAPI.qrGenerate
        let response: QRCodeGenerateResponse = try await execute(urlString: api.urlString, method: "GET")

        guard response.code == 0, let data = response.data else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    /// 轮询二维码扫码确认状态
    func pollQRCodeStatus(qrcodeKey: String) async throws -> QRCodePollData {
        let api = BilibiliAPI.qrPoll(qrcodeKey: qrcodeKey)
        let response: QRCodePollResponse = try await execute(urlString: api.urlString, method: "GET", queryItems: api.queryItems)

        guard let data = response.data else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    /// 拉取当前登录用户信息（nav 接口，自动携带登录 Cookie）。
    /// 会话级缓存：侧边栏 label 与账号页共用，避免重复请求；
    /// 登出后由 AccountViewModel 在失败路径触发 checkStoredCookies 时自然失效
    /// （下次登录后首次调用会重新拉取）。
    /// - Returns: 用户信息；未登录时 nav 返回 code=-101，此处抛错由调用方处理
    func fetchUserInfo() async throws -> UserAccountInfo {
        if let cached = cachedUserInfo { return cached }
        let api = BilibiliAPI.userInfo
        let response: UserAccountNavResponse = try await execute(urlString: api.urlString, method: "GET")

        guard response.code == 0, let data = response.data else {
            throw URLError(.userAuthenticationRequired)
        }
        cachedUserInfo = data
        return data
    }
}
