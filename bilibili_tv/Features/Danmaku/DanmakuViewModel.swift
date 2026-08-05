import Foundation
import Combine
import AVFoundation
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

/// 弹幕播放协调器:驱动 DanmakuProvider 数据层与 DanmakuView 渲染,
/// 通过 AVPlayer 周期时间回调同步发射弹幕,并处理 seek/暂停恢复
@MainActor
final class DanmakuViewModel: ObservableObject {
    private let provider = DanmakuProvider()
    private weak var danmakuView: DanmakuView?
    private weak var player: AVPlayer?
    private var timeObserver: Any?
    private var cid: Int?
    private var lastTickTime: TimeInterval?

    var isActive: Bool { cid != nil }

    private var cancellables = Set<AnyCancellable>()

    init() {
        // transport bar 弹幕设置菜单修改后刷新弹幕样式
        NotificationCenter.default.publisher(for: .danmakuSettingsDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.settingsDidChange()
            }
            .store(in: &cancellables)
    }

    deinit {
    }

    /// 弹幕飞行时长(秒):决定滚动速度,时长越长越慢
    private var displayTime: Double {
        let t = UserDefaults.standard.double(forKey: DanmakuSettingsKeys.displayTime)
        return t != 0 ? t : 8.0
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
        self.player = player
        self.cid = cid
        self.lastTickTime = nil

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
        if let prev = lastTickTime, (time < prev - 2 || time > prev + 5) {
            danmakuView?.clean()
        }
        lastTickTime = time

        Task {
            let dms = await provider.playerTimeChange(time: time)
            for dm in dms {
                shoot(dm)
            }
        }
    }

    private func shoot(_ dm: DanmakuProvider.Danmu) {
        guard let view = danmakuView else { return }
        let fontSize = CGFloat(UserDefaults.standard.double(forKey: DanmakuSettingsKeys.fontSize) != 0
            ? UserDefaults.standard.double(forKey: DanmakuSettingsKeys.fontSize)
            : 25)
        let opacity = CGFloat(UserDefaults.standard.double(forKey: DanmakuSettingsKeys.opacity) != 0
            ? UserDefaults.standard.double(forKey: DanmakuSettingsKeys.opacity)
            : 1.0)
        let model = DanmakuTextCellModel(
            text: dm.text,
            mode: dm.mode,
            color: dm.color,
            fontSize: fontSize,
            displayTime: displayTime,
            opacity: opacity
        )
        view.shoot(danmaku: model)
    }

    // MARK: - 设置应用

    private func applySettings() {
        guard let view = danmakuView else { return }
        let defaults = UserDefaults.standard
        let fontSize = defaults.double(forKey: DanmakuSettingsKeys.fontSize) != 0
            ? defaults.double(forKey: DanmakuSettingsKeys.fontSize)
            : 25.0
        view.trackHeight = fontSize * 1.3
        let area = defaults.double(forKey: DanmakuSettingsKeys.displayArea) != 0
            ? defaults.double(forKey: DanmakuSettingsKeys.displayArea)
            : 0.75
        view.displayArea = CGFloat(area)
    }
}
