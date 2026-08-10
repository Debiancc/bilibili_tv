import Foundation

/// Feed 主页加载状态机（单一定义，杜绝布尔/可选拼接）。
/// 原 `isLoading: Bool` + `errorMessage: String?` 可组合出非法态
/// （如 errorMessage 非空且 isLoading=true），统一为互斥 enum。
enum FeedState: Equatable {
    case idle
    case loading
    case loaded
    case failed(message: String)
}
