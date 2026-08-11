import Foundation

/// 详情页加载状态机（互斥 enum，杜绝 isLoading/errorMessage/seasonDetail == nil 三态拼接的非法态）。
/// 与阶段一 FeedState 同款结构：idle 初始 / loading 请求中 / loaded 成功 / failed(message:) 失败可重试。
enum MovieDetailState: Equatable {
    case idle
    case loading
    case loaded
    case failed(message: String)
}
