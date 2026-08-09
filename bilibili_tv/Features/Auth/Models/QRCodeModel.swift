import Foundation

/// 申请二维码 API 响应结构
struct QRCodeGenerateResponse: Codable {
    let code: Int
    let message: String
    let data: QRCodeGenerateData?
}

struct QRCodeGenerateData: Codable {
    let url: String
    let qrcodeKey: String

    enum CodingKeys: String, CodingKey {
        case url
        case qrcodeKey = "qrcode_key"
    }
}

/// 轮询扫码状态 API 响应结构
struct QRCodePollResponse: Codable {
    let code: Int
    let message: String
    let data: QRCodePollData?
}

struct QRCodePollData: Codable {
    let url: String?
    let refreshToken: String?
    let timestamp: Int?
    let code: Int
    let message: String

    enum CodingKeys: String, CodingKey {
        case url
        case refreshToken = "refresh_token"
        case timestamp
        case code
        case message
    }
}
