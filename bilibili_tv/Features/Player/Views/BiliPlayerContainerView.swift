import AVFoundation
import AVKit
import SwiftUI

/// ▶️ 播放器容器视图（阶段三 3a 瘦身）
///
/// 网络加载 / 状态机 / 进度上报已迁入 PlayerViewModel：
/// - 加载状态（idle/loading/ready/failed）由 `viewModel.state` 驱动三态渲染
/// - `.task` 触发加载；.ready 后启动进度心跳 / 播完上报 / 弹幕会话
///
/// 仍留在 View 侧（后续子阶段迁移）：
/// - 弹幕会话协调、试看横幅、统计 overlay（3c 迁入 VM）
struct BiliPlayerContainerView: View {
    let epId: Int?
    let seasonId: Int?
    var title: String?
    var subtitle: String?
    var coverURL: URL?
    /// ▶️ 续播起始时间(秒):>5 时播放器就绪后先 seek 再起播,避免从头闪烁
    var resumeTime: Double = 0

    @State private var viewModel: PlayerViewModel
    @StateObject private var danmakuVM = DanmakuViewModel()
    @AppStorage(DanmakuSettingsKeys.isEnabled) private var danmakuEnabled = true
    @Environment(\.scenePhase) private var scenePhase

    init(
        epId: Int?,
        seasonId: Int?,
        title: String? = nil,
        subtitle: String? = nil,
        coverURL: URL? = nil,
        resumeTime: Double = 0,
        viewModel: PlayerViewModel? = nil
    ) {
        self.epId = epId
        self.seasonId = seasonId
        self.title = title
        self.subtitle = subtitle
        self.coverURL = coverURL
        self.resumeTime = resumeTime
        // 🧪 测试入口：注入预置状态的 viewModel（snapshot 测试用），默认自建
        _viewModel = State(
            initialValue: viewModel
                ?? PlayerViewModel(
                    epId: epId,
                    seasonId: seasonId,
                    title: title,
                    subtitle: subtitle,
                    coverURL: coverURL,
                    resumeTime: resumeTime
                ))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch viewModel.state {
            case .idle, .loading:
                PlayerLoadingView()
            case .failed(let message):
                PlayerErrorView(message: message) {
                    Task {
                        await viewModel.loadVideo()
                    }
                }
            case .ready:
                playerContent
            }
        }
        .task {
            await viewModel.loadVideo()
        }
        // 🚀 加载完成后启动进度上报 / 弹幕会话
        .onChange(of: viewModel.state) { _, newState in
            if newState == .ready {
                startPostLoadServices()
            }
        }
        .onDisappear {
            print("🛑 [Player] Dismissing player, tearing down player items & cancelling network streams...")
            // 🧵 SwiftUI 可能在 dealloc 路径(非隔离上下文)调用本闭包,
            // 但主线程执行是保证的,故用 assumeIsolated 满足 Swift 6 隔离检查
            MainActor.assumeIsolated {
                viewModel.stopProgressReporting()
                viewModel.statsViewModel.stopMonitoring()
                danmakuVM.stop()
                viewModel.tearDownPlayer()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background || newPhase == .inactive {
                print("🌙 [Player] App entered background / inactive, reporting progress...")
                // 📡 切后台时上报当前进度并停心跳（前台时恢复）
                MainActor.assumeIsolated {
                    viewModel.stopProgressReporting(reportFinal: true)
                }
            } else if newPhase == .active {
                MainActor.assumeIsolated {
                    viewModel.resumeProgressReportingIfReady()
                }
            }
        }
        // 💬 Info 面板中的弹幕开关同步启停弹幕会话
        .onChange(of: danmakuEnabled) { _, enabled in
            MainActor.assumeIsolated {
                if enabled, let player = viewModel.player, let cid = viewModel.currentCid {
                    danmakuVM.start(cid: cid, player: player, startTime: player.currentTime().seconds)
                } else if !enabled {
                    danmakuVM.stop()
                }
            }
        }
    }

    // MARK: - 播放内容层（ready 态）

    private var playerContent: some View {
        Group {
            VideoPlayerViewControllerRepresentable(
                player: viewModel.player,
                statsViewModel: viewModel.statsViewModel,
                danmakuVM: danmakuVM,
                resumeTime: resumeTime
            )
            .ignoresSafeArea()

            // 💬 弹幕渲染层:叠加在视频之上 (allowsHitTesting 穿透遥控器焦点)
            if danmakuEnabled, danmakuVM.sessionState == .active, viewModel.player != nil {
                DanmakuViewWrapper(viewModel: danmakuVM)
                    .allowsHitTesting(false)
                    .ignoresSafeArea()
            }

            // 🎬 试看片段提示横幅:未购买时仅能看预览,文案按大会员状态区分
            if viewModel.isPreviewOnly, let hint = viewModel.purchaseHintText {
                HStack(spacing: 10) {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("当前为试看片段")
                            .font(.caption)
                            .bold()
                        Text(hint)
                            .font(.caption2)
                            .opacity(0.8)
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.black.opacity(0.65))
                .cornerRadius(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 30)
                .padding(.top, 30)
                .allowsHitTesting(false)
            }

            // 📊 统计调试面板小窗 (Stats for nerds, 由 Info 面板"网络诊断"开关控制)
            StatsOverlayView(statsViewModel: viewModel.statsViewModel)
        }
    }

    // MARK: - 加载完成后的服务启动（进度心跳 / 播完上报 / 弹幕会话）
    // 3a 中 VM 只负责加载；3b 已把进度心跳/播完上报迁入 VM，此处仅剩弹幕协调（3c 迁入）

    private func startPostLoadServices() {
        guard let player = viewModel.player else { return }

        // 📡 进度上报已迁入 VM：startProgressReporting() 启动心跳 + 播完观察者
        viewModel.startProgressReporting()

        // 💬 启动弹幕会话 (cid 由 VM 在加载流程中解析)
        if let cid = viewModel.currentCid {
            print("💬 [Player] Starting danmaku session, cid: \(cid)")
            if danmakuEnabled {
                danmakuVM.start(cid: cid, player: player, startTime: resumeTime)
            }
        }
    }
}
struct VideoPlayerViewControllerRepresentable: UIViewControllerRepresentable {
    let player: AVPlayer?
    let statsViewModel: PlayerStatsViewModel
    let danmakuVM: DanmakuViewModel
    /// ▶️ 续播起始时间(秒),>5 时延迟起播,就绪后先 seek 再 play
    var resumeTime: Double = 0

    @MainActor
    class Coordinator {
        let statsViewModel: PlayerStatsViewModel
        let resumeTime: Double
        /// ▶️ 续播延迟 seek 任务:teardown 时取消,避免播放器关闭后仍 seek/play
        var resumeSeekTask: Task<Void, Never>?

        init(statsViewModel: PlayerStatsViewModel, resumeTime: Double) {
            self.statsViewModel = statsViewModel
            self.resumeTime = resumeTime
        }

        /// ▶️ 等 item 就绪后 seek 到续播点再起播,避免从 0 闪烁
        func scheduleResumeSeek(for player: AVPlayer) {
            guard resumeTime > 5, let item = player.currentItem else { return }
            resumeSeekTask?.cancel()
            resumeSeekTask = Task { [weak player] in
                guard let player else {
                    print("⚠️ [Player] Resume seek skipped, player already released")
                    return
                }
                // 等待 item 变为 readyToPlay (100ms 轮询 + 10s 超时兜底)
                let deadline = Date().addingTimeInterval(10)
                while item.status != .readyToPlay {
                    if Task.isCancelled {
                        print("⚠️ [Player] Resume seek cancelled during readiness wait")
                        return
                    }
                    if item.status == .failed {
                        print("⚠️ [Player] Resume seek aborted, item failed (status=\(item.status.rawValue))")
                        return
                    }
                    if Date() > deadline {
                        // 超时:放弃续播 seek,直接普通起播,避免就绪后仍停在暂停态
                        if !Task.isCancelled {
                            print("⚠️ [Player] Resume readiness timed out, starting normal playback")
                            player.play()
                        }
                        return
                    }
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
                guard !Task.isCancelled else { return }
                let target = CMTime(seconds: resumeTime, preferredTimescale: 600)
                let completed = await item.seek(
                    to: target,
                    toleranceBefore: .zero,
                    toleranceAfter: CMTime(seconds: 0.5, preferredTimescale: 600)
                )
                guard !Task.isCancelled else {
                    print("⚠️ [Player] Resume seek finished after cancellation, skipping play")
                    return
                }
                print("▶️ [Player] Resume seek to \(resumeTime)s completed: \(completed)")
                player.play()
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(statsViewModel: statsViewModel, resumeTime: resumeTime)
    }

    static func dismantleUIViewController(_ uiViewController: AVPlayerViewController, coordinator: Coordinator) {
        coordinator.resumeSeekTask?.cancel()
        coordinator.resumeSeekTask = nil
        uiViewController.player?.pause()
        uiViewController.player = nil
        coordinator.statsViewModel.stopMonitoring()
    }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = true

        // ▶️ 续播:先 seek 再 play;普通播放立即起播
        if let player {
            if context.coordinator.resumeTime > 5 {
                context.coordinator.scheduleResumeSeek(for: player)
            } else {
                player.play()
            }
            statsViewModel.startMonitoring(player: player)
        }

        // 💬 弹幕统一入口(右上角按钮行,与字幕/空间音频同排):
        // 一个 UIMenu 按钮,内部包含:弹幕开关 / 弹幕设置 / 网络诊断
        // transportBarCustomMenuItems 是公开 API(tvOS 15+),渲染与焦点完全由 AVKit 管理
        controller.transportBarCustomMenuItems = DanmakuTransportBarItems.makeItems(
            statsViewModel: statsViewModel
        )
        controller.customInfoViewControllers = []

        // 🚀 阶段2：平稳巡航期 (Steady-State Cruise Phase) -> 4 秒后切回 10 秒缓冲区
        if let playerItem = player?.currentItem {
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                playerItem.preferredForwardBufferDuration = 10.0
                print("⚓️ [Player] Transitioned to steady-state buffer target (10.0s)")
            }
        }

        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
    }
}

// MARK: - 💬 AVKit transport bar 自定义项(与字幕/空间音频同排)
// 使用公开 API AVPlayerViewController.transportBarCustomMenuItems (tvOS 15+):
// UIAction 渲染为按钮行图标按钮(弹幕开关),UIMenu 渲染为带子菜单的按钮(弹幕设置)。
// 状态写入 UserDefaults(@AppStorage 同 key),由 BiliPlayerContainerView 的 onChange 自动启停弹幕会话。

enum DanmakuTransportBarItems {
    @MainActor
    static func makeItems(statsViewModel: PlayerStatsViewModel) -> [UIMenuElement] {
        let onImage = UIImage(systemName: "list.bullet.rectangle.fill")
        let offImage = UIImage(systemName: "list.bullet.rectangle")

        // 💬 弹幕开关:点击切换 UserDefaults -> @AppStorage -> onChange 启停弹幕
        let isOn =
            UserDefaults.standard.object(forKey: DanmakuSettingsKeys.isEnabled) == nil
            || UserDefaults.standard.bool(forKey: DanmakuSettingsKeys.isEnabled)
        let toggleAction = UIAction(title: "显示弹幕", image: isOn ? onImage : offImage, state: isOn ? .on : .off) { action in
            let enabled =
                !(UserDefaults.standard.object(forKey: DanmakuSettingsKeys.isEnabled) == nil
                || UserDefaults.standard.bool(forKey: DanmakuSettingsKeys.isEnabled))
            UserDefaults.standard.set(enabled, forKey: DanmakuSettingsKeys.isEnabled)
            action.image = enabled ? onImage : offImage
            action.state = enabled ? .on : .off
            print("💬 [Player] Danmaku toggled via transport bar: \(enabled)")
        }

        // ⚙️ 弹幕设置子菜单
        let settingsMenu = UIMenu(
            title: "弹幕设置",
            image: UIImage(systemName: "gearshape"),
            children: [
                durationMenu(),
                opacityMenu(),
                fontSizeMenu(),
                displayAreaMenu()
            ]
        )

        // 📊 网络诊断开关:控制 StatsOverlayView 小窗显示
        let statsAction = UIAction(
            title: "网络诊断",
            image: UIImage(systemName: statsViewModel.isVisible ? "chart.bar.fill" : "chart.bar"),
            state: statsViewModel.isVisible ? .on : .off
        ) { action in
            statsViewModel.isVisible.toggle()
            action.image = UIImage(systemName: statsViewModel.isVisible ? "chart.bar.fill" : "chart.bar")
            action.state = statsViewModel.isVisible ? .on : .off
            print("📊 [Player] Stats overlay toggled via transport bar: \(statsViewModel.isVisible)")
        }

        // 🎯 统一入口:一个弹幕控制菜单,内含开关 + 设置 + 网络诊断
        let danmakuMenu = UIMenu(
            title: "弹幕控制",
            image: isOn ? onImage : offImage,
            children: [toggleAction, settingsMenu, statsAction]
        )
        return [danmakuMenu]
    }

    private static func doubleValue(_ key: String, default def: Double) -> Double {
        let d = UserDefaults.standard
        return d.object(forKey: key) == nil ? def : d.double(forKey: key)
    }

    @MainActor
    private static func durationMenu() -> UIMenu {
        let current = doubleValue(DanmakuSettingsKeys.displayTime, default: 8.0)
        return UIMenu(
            title: "弹幕展示时长",
            options: [.displayInline, .singleSelection],
            children: [4, 6, 8].map { dur in
                UIAction(title: "\(dur) 秒", state: dur == Int(current) ? .on : .off) { _ in
                    UserDefaults.standard.set(Double(dur), forKey: DanmakuSettingsKeys.displayTime)
                    danmakuSettingsDidChange()
                }
            }
        )
    }

    /// 弹幕透明度:50% / 75% / 100%
    @MainActor
    private static func opacityMenu() -> UIMenu {
        let current = doubleValue(DanmakuSettingsKeys.opacity, default: 1.0)
        return UIMenu(
            title: "透明度",
            options: [.displayInline, .singleSelection],
            children: [0.5, 0.75, 1.0].map { value in
                UIAction(title: "\(Int(value * 100))%", state: value == current ? .on : .off) { _ in
                    UserDefaults.standard.set(value, forKey: DanmakuSettingsKeys.opacity)
                    danmakuSettingsDidChange()
                }
            }
        )
    }

    /// 弹幕字号
    @MainActor
    private static func fontSizeMenu() -> UIMenu {
        let current = doubleValue(DanmakuSettingsKeys.fontSize, default: 25.0)
        return UIMenu(
            title: "字号",
            options: [.displayInline, .singleSelection],
            children: [25.0, 33.0, 41.0, 49.0, 57.0].map { value in
                UIAction(title: "\(Int(value))", state: value == current ? .on : .off) { _ in
                    UserDefaults.standard.set(value, forKey: DanmakuSettingsKeys.fontSize)
                    danmakuSettingsDidChange()
                }
            }
        )
    }

    /// 弹幕显示区域:全屏 3/4 / 半屏 1/2 / 小区域 1/4
    @MainActor
    private static func displayAreaMenu() -> UIMenu {
        let current = doubleValue(DanmakuSettingsKeys.displayArea, default: 0.75)
        let options: [(value: Double, title: String)] = [
            (0.75, "全屏 (3/4)"),
            (0.5, "半屏 (1/2)"),
            (0.25, "小区域 (1/4)")
        ]
        return UIMenu(
            title: "显示区域",
            options: [.displayInline, .singleSelection],
            children: options.map { option in
                UIAction(title: option.title, state: option.value == current ? .on : .off) { _ in
                    UserDefaults.standard.set(option.value, forKey: DanmakuSettingsKeys.displayArea)
                    danmakuSettingsDidChange()
                }
            }
        )
    }

    /// 设置变化后通知 DanmakuViewModel 刷新弹幕样式
    private static func danmakuSettingsDidChange() {
        NotificationCenter.default.post(name: .danmakuSettingsDidChange, object: nil)
    }
}

extension Notification.Name {
    /// 弹幕设置变化(transport bar 菜单修改后通知 DanmakuViewModel 刷新)
    static let danmakuSettingsDidChange = Notification.Name("danmakuSettingsDidChange")
}
