import AVFoundation
import AVKit
import Observation
import os
import SwiftUI

/// 背景视频链路日志(统一日志渠道,便于 simctl log / Console 抓取)
private let bannerVideoLog = Logger(subsystem: "bilibili_tv", category: "BannerVideo")

/// 轮播预告片取流服务抽象(可注入 Mock 断言生命周期;默认走 BilibiliService.shared)
@MainActor
protocol BannerVideoServicing: Sendable {
    func fetchBannerPreviewURL(epId: Int?, cid: Int?, seasonId: Int?, qn: Int) async throws -> String
    /// 失效缓存的预告片流 URL(播放失败时调用,避免重试命中过期签名)
    func invalidateBannerPreviewURL(epId: Int?, cid: Int?, seasonId: Int?, qn: Int)
}

extension BilibiliService: BannerVideoServicing {}

/// 轮播横幅背景视频控制器(单个 banner 条目对应一个实例):
/// 从 play_focus 取流(轻量 MP4)并播放 play_stime..play_etime 区间;
/// 生命周期:load → ready → playing(active 页) → pause(离屏) → finished/failed。
/// 与正片播放器(BiliPlayerContainerView + DASH/HLS 管线)完全解耦:
/// 无 transport bar、无弹幕、无 DRM,只输出"播完/失败"事件供轮播调度。
@MainActor
@Observable
final class BannerVideoController {
    /// 播放阶段(互斥 enum,不允许 idle/loading/failed 等布尔组合)
    enum Phase: Equatable, CustomStringConvertible {
        case idle
        case loading
        case playing
        /// 区间已播完:视频层隐藏(露出 fallback 背景图),等待 3s 后触发翻页
        case finished
        case failed

        var description: String {
            switch self {
            case .idle: return "idle"
            case .loading: return "loading"
            case .playing: return "playing"
            case .finished: return "finished"
            case .failed: return "failed"
            }
        }
    }

    private(set) var phase: Phase = .idle
    private(set) var player: AVPlayer?
    /// 区间播放进度 0..1(供指示条同步;驱动模式下倒计时=视频进度)
    private(set) var progress: CGFloat = 0

    /// 进入 playing(首帧就绪)
    var onReady: () -> Void = {}
    /// 进度更新(区间内 0..1)
    var onProgress: (CGFloat) -> Void = { _ in }
    /// 播放完区间(times==0 单遍语义,触发翻页)
    var onFinished: () -> Void = {}
    /// 取流/播放失败(宿主回退固定计时器)
    var onFailed: () -> Void = {}

    private var playFocus: PlayFocus?
    private var startTime: Double = 0
    private var endTime: Double = 0
    private var isMuted: Bool = true
    private var isActive = false
    /// 定时进度观察者令牌;deinit 兜底经 timeObserverRemoval 移除
    @ObservationIgnored
    private nonisolated(unsafe) var timeObserver: Any?
    /// deinit 兜底移除 time observer 的闭包:attach 时捕获当次的 player(弱引用)与令牌,
    /// 让非隔离的 deinit 无需触碰 @MainActor 的 player 属性即可清理
    /// (未走 teardown/fail 就释放 controller 的路径下,观察者仍会挂在 AVPlayer 上)
    @ObservationIgnored
    private nonisolated(unsafe) var timeObserverRemoval: (() -> Void)?
    /// 视频自然播完兜底(未到达 endTime 时,如过短视频):didPlayToEndTime 通知
    @ObservationIgnored
    private nonisolated(unsafe) var endNotificationObserver: Any?
    /// 取流/加载任务:teardown 与 deinit 均取消
    @ObservationIgnored
    private nonisolated(unsafe) var loadTask: Task<Void, Never>?
    /// 播完后的 fallback 图片停留计时(3s 后翻页);teardown/deinit 时取消
    @ObservationIgnored
    private nonisolated(unsafe) var fallbackTask: Task<Void, Never>?
    /// 加载代际:每次 teardown/发起加载递增;迟到的 createPlayer(asset 加载可能在
    /// 任务取消后仍成功完成)若代际不匹配则丢弃,不得更新 endTime/安装 player/observer
    private var loadGeneration = 0

    private let service: any BannerVideoServicing

    init(service: any BannerVideoServicing = BilibiliService.shared) {
        self.service = service
    }

    deinit {
        loadTask?.cancel()
        fallbackTask?.cancel()
        timeObserverRemoval?()
        if let endNotificationObserver {
            NotificationCenter.default.removeObserver(endNotificationObserver)
        }
    }

    func load(_ focus: PlayFocus?) {
        // 幂等守卫:同一 focus 且已进入加载/播放链路时跳过,避免 onAppear 与
        // onChange(playFocus) 在「数据到达与视图 appear 同时发生」时连续两次取流;
        // .failed 放行(允许同 focus 重试),.idle 放行(上次因无区间/快照跳过,跳过等价)。
        if focus == playbackFocus, phase != .idle, phase != .failed {
            bannerVideoLog.info("load skipped: same focus \(String(describing: focus?.epid)) phase=\(String(describing: self.phase))")
            return
        }
        teardown()
        playbackFocus = focus
        #if DEBUG
        if ContentView.isSnapshotTesting || ProcessInfo.processInfo.arguments.contains("-uitestMockFeed") {
            phase = .idle
            return
        }
        #endif
        guard let focus, let start = focus.playStime, let end = focus.playEtime, end > start else {
            bannerVideoLog.info("load skipped: no playable range stime=\(String(describing: focus?.playStime)) etime=\(String(describing: focus?.playEtime))")
            phase = .idle
            return
        }
        startTime = Double(start)
        endTime = Double(end)
        // 声音策略:默认开声。抓包 sound_switch 均为 false(代表运营静音标记),
        // 但产品预期轮播背景视频带声音(见需求确认),故不按该字段静音
        isMuted = false
        phase = .loading
        bannerVideoLog.info(
            "load: ep=\(String(describing: focus.epid)) cid=\(String(describing: focus.cid)) range=\(start)..\(end)"
        )
        startLoadTask()
    }

    /// 是否应驱动自动轮播(focus 有效且未失败);loading 期间同样算驱动,避免等待期被 8s 计时器翻页
    var drivesAutoRotation: Bool {
        phase == .loading || phase == .playing
    }

    func setActive(_ active: Bool) {
        bannerVideoLog.info("setActive \(active) phase=\(String(describing: self.phase))")
        isActive = active
        guard phase == .playing || phase == .finished, let player else { return }
        if active {
            if phase == .finished {
                // 播完后返回本页:seek 回区间起点重播,重新进入 playing(露出视频层)
                cancelFallback()
                player.seek(to: CMTime(seconds: startTime, preferredTimescale: 600)) { [weak self] _ in
                    // 与 createPlayer 同款身份守卫:teardown 后迟到的回调不得复活孤儿 player
                    guard let self, self.player === player, self.isActive else { return }
                    self.phase = .playing
                    player.play()
                }
            } else {
                player.play()
            }
        } else {
            player.pause()
            cancelFallback()
        }
    }

    func teardown() {
        // 代际递增:使在途任务的迟到结果(取流返回/createPlayer 完成)全部失效
        loadGeneration &+= 1
        loadTask?.cancel()
        loadTask = nil
        cancelFallback()
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        timeObserverRemoval = nil
        if let endNotificationObserver {
            NotificationCenter.default.removeObserver(endNotificationObserver)
        }
        endNotificationObserver = nil
        player?.pause()
        player = nil
        progress = 0
        phase = .idle
        playbackFocus = nil
    }

    // MARK: - 私有

    private var playbackFocus: PlayFocus?

    private func startLoadTask() {
        // ⚠️ 取流期间不得强持有 self:闭包内若保留强 self(如 guard let self 贯穿 await),
        // 未走 teardown 直接释放 controller 时 deinit 会被在途 Task 阻塞、取消永远无法
        // 生效(死锁)。参照 PlayerItemLoader 的值捕获模式:focus/service 先快照为局部值,
        // await 期间只弱引用 self,取流完成后再 `let self` 重新建立强引用。
        let focus = playbackFocus
        let service = self.service
        let generation = loadGeneration
        loadTask = Task { [weak self] in
            let url: String
            if let custom = focus?.autoplayUri, !custom.isEmpty {
                // 预留分支:autoplay_uri 运营自定义流(当前抓包全为空)
                url = custom
            } else {
                do {
                    url = try await service.fetchBannerPreviewURL(
                        epId: focus?.epid,
                        cid: focus?.cid,
                        seasonId: focus?.seasonId,
                        qn: 64
                    )
                } catch {
                    // teardown/deinit 取消取流属正常流程,不能当失败处理(见 fail() 注释)
                    guard !Task.isCancelled else { return }
                    bannerVideoLog.error("fetch failed: \(error.localizedDescription)")
                    self?.fail()
                    return
                }
            }
            guard !Task.isCancelled, let self, self.loadGeneration == generation else { return }
            bannerVideoLog.info("got stream: \(url.prefix(120))")
            await self.createPlayer(urlString: url, generation: generation)
        }
    }

    /// 资产验证结果(互斥,不允许布尔/可选组合):
    /// 迟到结果(stale)与真实失败(failed)必须区分——stale 静默丢弃,不得走 fail()
    private enum AssetValidationOutcome {
        /// 验证通过,附钳制后的区间终点(可等于原 endTime)
        case ready(endTime: Double)
        /// 取消或代际过期:静默丢弃,不触碰任何状态
        case stale
        /// 真实取流失败:走 fail()
        case failed
    }

    /// 验证流可达并钳制区间终点(await 期间可能被取消/换代):
    /// 每次 await 后校验代际与取消状态,迟到的结果一律返回 .stale,
    /// 不做任何状态变更(不更新 endTime、不装 player/observer)
    private func validateAsset(_ asset: AVURLAsset, generation: Int) async -> AssetValidationOutcome {
        do {
            _ = try await asset.loadTracks(withMediaType: .video)
            guard !Task.isCancelled, self.loadGeneration == generation else { return .stale }
            // ⚠️ 播放区间上界以视频物理时长为准:play_focus.play_etime 常大于实际视频长度
            // (实测 durl timelength=35.008s 而 etime=36),按 etime 等终点会因视频先自然结束
            // 而永远触发不了"播完"逻辑。endTime 取 min(etime, duration-0.3s)。
            let duration = try await asset.load(.duration)
            guard !Task.isCancelled, self.loadGeneration == generation else { return .stale }
            let videoSeconds = duration.seconds
            guard videoSeconds.isFinite, videoSeconds > 0 else { return .ready(endTime: self.endTime) }
            let clampedEnd = min(Double(self.endTime), videoSeconds - 0.3)
            guard clampedEnd > self.startTime + 0.1 else { return .ready(endTime: self.endTime) }
            return .ready(endTime: clampedEnd)
        } catch {
            // teardown/切页会取消 loadTask,此时抛 CancellationError 属正常流程,
            // 不能当失败处理(否则页面被永久标记 failed,且新任务成功后也会被旧任务的
            // fail() 打回 .failed —— 频道切换慢网络下必现)
            if Task.isCancelled || self.loadGeneration != generation { return .stale }
            bannerVideoLog.error("loadTracks failed: \(error.localizedDescription)")
            return .failed
        }
    }

    /// 播放预告片流:与正片 MP4 降级路径一致的鉴权方式——
    /// AVURLAsset 用 `AVURLAssetHTTPHeaderFieldsKey` 注入 streamHeaders(UA/Referer/Cookie),
    /// 并在创建前后验证流可达(loadTracks),失败即 fail。
    /// ⚠️ 代际守卫:asset 加载是协作式取消,任务取消后 await 仍可能成功返回;
    /// 每次 await 后与变更状态前校验 generation,迟到的旧加载直接丢弃
    private func createPlayer(urlString: String, generation: Int) async {
        guard let url = URL(string: urlString), !urlString.isEmpty else {
            guard self.loadGeneration == generation else { return }
            fail()
            return
        }
        let options: [String: Any] = ["AVURLAssetHTTPHeaderFieldsKey": PlayerItemLoader.streamHeaders]
        let asset = AVURLAsset(url: url, options: options)
        switch await validateAsset(asset, generation: generation) {
        case .stale:
            return
        case .failed:
            fail()
            return
        case .ready(let clampedEnd):
            self.endTime = clampedEnd
        }
        guard !Task.isCancelled, self.loadGeneration == generation else { return }
        let item = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: item)
        player.isMuted = isMuted
        player.actionAtItemEnd = .pause
        self.player = player
        // 兜底:视频物理播完(未到达 endTime,如过短视频/时长钳制失败)也进入 finished,
        // 避免播放器自然结束(actionAtItemEnd=.pause)后停在 playing、轮播永不翻页
        endNotificationObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: item,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.phase == .playing else { return }
            bannerVideoLog.info("natural end reached")
            self.finishRange()
        }
        installTimeObserver(on: player)
        player.seek(to: CMTime(seconds: startTime, preferredTimescale: 600)) { [weak self] _ in
            // 身份守卫:teardown/重载可能已换掉 player 或置 nil,迟到的 seek 回调
            // 不得复活孤儿 player(会无声播放且无视频层),与 time observer 同款守卫
            guard let self, self.player === player else { return }
            self.phase = .playing
            // 非活动页(预加载)就绪后保持静默:不播、不回调 ready,等 setActive(true)
            // 经 guard(phase == .playing)直接起播;避免 ready 事件误导轮播调度
            guard self.isActive else {
                bannerVideoLog.info("ready at \(self.startTime)s, waiting for activation")
                return
            }
            player.play()
            self.onReady()
            bannerVideoLog.info("playing from \(self.startTime)s to \(self.endTime)s muted=\(self.isMuted)")
        }
    }

    /// 定时(0.25s)推进区间进度;越过 endTime 时进入 finished
    private func installTimeObserver(on player: AVPlayer) {
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        let observer = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self, self.player === player else { return }
            let elapsed = time.seconds
            let span = self.endTime - self.startTime
            let token = min(max((elapsed - self.startTime) / max(span, 1), 0), 1)
            self.progress = CGFloat(token)
            self.onProgress(CGFloat(token))
            if elapsed >= self.endTime {
                self.finishRange()
            }
        }
        timeObserver = observer
        timeObserverRemoval = { [weak player] in
            player?.removeTimeObserver(observer)
        }
    }

    /// 区间播完(时间钳制到达或视频自然播完):隐藏视频层(露出 fallback 背景图),
    /// 停留 3s 后触发翻页。幂等:仅从 playing 进入,observer/通知双触发安全。
    /// 返回本页时 setActive 会 seek 回起点重播。
    private func finishRange() {
        guard phase == .playing, let player else { return }
        player.pause()
        phase = .finished
        progress = 1
        onProgress(1)
        bannerVideoLog.info("range ended")
        scheduleFallbackAndAdvance()
    }

    /// 失败:统一离开 playing/loading 进入 failed(不回退 phase,由宿主决定展示)
    private func fail() {
        cancelFallback()
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        timeObserverRemoval = nil
        if let endNotificationObserver {
            NotificationCenter.default.removeObserver(endNotificationObserver)
        }
        endNotificationObserver = nil
        player?.pause()
        player = nil
        // 失效缓存条目:取流/播放失败大概率是签名 URL 过期,失效后 .failed 重试会重新取流,
        // 而非在 TTL 内反复命中死链
        if let focus = playbackFocus {
            service.invalidateBannerPreviewURL(
                epId: focus.epid,
                cid: focus.cid,
                seasonId: focus.seasonId,
                qn: 64
            )
        }
        phase = .failed
        onFailed()
    }

    /// 单遍播完后的 fallback 图片停留:3 秒后触发翻页(需求:背景图展示 3s 再跳下一张)
    private func scheduleFallbackAndAdvance() {
        cancelFallback()
        fallbackTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled, let self else { return }
            self.fallbackTask = nil
            bannerVideoLog.info("fallback 3s elapsed, advancing page")
            self.onFinished()
        }
    }

    private func cancelFallback() {
        fallbackTask?.cancel()
        fallbackTask = nil
    }
}

/// AVPlayerViewController 承载(关闭系统控件):与正片播放容器同源的渲染路径。
/// 手动 AVPlayerLayer 嵌入 SwiftUI 层在模拟器上会"第一帧冻结"(播放时钟推进但画面不刷新),
/// 系统 AVPlayerViewController 的渲染管线无此问题。
private struct PlayerViewControllerRepresentable: UIViewControllerRepresentable {
    let player: AVPlayer?

    func makeUIViewController(context: Context) -> PlayerContainerViewController {
        let controller = PlayerContainerViewController()
        controller.playerViewController.showsPlaybackControls = false
        // ⚠️ 关键:禁止视频层参与 tvOS 焦点引擎与触摸——
        // 否则代表视图(UIKit)会覆盖 SwiftUI 按钮,右键焦点直接跳页、跳过 Play/详情/收藏按钮
        controller.playerViewController.view.isUserInteractionEnabled = false
        return controller
    }

    func updateUIViewController(_ controller: PlayerContainerViewController, context: Context) {
        controller.playerViewController.player = player
    }
}

/// 简单容器:透明背景 AVPlayerViewController,视频以封面填充模式铺满
private final class PlayerContainerViewController: UIViewController {
    let playerViewController = AVPlayerViewController()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        playerViewController.view.backgroundColor = .clear
        playerViewController.videoGravity = .resizeAspectFill
        // 轮播预告为非全屏浏览面内容,禁用自动显示标准匹配(帧率/动态范围),
        // 避免每次翻页触发 HDMI 帧率切换导致黑屏
        playerViewController.appliesPreferredDisplayCriteriaAutomatically = false
        // 与 makeUIViewController 的 isUserInteractionEnabled=false 保持一致,
        // 视频层仅渲染,不拦截焦点/触摸
        playerViewController.view.isUserInteractionEnabled = false
        addChild(playerViewController)
        playerViewController.didMove(toParent: self)
        view.addSubview(playerViewController.view)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        playerViewController.view.frame = view.bounds
    }
}

/// 轮播横幅视频背景层:
/// - `playFocus == nil`:返回空视图(idle),背景保持纯图片
/// - 视频状态变化经回调上报(page 已编制由宿主合成):ready 驱动轮播、progress 驱动指示条、
///   finished 翻页、failed 回退固定计时器
struct BannerVideoBackgroundView: View {
    let playFocus: PlayFocus?
    /// 是否激活(驱动 play/pause 切换)。由宿主经 isVideoActive 合成:
    /// 活动页 + 本 Tab 选中 + 焦点在轮播内 + 无本 Tab 路由/覆盖遮挡
    /// (isFeedCovered(for:) 已按 owner Tab 域内化,经参数链路透传至本处,
    /// 不再经环境重复门控——单一门控管线,状态流可静态追踪)
    let isActive: Bool
    var onReady: () -> Void = {}
    var onProgress: (CGFloat) -> Void = { _ in }
    var onFinished: () -> Void = {}
    var onFailed: () -> Void = {}

    /// 退后台/回前台联动:后台暂停(避免音频会话下预告片声音继续输出),前台恢复
    @Environment(\.scenePhase) private var scenePhase

    @State private var controller = BannerVideoController()

    /// ⚠️ 覆盖(详情页/播放 cover/账号页/控制台)必须经状态门控暂停,不得依赖
    /// onDisappear:TabView(sidebarAdaptable) + 常驻非 Lazy 层级下被覆盖视图的
    /// onDisappear 不保证触发(曾导致详情页下预告片持续出声);路由状态(binding
    /// 回写 → isVideoActive)才是「已离开 feed」的唯一契约事实源(Apple 文档口径)。
    /// 门控为 pause 而非 teardown:从详情/播放返回时视频从断点续播,零网络。
    /// onDisappear 仅保留为视图销毁时的最终清理。
    private var isEffectivelyActive: Bool {
        isActive
    }

    var body: some View {
        ZStack {
            if let player = controller.player, controller.phase == .playing {
                PlayerViewControllerRepresentable(player: player)
            }
        }
        .onAppear {
            bindCallbacks()
            controller.setActive(isEffectivelyActive)
            controller.load(playFocus)
        }
        .onChange(of: playFocus) { _, newFocus in
            bindCallbacks()
            controller.setActive(isEffectivelyActive)
            controller.load(newFocus)
        }
        .onChange(of: isEffectivelyActive) { _, active in
            controller.setActive(active)
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .background, .inactive:
                controller.setActive(false)
            case .active:
                controller.setActive(isEffectivelyActive)
            @unknown default:
                break
            }
        }
        .onDisappear {
            controller.teardown()
        }
    }

    private func bindCallbacks() {
        controller.onReady = onReady
        controller.onProgress = onProgress
        controller.onFinished = onFinished
        controller.onFailed = onFailed
    }
}
