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
}

enum QRCodeDisplayContentFactory {
    /// 将业务状态映射为卡片展示内容（穷尽 switch，禁止 if/else 拼接）
    ///
    /// - Note: 刻意保留了重构前的渲染语义 —— `.initial` / `.success` / `.error`
    ///   在旧实现中会落入"已失效"遮罩（布尔组合的 side effect），这里如实保留，
    ///   以便通过测试锁定功能等价性；如需修正为各状态专属语义，另行单独变更。
    static func make(for state: QRCodeState) -> QRCodeDisplayContent {
        switch state {
        case .initial, .expired, .success, .error:
            return .expired
        case .loading:
            return .progress
        case .ready(let url, _):
            return .awaitingScan(url: url)
        case .scanned(let url):
            return .scanned(url: url)
        }
    }
}
