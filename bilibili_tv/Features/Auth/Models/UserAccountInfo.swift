import Foundation

/// nav 接口登录用户信息（只解码 TV 端账号页实际使用的最小字段集）
struct UserAccountInfo: Codable, Equatable {
    /// 用户 mid
    let mid: Int64
    /// 昵称
    let uname: String
    /// 头像 URL
    let face: String
    /// 大会员标识
    let vipStatus: Int
    /// 等级
    let levelInfo: UserAccountLevelInfo

    var level: Int { levelInfo.currentLevel }

    enum CodingKeys: String, CodingKey {
        case mid, uname, face
        case vipStatus = "vipStatus"
        case levelInfo = "level_info"
    }
}

/// nav 接口响应外壳
struct UserAccountNavResponse: Codable {
    let code: Int
    let message: String?
    let data: UserAccountInfo?
}

/// 用户等级信息（nav.level_info）
struct UserAccountLevelInfo: Codable, Equatable {
    let currentLevel: Int

    enum CodingKeys: String, CodingKey {
        case currentLevel = "current_level"
    }
}
