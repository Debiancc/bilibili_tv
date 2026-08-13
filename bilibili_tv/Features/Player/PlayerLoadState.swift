import Foundation

/// 播放器加载状态机（互斥 enum，杜绝 isLoading/errorMessage/finalPlayerItem != nil 三态拼接的非法态）。
/// 与阶段一 FeedState / 阶段二 MovieDetailState 同款结构：
/// idle 初始 / loading 请求中 / ready 加载完成 / failed(PlayerError) 失败可重试。
enum PlayerLoadState: Equatable {
    case idle
    case loading
    case ready
    case failed(PlayerError)
}
