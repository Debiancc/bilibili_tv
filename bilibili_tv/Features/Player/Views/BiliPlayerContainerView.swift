import AVFoundation
import AVKit
import SwiftUI

/// ▶️ 播放器容器视图（阶段三 3a/3b/3c 瘦身）
///
/// 网络加载 / 状态机 / 进度上报已迁入 PlayerViewModel（3a/3b）；
/// 3c 将弹幕会话协调（danmakuVM/danmakuEnabled）、应用生命周期转发、服务启动收敛入 VM：
/// - 弹幕渲染层显隐由 `viewModel.danmakuSessionActive` 驱动（VM 镜像 danmakuVM.sessionState）
/// - 试看横幅数据在 VM（isPreviewOnly/purchaseHintText），本视图只负责渲染
/// - transport bar 自定义项（弹幕开关/设置/网络诊断）移出本文件，直连 viewModel
struct BiliPlayerContainerView: View {
    let epId: Int?
    let seasonId: Int?
    var title: String?
    var subtitle: String?
    var coverURL: URL?
    /// ▶️ 续播起始时间(秒):>5 时播放器就绪后先 seek 再起播,避免从头闪烁
    var resumeTime: Double = 0

    @State private var viewModel: PlayerViewModel
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
        // 🚀 加载完成后启动进度上报 / 弹幕会话（逻辑收敛在 VM.startPostLoadServices）
        .onChange(of: viewModel.state) { _, newState in
            if newState == .ready {
                viewModel.startPostLoadServices()
            }
        }
        .onDisappear {
            print("🛑 [Player] Dismissing player, tearing down player items & cancelling network streams...")
            // 🧵 SwiftUI 未保证 onDisappear 回调在主线程执行（onChange 也只承诺"可能"在主线程），
            // 用 Task { @MainActor } 包一层比 assumeIsolated 更安全（不会在后台线程触发时崩溃）
            Task { @MainActor in
                viewModel.tearDownPlayer()
            }
        }
        // 🌙 应用生命周期转发（映射为 VM 侧枚举,逻辑全在 VM.handleScenePhaseChange）
        .onChange(of: scenePhase) { _, newPhase in
            Task { @MainActor in
                viewModel.handleScenePhaseChange(newPhase.toAppLifecyclePhase())
            }
        }
    }

    // MARK: - 播放内容层（ready 态）

    private var playerContent: some View {
        Group {
            VideoPlayerViewControllerRepresentable(
                viewModel: viewModel,
                resumeTime: resumeTime
            )
            .ignoresSafeArea()

            // 💬 弹幕渲染层:叠加在视频之上 (allowsHitTesting 穿透遥控器焦点)
            // 显隐由 VM 镜像的 danmakuSessionActive 驱动(弹幕开 + 会话激活 才为 true)
            if viewModel.danmakuSessionActive {
                DanmakuViewWrapper(viewModel: viewModel.danmakuVM)
                    .allowsHitTesting(false)
                    .ignoresSafeArea()
            }

            // 🎬 试看片段提示横幅:数据在 VM,此处只渲染
            if viewModel.isPreviewOnly, let hint = viewModel.purchaseHintText {
                PlayerPreviewBannerView(hint: hint)
            }

            // 📊 统计调试面板小窗 (Stats for nerds, 由 Info 面板"网络诊断"开关控制)
            StatsOverlayView(statsViewModel: viewModel.statsViewModel)
        }
    }
}

/// ScenePhase → VM 侧生命周期枚举的映射（VM 不引入 SwiftUI）
extension ScenePhase {
    fileprivate func toAppLifecyclePhase() -> AppLifecyclePhase {
        switch self {
        case .background: .background
        case .inactive: .inactive
        case .active: .active
        @unknown default: .inactive
        }
    }
}

struct VideoPlayerViewControllerRepresentable: UIViewControllerRepresentable {
    let viewModel: PlayerViewModel
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
        Coordinator(statsViewModel: viewModel.statsViewModel, resumeTime: resumeTime)
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
        controller.player = viewModel.player
        controller.showsPlaybackControls = true

        // ▶️ 续播:先 seek 再 play;普通播放立即起播
        if let player = viewModel.player {
            if context.coordinator.resumeTime > 5 {
                context.coordinator.scheduleResumeSeek(for: player)
            } else {
                player.play()
            }
            viewModel.statsViewModel.startMonitoring(player: player)
        }

        // 💬 弹幕统一入口(右上角按钮行,与字幕/空间音频同排):
        // 一个 UIMenu 按钮,内部包含:弹幕开关 / 弹幕设置 / 网络诊断
        // transportBarCustomMenuItems 是公开 API(tvOS 15+),渲染与焦点完全由 AVKit 管理
        controller.transportBarCustomMenuItems = DanmakuTransportBarItems.makeItems(viewModel: viewModel)
        controller.customInfoViewControllers = []

        // 🚀 阶段2：平稳巡航期 (Steady-State Cruise Phase) -> 4 秒后切回 10 秒缓冲区
        if let playerItem = viewModel.player?.currentItem {
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
