import AVFoundation
import Combine
import Foundation
import Observation
import UIKit

/// 弹幕设置存储键 (与 View 层 @AppStorage 共用同一 key)
enum DanmakuSettingsKeys {
    static let isEnabled = "danmaku.isEnabled"
    static let opacity = "danmaku.opacity"
    static let fontSize = "danmaku.fontSize"
    static let displayArea = "danmaku.displayArea"
    /// 弹幕展示时长(秒),决定滚动速度
    static let displayTime = "danmaku.displayTime"
}

/// 弹幕默认设置值(未在设置中调整过时使用,与 transport bar 菜单/首选项统一)
enum DanmakuDefaults {
    /// 默认字号(pt)
    static let fontSize: CGFloat = 33
    /// 弹幕合并窗口(秒):窗口内相同文本聚合为一条 cluster。
    /// 滑动续期语义:每次新弹幕到达续期(最后活跃后 10s 无新弹幕才封存)
    static let clusterWindowSeconds: TimeInterval = 10
    /// cluster 主文本字号相对基础字号的缩放上限(防超大字号压满屏)
    static let clusterMaxScale: CGFloat = 2.0
}

extension Notification.Name {
    /// 弹幕设置变化(transport bar 菜单修改后通知 DanmakuViewModel 刷新)
    static let danmakuSettingsDidChange = Notification.Name("danmakuSettingsDidChange")
}

/// 弹幕数据层抽象（3c 注入缝：单元测试可注入 stub，避免真实网络请求）
@MainActor
protocol DanmakuProviding {
    func initVideo(cid: Int, startPos: TimeInterval) async
    func playerTimeChange(time: TimeInterval) async -> [DanmakuProvider.Danmu]
}

extension DanmakuProvider: DanmakuProviding {}

/// 弹幕播放协调器:驱动 DanmakuProvider 数据层与 DanmakuView 渲染,
/// 通过 AVPlayer 周期时间回调同步发射弹幕,并处理 seek/暂停恢复
@MainActor
@Observable
final class DanmakuViewModel {
    private let provider: any DanmakuProviding
    private weak var danmakuView: DanmakuView?
    private weak var player: AVPlayer?
    private var timeObserver: Any?
    private var cid: Int?
    private var lastTickTime: TimeInterval?
    /// 正在执行的 tick 异步任务标志,防止多个 tick 交错调用 provider
    private var tickInFlight = false

    var isActive: Bool { cid != nil }

    private var cancellables = Set<AnyCancellable>()

    /// 弹幕合并引擎(10s 滑动续期窗口聚合相同文本;seek/停止时 reset)
    private var clusterEngine = ClusterDanmakuEngine()
    /// 活跃 cluster 展示模型(归一化文本 → model):实时计数增长时原位更新
    private var clusterModels: [String: DanmakuClusterCellModel] = [:]
    /// 渲染代际:start/stop/seek 时递增,丢弃挂起期间返回的旧位置弹幕结果
    private var renderGeneration = 0

    /// 会话生命周期状态:驱动弹幕渲染层显示/隐藏（SwiftUI 经 @Observable 直接跟踪）
    private(set) var sessionState: SessionState = .idle

    enum SessionState {
        case idle
        case active
    }

    // MARK: - 设置缓存 (applySettings 刷新,避免每帧/每弹幕读 UserDefaults)

    private var cachedFontSize: CGFloat = DanmakuDefaults.fontSize
    private var cachedOpacity: CGFloat = 1
    private var cachedDisplayTime: Double = 8

    init(provider: any DanmakuProviding = DanmakuProvider()) {
        self.provider = provider
        // transport bar 弹幕设置菜单修改后刷新弹幕样式
        NotificationCenter.default.publisher(for: .danmakuSettingsDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.settingsDidChange()
            }
            .store(in: &cancellables)
    }

    // MARK: - 生命周期

    func attach(view: DanmakuView) {
        danmakuView = view
        applySettings()
    }

    func detach() {
        danmakuView = nil
    }

    /// 开始弹幕会话:注册播放器周期回调并预取起始分段
    func start(cid: Int, player: AVPlayer, startTime: TimeInterval) {
        // 先移除旧播放器上的时间观察者,再替换 self.player
        if let timeObserver, let oldPlayer = self.player, oldPlayer !== player {
            oldPlayer.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        self.player = player
        self.cid = cid
        self.lastTickTime = nil
        sessionState = .active

        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }

        let interval = CMTime(seconds: 1, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in
                self?.tick(time: time.seconds)
            }
        }

        Task {
            await provider.initVideo(cid: cid, startPos: startTime)
        }
    }

    func stop() {
        renderGeneration &+= 1
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        player = nil
        cid = nil
        lastTickTime = nil
        sessionState = .idle
        clusterEngine.reset()
        clusterModels.removeAll()
        danmakuView?.stop()
        danmakuView?.clean()
    }

    /// 设置变更后重新应用到 DanmakuView (字号/显示区域)
    func settingsDidChange() {
        applySettings()
    }

    // MARK: - 播放同步

    private func tick(time: TimeInterval) {
        guard cid != nil, let player else { return }

        // 播放/暂停联动:DanmakuView 在非播放状态会丢弃 shoot
        let isPlaying = player.timeControlStatus == .playing && player.rate > 0
        if isPlaying, danmakuView?.status != .play {
            danmakuView?.play()
        } else if !isPlaying, danmakuView?.status == .play {
            danmakuView?.pause()
        }
        guard isPlaying else { return }

        // seek 检测:时间回退或前跳超过 2s 视为拖动进度条,清屏重播
        if let prev = lastTickTime, time < prev - 2 || time > prev + 5 {
            renderGeneration &+= 1
            danmakuView?.clean()
            clusterEngine.reset()
            clusterModels.removeAll()
        }
        lastTickTime = time

        // 串行化:上一次 tick 的异步拉取未完成时跳过本次,避免 provider 游标状态交错
        guard !tickInFlight else { return }
        tickInFlight = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.tickInFlight = false }
            // 挂起期间发生 stop/seek:代际变化,丢弃旧位置的结果
            let generation = self.renderGeneration
            let dms = await self.provider.playerTimeChange(time: time)
            guard generation == self.renderGeneration else { return }
            // 弹幕先经 cluster 引擎聚合:10s 滑动窗口同文本实时合并为静态 cluster
            // (首条滚动即时显示;第 2 条起前置 cluster,计数实时增长)
            let outputs = self.clusterEngine.process(newDanmus: dms, now: time)
            self.apply(outputs)
        }
    }

    private func shoot(_ dm: DanmakuProvider.Danmu) {
        guard let view = danmakuView else { return }
        let model = DanmakuTextCellModel(
            text: dm.text,
            mode: dm.mode,
            color: dm.color,
            fontSize: cachedFontSize,
            displayTime: cachedDisplayTime,
            opacity: cachedOpacity
        )
        view.shoot(danmaku: model)
    }

    /// 分发 cluster 引擎输出:首条滚动 / 前置 cluster / 计数更新 / 窗口封存
    private func apply(_ outputs: [ClusterDanmakuEngine.ClusterOutput]) {
        for output in outputs {
            switch output {
            case .shoot(let danmu):
                shoot(danmu)
            case .showCluster(let cluster):
                showCluster(cluster)
            case .updateCluster(let cluster):
                updateCluster(cluster)
            case .endCluster(let key):
                clusterModels.removeValue(forKey: key)
            }
        }
    }

    /// 前置创建 cluster 弹幕:主文本字号随计数缩放,计数部分固定基础字号,
    /// 轨道类型 .top(水平居中,无滚动动画),displayTime 后淡出消失
    private func showCluster(_ cluster: ClusterDanmakuEngine.ClusterDanmaku) {
        guard let view = danmakuView else { return }
        let model = makeClusterModel(cluster)
        clusterModels[cluster.key] = model
        view.shoot(danmaku: model)
    }

    /// 实时更新已在轨 cluster 的计数与字号(identifier 不变,原位重绘);
    /// 若已在轨 cell 已淡出/被移除(displayTime 到期),重新发射以持续展示刷屏计数
    private func updateCluster(_ cluster: ClusterDanmakuEngine.ClusterDanmaku) {
        guard let view = danmakuView, let model = clusterModels[cluster.key] else { return }
        model.update(
            count: cluster.count,
            fontSize: ClusterFontScaler.fontSize(base: cachedFontSize, count: cluster.count)
        )
        if !view.updateCell(for: model) {
            // 原 cell 不在轨:重新发射(走 .top 轨道,displayTime 重新计时)
            view.shoot(danmaku: model)
        }
    }

    private func makeClusterModel(_ cluster: ClusterDanmakuEngine.ClusterDanmaku) -> DanmakuClusterCellModel {
        DanmakuClusterCellModel(
            text: cluster.text,
            count: cluster.count,
            color: cluster.color,
            fontSize: ClusterFontScaler.fontSize(base: cachedFontSize, count: cluster.count),
            countFontSize: cachedFontSize,
            displayTime: cachedDisplayTime,
            opacity: cachedOpacity
        )
    }

    // MARK: - 设置应用

    private func applySettings() {
        let defaults = UserDefaults.standard
        let fontSize =
            defaults.object(forKey: DanmakuSettingsKeys.fontSize) == nil
            ? DanmakuDefaults.fontSize
            : defaults.double(forKey: DanmakuSettingsKeys.fontSize)
        let opacity =
            defaults.object(forKey: DanmakuSettingsKeys.opacity) == nil
            ? 1.0
            : defaults.double(forKey: DanmakuSettingsKeys.opacity)
        let displayTime =
            defaults.object(forKey: DanmakuSettingsKeys.displayTime) == nil
            ? 8.0
            : defaults.double(forKey: DanmakuSettingsKeys.displayTime)

        cachedFontSize = CGFloat(fontSize)
        cachedOpacity = CGFloat(opacity)
        cachedDisplayTime = displayTime

        guard let view = danmakuView else { return }
        view.trackHeight = cachedFontSize * 1.3
        let area =
            defaults.object(forKey: DanmakuSettingsKeys.displayArea) == nil
            ? 0.75
            : defaults.double(forKey: DanmakuSettingsKeys.displayArea)
        view.displayArea = CGFloat(area)
    }
}
