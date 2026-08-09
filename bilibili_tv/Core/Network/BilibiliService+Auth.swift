import Foundation

extension BilibiliService {
    /// 请求生成全新扫码登录二维码数据
    func generateQRCode() async throws -> QRCodeGenerateData {
        let urlString = "https://passport.bilibili.com/x/passport-login/web/qrcode/generate"
        let response: QRCodeGenerateResponse = try await execute(urlString: urlString, method: "GET")

        guard response.code == 0, let data = response.data else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    /// 轮询二维码扫码确认状态
    func pollQRCodeStatus(qrcodeKey: String) async throws -> QRCodePollData {
        let urlString = "https://passport.bilibili.com/x/passport-login/web/qrcode/poll"
        let queryItems = [
            URLQueryItem(name: "qrcode_key", value: qrcodeKey)
        ]
        let response: QRCodePollResponse = try await execute(urlString: urlString, method: "GET", queryItems: queryItems)

        guard let data = response.data else {
            throw URLError(.badServerResponse)
        }
        return data
    }
}
