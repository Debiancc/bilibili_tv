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

    /// 会话生命周期状态:驱动弹幕渲染层显示/隐藏（SwiftUI 经 @Observable 直接跟踪）
    private(set) var sessionState: SessionState = .idle

    enum SessionState {
        case idle
        case active
    }

    // MARK: - 设置缓存 (applySettings 刷新,避免每帧/每弹幕读 UserDefaults)

    private var cachedFontSize: CGFloat = 25
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
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        player = nil
        cid = nil
        lastTickTime = nil
        sessionState = .idle
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
            danmakuView?.clean()
        }
        lastTickTime = time

        // 串行化:上一次 tick 的异步拉取未完成时跳过本次,避免 provider 游标状态交错
        guard !tickInFlight else { return }
        tickInFlight = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.tickInFlight = false }
            let dms = await self.provider.playerTimeChange(time: time)
            for dm in dms {
                self.shoot(dm)
            }
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

    // MARK: - 设置应用

    private func applySettings() {
        let defaults = UserDefaults.standard
        let fontSize =
            defaults.object(forKey: DanmakuSettingsKeys.fontSize) == nil
            ? 25.0
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
