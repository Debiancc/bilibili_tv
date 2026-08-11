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
}
