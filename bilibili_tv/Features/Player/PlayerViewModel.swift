import AVFoundation
import Foundation
import Observation

/// 播放器加载所需的网络服务抽象，便于 ViewModel 注入 Mock 进行行为断言测试
/// （参照阶段一 FeedServicing / QRCodeAuthServicing 的协议注入模式）
@MainActor
protocol PlayerServicing: Sendable {
    func fetchPlayURL(epId: Int?, cid: Int?, seasonId: Int?, qn: Int) async throws -> PlayURLResult
    func fetchEpisodeCid(epId: Int, seasonId: Int?) async throws -> Int?
}

extension BilibiliService: PlayerServicing {}

/// 播放器加载状态机 + 核心加载逻辑（阶段三 3a）
///
/// 从 BiliPlayerContainerView 迁移出的部分：
/// - 加载状态机（`PlayerLoadState` 替代 isLoading/errorMessage/finalPlayerItem != nil 三态）
/// - `loadVideo()` 核心：qn 降级、DASH/MP4 双方案、metadata 附属逻辑、cid 解析
///
/// 仍留在 View 侧的部分（后续子阶段迁移）：
/// - 进度心跳 Timer / 播完上报 / 弹幕会话协调（3b/3c）
///
/// 并发/生命周期说明：View 的 `.task { await viewModel.loadVideo() }` 在视图消失时会被取消，
/// 但 unstructured Task 不继承调用方的取消状态，因此 VM 自持 `loadTask` 并在 `deinit` 中取消，
/// 保证播放器视图销毁时正在进行的加载请求一定被终止（测试见 PlayerViewModelTests 的 deinit 用例）。
@Observable
@MainActor
final class PlayerViewModel {
    /// 加载状态机（互斥 enum，杜绝布尔/可选拼接的非法态）
    var state: PlayerLoadState = .idle
    /// 就绪后的播放器实例（仅 .ready 态非 nil）
    var player: AVPlayer?

    /// 播放器加载完成后的 AVPlayerItem（.ready 态非 nil；teardown 后置 nil）
    private(set) var finalPlayerItem: AVPlayerItem?
    /// 试看片段流标志：未购买时仅返回试看片段，播放器叠加提示横幅
    private(set) var isPreviewOnly = false
    /// 试看提示的「观看全片」文案（大会员 vs 单片购买区分）
    private(set) var purchaseHintText: String?
    /// 弹幕所需 cid（playurl 响应优先，season/ep 详情兜底解析）
    private(set) var currentCid: Int?

    /// 📊 统计面板数据源（3a 随加载流程提前迁入，3b 将正式收敛 API）
    let statsViewModel = PlayerStatsViewModel()

    private let epId: Int?
    private let seasonId: Int?
    // metadata 三要素供 PlayerViewModel+ItemLoading.swift 的加载流程使用（跨文件 extension 需 internal）
    let title: String?
    let subtitle: String?
    let coverURL: URL?
    private let resumeTime: Double
    private let service: any PlayerServicing

    /// HLS ResourceLoader 强引用：AVAssetResourceLoaderDelegate 为 weak，必须由 VM 持有防止提前释放
    private var hlsLoader: BiliHLSResourceLoader?

    /// 加载任务：deinit 时取消，确保视图销毁后加载请求被终止
    /// （@MainActor 类的 deinit 无法访问隔离存储，参照 PlayerStatsViewModel.statsTimer 的 nonisolated(unsafe) 模式）
    @ObservationIgnored
    private nonisolated(unsafe) var loadTask: Task<Void, Never>?

    init(
        epId: Int?,
        seasonId: Int?,
        title: String? = nil,
        subtitle: String? = nil,
        coverURL: URL? = nil,
        resumeTime: Double = 0,
        service: any PlayerServicing = BilibiliService.shared
    ) {
        self.epId = epId
        self.seasonId = seasonId
        self.title = title
        self.subtitle = subtitle
        self.coverURL = coverURL
        self.resumeTime = resumeTime
        self.service = service
    }

    deinit {
        loadTask?.cancel()
    }

    /// 加载播放流（幂等守卫：仅从 idle/failed 发起，loading/ready 直接返回）
    ///
    /// 并发/生命周期注意：本方法先收集加载所需的全部输入（值类型快照），再把
    /// 实际加载流程交给 `PlayerItemLoader`——加载挂起期间不持有 self，
    /// 因此 VM 可在加载中途被释放（deinit 取消 loadTask，见 deinit_cancelsInFlightLoadTask 测试）。
    func loadVideo() async {
        switch state {
        case .idle, .failed:
            break
        case .loading, .ready:
            return
        }
        state = .loading

        loadTask?.cancel()
        let input = PlayerLoadInput(
            epId: epId, seasonId: seasonId,
            title: title, subtitle: subtitle, coverURL: coverURL,
            service: service, statsViewModel: statsViewModel)
        loadTask = Task<Void, Never> { [weak self] in
            let outcome = await PlayerItemLoader.load(input: input)
            guard let self else { return }
            self.apply(outcome)
        }
    }

    /// 🧹 播放器 teardown（View onDisappear 调用）：取消资源加载并释放播放器引用
    func tearDownPlayer() {
        finalPlayerItem?.cancelPendingSeeks()
        finalPlayerItem?.asset.cancelLoading()
        finalPlayerItem = nil
        player = nil
        hlsLoader = nil
    }

    /// 将 PlayerItemLoader 的加载结果写回状态机（加载挂起期间 VM 不存活于此，回写时必然短暂持有）
    private func apply(_ outcome: PlayerLoadOutcome) {
        // 🎬 试看标志位在 fetch 成功后即设置，即使后续 playerItem 构造失败也保留
        isPreviewOnly = outcome.isPreviewOnly
        purchaseHintText = outcome.purchaseHintText

        guard let playerItem = outcome.playerItem else {
            if let error = outcome.error {
                state = .failed(message: error.localizedDescription)
            }
            return
        }
        finalPlayerItem = playerItem
        hlsLoader = outcome.hlsLoader
        currentCid = outcome.currentCid
        player = AVPlayer(playerItem: playerItem)
        state = .ready
    }
}
