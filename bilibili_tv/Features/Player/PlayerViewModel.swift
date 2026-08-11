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

/// 观看进度记录抽象（3b：心跳上报可注入 Mock 断言调用参数）
/// 默认实现为 LocalWatchHistoryStore.shared（本地持久化 + 续播数据源）
@MainActor
protocol WatchHistoryRecording: Sendable {
    // swiftlint:disable function_parameter_count
    // 签名与 LocalWatchHistoryStore.record 一致（存储 API 固定 8 参），
    // 该存储方法在 main 上同样带 function_parameter_count warning，为既有容忍项
    func record(
        seasonId: Int?,
        epId: Int?,
        cid: Int?,
        title: String,
        episodeTitle: String?,
        coverURLString: String?,
        progress: Int,
        duration: Int
    )
    // swiftlint:enable function_parameter_count
}

extension LocalWatchHistoryStore: WatchHistoryRecording {}

/// 播放器加载状态机 + 核心加载逻辑（阶段三 3a）+ 进度上报（3b）
///
/// 从 BiliPlayerContainerView 迁移出的部分：
/// - 加载状态机（`PlayerLoadState` 替代 isLoading/errorMessage/finalPlayerItem != nil 三态）
/// - `loadVideo()` 核心：qn 降级、DASH/MP4 双方案、metadata 附属逻辑、cid 解析
/// - 进度心跳 Timer / 播完上报（3b 迁入；View 不再直接持有 Timer）
///
/// 仍留在 View 侧的部分（后续子阶段迁移）：
/// - 弹幕会话协调 / 试看横幅 / 统计 overlay（3c 迁入）
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
    var finalPlayerItem: AVPlayerItem?
    /// 试看片段流标志：未购买时仅返回试看片段，播放器叠加提示横幅
    private(set) var isPreviewOnly = false
    /// 试看提示的「观看全片」文案（大会员 vs 单片购买区分）
    private(set) var purchaseHintText: String?
    /// 弹幕所需 cid（playurl 响应优先，season/ep 详情兜底解析）
    var currentCid: Int?

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

    /// 进度心跳 Timer（3b 迁入；View 不再直接持有）
    @ObservationIgnored
    private nonisolated(unsafe) var progressReporterTimer: Timer?
    /// 播完上报观察者（AVPlayerItemDidPlayToEndTime）
    @ObservationIgnored
    private nonisolated(unsafe) var playbackEndObserver: NSObjectProtocol?
    /// 进度节流基准：两次上报的播放秒数差 < heartbeatInterval 时跳过
    private var lastReportedProgress: Int = 0

    /// 心跳间隔（测试可注入较小值，时序测试需等待超过该间隔再断言）
    private let heartbeatInterval: TimeInterval
    /// 进度记录存储（3b 注入抽象，测试用 Mock 断言调用参数）
    private let historyStore: any WatchHistoryRecording
    /// 当前播放秒数（测试可注入固定值；默认读 player.currentTime，无 item 时为 NaN）
    /// 参照 MockPlayerService 的注入模式：不注入时行为与真实环境一致
    var playbackTimeProvider: () -> Double?

    init(
        epId: Int?,
        seasonId: Int?,
        title: String? = nil,
        subtitle: String? = nil,
        coverURL: URL? = nil,
        resumeTime: Double = 0,
        heartbeatInterval: TimeInterval = 30,
        historyStore: any WatchHistoryRecording = LocalWatchHistoryStore.shared,
        service: any PlayerServicing = BilibiliService.shared
    ) {
        self.epId = epId
        self.seasonId = seasonId
        self.title = title
        self.subtitle = subtitle
        self.coverURL = coverURL
        self.resumeTime = resumeTime
        self.heartbeatInterval = heartbeatInterval
        self.historyStore = historyStore
        self.service = service
        self.playbackTimeProvider = { nil }
    }

    deinit {
        loadTask?.cancel()
        progressReporterTimer?.invalidate()
        if let playbackEndObserver {
            NotificationCenter.default.removeObserver(playbackEndObserver)
        }
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

    // MARK: - 3b: 进度上报（心跳 / 播完 / 后台）

    /// 🚀 启动进度上报（.ready 后由 View 调用）：
    /// - 心跳 Timer（默认 30s，force=false 节流；测试可注入更短间隔）
    /// - 播完观察者（AVPlayerItemDidPlayToEndTime → 以 duration 标记看完）
    /// 幂等：重复调用不重复启动。
    func startProgressReporting() {
        guard state == .ready, player != nil else { return }
        guard progressReporterTimer == nil else { return }

        progressReporterTimer = Timer.scheduledTimer(withTimeInterval: heartbeatInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.reportProgress(force: false)
            }
        }

        guard playbackEndObserver == nil else { return }
        playbackEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: finalPlayerItem,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.reportProgress(force: true, completed: true)
            }
        }
    }

    /// 🛑 停止进度上报（View onDisappear / 切后台调用）：停心跳、移除观察者、上报最终进度
    /// - Parameter reportFinal: 停止时是否上报一次当前进度（onDisappear 传 true；仅停心跳可传 false）
    func stopProgressReporting(reportFinal: Bool = true) {
        progressReporterTimer?.invalidate()
        progressReporterTimer = nil
        if let playbackEndObserver {
            NotificationCenter.default.removeObserver(playbackEndObserver)
        }
        playbackEndObserver = nil
        if reportFinal {
            reportProgress(force: true)
        }
    }

    /// 播放器就绪后（仅 .ready）恢复心跳：切回前台场景时调用
    func resumeProgressReportingIfReady() {
        guard state == .ready, progressReporterTimer == nil else { return }
        startProgressReporting()
    }

    /// 📡 上报当前观看进度（默认 heartbeatInterval 节流；force 跳过；completed 表示该集播完,以 duration 标记看完）
    /// 数据源 = 本地播放记录 (LocalWatchHistoryStore，经 historyStore 注入抽象);
    /// 远程上报 API (BilibiliService.reportWatchProgress, 需真实 aid 方能写入服务端历史) 为预留, 暂未接入
    /// （internal 供测试直接驱动节流断言，避免依赖 Timer 真实时序；生产路径仅经心跳/播完/后台调用）
    func reportProgress(force: Bool, completed: Bool = false) {
        let seconds: Double
        if completed, let duration = finalPlayerItem?.duration.seconds, duration.isFinite, duration > 0 {
            seconds = duration
        } else {
            // ⚠️ player 无有效 item 时 currentTime() 返回 kCMTimeInvalid (NaN),Int(NaN) 会 trap
            seconds = playbackTimeProvider() ?? player?.currentTime().seconds ?? 0
        }
        guard seconds.isFinite, seconds > 0 else { return }
        let t = Int(seconds)
        guard t > 0 else { return }
        if !force && abs(t - lastReportedProgress) < Int(heartbeatInterval) { return }
        lastReportedProgress = t

        let duration = finalPlayerItem?.duration.seconds ?? 0
        let itemDuration = duration.isFinite && duration > 0 ? Int(duration) : 0
        historyStore.record(
            seasonId: seasonId,
            epId: epId,
            cid: currentCid,
            title: title ?? "未命名影视",
            episodeTitle: subtitle,
            coverURLString: coverURL?.absoluteString,
            progress: t,
            duration: itemDuration
        )
        print("📼 [History] recorded locally: ep=\(epId ?? -1) ss=\(seasonId ?? -1) t=\(t)s dur=\(itemDuration)s")
        // 预留远程上报: BilibiliService.shared.reportWatchProgress(epId:seasonId:cid:playedTime:)
        // 接入前提: 从 pgc/view/web/season 解析该集真实 aid (aid=0 时服务端静默丢弃, 不写入历史)
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
