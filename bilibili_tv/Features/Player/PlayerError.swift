import Foundation

/// 播放器加载失败的领域错误（替换 NSError "PlayerError" -1/-2/-3 魔法码与字符串传递）。
/// 仅包含真实会发生的应用级错误类别：
/// - missingIdentifiers：缺 epId/seasonId（原 NSError -3）
/// - sourceUnavailable：无可用播放流（空流/大会员或 CDN 鉴权失败，原 NSError -1）
/// - unsupportedFormat：MP4 合成轨道创建失败（原 NSError -2）
/// - network / unknown：透传底层错误（URLError 与未知错误不丢弃诊断信息）
/// VIP/购买错误不在此枚举：试看走 isPreviewOnly 横幅路径，不产生 failed 状态。
enum PlayerError: Error, Equatable {
    /// 网络层错误（URLError 等），携带底层错误保持诊断信息
    case network(Error)
    /// 缺少剧集或季度 ID，无法发起加载
    case missingIdentifiers
    /// 无可用播放流（可能需要大会员或 CDN 鉴权失败）
    case sourceUnavailable
    /// 合成播放流失败（如无法创建 MP4 合成轨道）
    case unsupportedFormat
    /// 未知/内部错误，保留底层错误
    case unknown(Error)

    /// 面向用户的展示文案（UI 只消费本属性，不再解析字符串或 NSError code）
    var userMessage: String {
        switch self {
        case .network(let error):
            return error.localizedDescription
        case .missingIdentifiers:
            return "缺少剧集或季度 ID，无法播放"
        case .sourceUnavailable:
            return "无法解析播放流（可能需要大会员或 CDN 鉴权失败）"
        case .unsupportedFormat:
            return "无法创建合成轨道"
        case .unknown(let error):
            return error.localizedDescription
        }
    }

    /// 将任意底层错误归一化为 PlayerError：PlayerError 直接透传，
    /// URLError 归入 .network，其余归入 .unknown（均不丢弃诊断信息）。
    static func normalize(_ error: Error) -> PlayerError {
        if let playerError = error as? PlayerError {
            return playerError
        }
        if error is URLError {
            return .network(error)
        }
        return .unknown(error)
    }

    /// 基于 NSError domain+code 比较携带的底层错误（URLError/自定义 NSError 均覆盖）
    private static func underlyingEquals(_ lhsError: Error, _ rhsError: Error) -> Bool {
        let lhsNS = lhsError as NSError
        let rhsNS = rhsError as NSError
        return lhsNS.domain == rhsNS.domain && lhsNS.code == rhsNS.code
    }

    static func == (lhs: PlayerError, rhs: PlayerError) -> Bool {
        switch (lhs, rhs) {
        case (.network(let lhsError), .network(let rhsError)):
            return underlyingEquals(lhsError, rhsError)
        case (.missingIdentifiers, .missingIdentifiers):
            return true
        case (.sourceUnavailable, .sourceUnavailable):
            return true
        case (.unsupportedFormat, .unsupportedFormat):
            return true
        case (.unknown(let lhsError), .unknown(let rhsError)):
            return underlyingEquals(lhsError, rhsError)
        default:
            return false
        }
    }
}
