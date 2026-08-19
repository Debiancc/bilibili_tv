import Observation
import SwiftUI

/// 播放/详情意图协调器：由根视图（ContentView）持有并经 `.environment(\.playbackCoordinator)` 注入，
/// 叶子视图（HeroBannerView / ResumeShelfView / ShelfView / DetailHeroSection）直接调用
/// `play(_:)` / `openDetail(_:)`，
/// 根视图以单一 `.fullScreenCover(item:)` 呈现播放、`.navigationDestination(item:)` 呈现详情。
///
/// 刻意不标注 `@MainActor`：本类仅承载一个由主线程 UI 动作同步写入的引用字段，
/// 无并发入口；同时非隔离的 `init` 允许作为 `EnvironmentKey` 默认值，
/// 使测试/预览在未注入时也能安全构建（默认实例的播放请求仅存在于测试语境，无副作用）。
@Observable
final class PlaybackCoordinator {
    /// 当前播放请求（nil = 无 cover 展示；cover 关闭时由 `fullScreenCover(item:)` 自动复位）
    var activePlayback: PlaybackContext?

    /// 当前详情请求（nil = 无详情页；详情页 pop 时由 `navigationDestination(item:)` 自动复位）
    var activeDetail: FeedItem?

    /// 搜索页是否呈现（侧边栏入口触发；SearchView pop 时由 `navigationDestination(isPresented:)` 自动复位）
    var isSearchPresented: Bool = false

    func play(_ context: PlaybackContext) {
        activePlayback = context
    }

    /// 详情导航意图：shelf 卡片 / hero 详情按钮直达根视图 NavigationStack。
    /// 与播放通道相互独立——详情页呈现期间播放 cover 仍可叠加（两者由不同容器承载）。
    func openDetail(_ item: FeedItem) {
        activeDetail = item
    }

    /// 搜索导航意图：侧边栏搜索入口触发 SearchView 呈现
    func openSearch() {
        isSearchPresented = true
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
