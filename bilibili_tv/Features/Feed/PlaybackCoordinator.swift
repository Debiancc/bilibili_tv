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

    /// 哪个 Tab 拥有当前的 activeDetail。用于将详情隔离在各自的 Tab 内，
    /// 防止切换 Tab 时旧详情泄漏到新 Tab 的 NavigationStack。
    private(set) var activeDetailOwner: HomeTab?

    /// 非播放类全屏覆盖(账号页 / 调试控制台)呈现状态:
    /// 与播放 cover 一样,fullScreenCover 呈现不保证触发底层视图的 onDisappear,
    /// 轮播背景视频据此一并暂停,避免在覆盖层下继续出声/解码。
    /// 各覆盖独立记录(而非共享一个布尔),关闭其中一个时不得因后写覆盖而误恢复播放
    var isAccountOverlayPresented = false
    var isPulseConsoleOverlayPresented = false

    /// 任一辅助覆盖呈现即视为遮挡(OR 语义):
    /// 两个 cover 同时打开时,只关掉其中一个不应恢复轮播播放
    var isAuxiliaryOverlayPresented: Bool {
        isAccountOverlayPresented || isPulseConsoleOverlayPresented
    }

    /// 任一路由/覆盖盖在 feed 之上:轮播背景视频应暂停、自动轮播应停走。
    /// 各来源独立记录(播放 cover 与详情页可合法叠加),聚合为 OR;
    /// 关闭其中一个时不得因其它来源仍开启而误恢复播放。
    /// ⚠️ 消费方(BannerVideoBackgroundView / PageIndicatorView)必须订阅本聚合值,
    /// 不得改读底层单字段:新增覆盖来源时只需在此登记一处,遗漏门控即编译/测试可见。
    /// 详情页(NavigationStack push)必须纳入:onDisappear 在 TabView(sidebarAdaptable)
    /// + 常驻非 Lazy 层级下不保证触发(详见 BannerVideoBackgroundView 注释),
    /// 路由状态(binding 回写)才是「已离开 feed」的唯一契约事实源。
    var isFeedCovered: Bool {
        activePlayback != nil
            || activeDetail != nil
            || isAuxiliaryOverlayPresented
    }

    func play(_ context: PlaybackContext) {
        activePlayback = context
    }

    /// 详情导航意图：shelf 卡片 / hero 详情按钮直达根视图 NavigationStack。
    /// 与播放通道相互独立——详情页呈现期间播放 cover 仍可叠加（两者由不同容器承载）。
    func openDetail(_ item: FeedItem, owner: HomeTab) {
        activeDetail = item
        activeDetailOwner = owner
    }

    /// 清除详情（由 navigationDestination 的 set: nil 触发，或显式调用）
    func clearDetail() {
        activeDetail = nil
        activeDetailOwner = nil
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
