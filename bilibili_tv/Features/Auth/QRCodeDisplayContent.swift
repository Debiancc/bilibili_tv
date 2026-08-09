import Foundation

/// 二维码卡片在当前业务状态下的展示内容（互斥展示态的纯数据描述）
///
/// 与 `QRCodeState` 一一对应，但只描述"卡片该显示什么"，
/// 不包含任何 SwiftUI 依赖，可脱离 UI 环境穷尽单元测试。
enum QRCodeDisplayContent: Equatable {
    case progress
    case awaitingScan(url: String)
    case scanned(url: String)
    case expired
    case success
    case error(message: String)
}

enum QRCodeDisplayContentFactory {
    /// 将业务状态映射为卡片展示内容（穷尽 switch，禁止 if/else 拼接）
    ///
    /// - Note: `.initial` / `.expired` 保留重构前渲染语义（落入"已失效"遮罩）；
    ///   `.success` / `.error` 映射为各自专属展示内容，不再复用失效遮罩。
    static func make(for state: QRCodeState) -> QRCodeDisplayContent {
        switch state {
        case .initial, .expired:
            return .expired
        case .loading:
            return .progress
        case .ready(let url, _):
            return .awaitingScan(url: url)
        case .scanned(let url):
            return .scanned(url: url)
        case .success:
            return .success
        case .error(let message):
            return .error(message: message)
        }
    }
}
