import Observation
import SwiftUI

/// 播放意图协调器：由根视图（ContentView）持有并经 `.environment(\.playbackCoordinator)` 注入，
/// 叶子视图（HeroBannerView / ResumeShelfView）直接调用 `play(_:)`，
/// 根视图以单一 `.fullScreenCover(item:)` 呈现。
///
/// 刻意不标注 `@MainActor`：本类仅承载一个由主线程 UI 动作同步写入的引用字段，
/// 无并发入口；同时非隔离的 `init` 允许作为 `EnvironmentKey` 默认值，
/// 使测试/预览在未注入时也能安全构建（默认实例的播放请求仅存在于测试语境，无副作用）。
@Observable
final class PlaybackCoordinator {
    /// 当前播放请求（nil = 无 cover 展示；cover 关闭时由 `fullScreenCover(item:)` 自动复位）
    var activePlayback: PlaybackContext?

    func play(_ context: PlaybackContext) {
        activePlayback = context
    }
}

// MARK: - Environment 注入

private struct PlaybackCoordinatorKey: EnvironmentKey {
    /// 默认值按需创建新实例（computed，避免非 Sendable 类型的 static 存储属性并发告警）：
    /// 未注入环境时（单测直接构建叶子视图 / Preview）保证不崩溃，且访问者互不共享状态。
    /// 生产路径下 ContentView 始终注入真实实例，叶子视图触发的是同一个根协调器。
    static var defaultValue: PlaybackCoordinator { PlaybackCoordinator() }
}

extension EnvironmentValues {
    var playbackCoordinator: PlaybackCoordinator {
        get { self[PlaybackCoordinatorKey.self] }
        set { self[PlaybackCoordinatorKey.self] = newValue }
    }
}
