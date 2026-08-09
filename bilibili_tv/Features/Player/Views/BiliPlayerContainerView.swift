import AVFoundation
import AVKit
import SwiftUI

struct BiliPlayerContainerView: View {
    let epId: Int?
    let seasonId: Int?
    var title: String?
    var subtitle: String?
    var coverURL: URL?
    /// ▶️ 续播起始时间(秒):>5 时播放器就绪后先 seek 再起播,避免从头闪烁
    var resumeTime: Double = 0

    @State private var statsViewModel = PlayerStatsViewModel()
    @StateObject private var danmakuVM = DanmakuViewModel()
    @State private var finalPlayerItem: AVPlayerItem?
    @State private var player: AVPlayer?
    @State private var hlsLoader: BiliHLSResourceLoader?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isPreviewOnly = false
    @State private var purchaseHintText: String?
    @State private var currentCid: Int?
    @State private var progressReporterTimer: Timer?
    @State private var lastReportedProgress: Int = 0
    @State private var playbackEndObserver: NSObjectProtocol?
    @AppStorage(DanmakuSettingsKeys.isEnabled) private var danmakuEnabled = true
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if isLoading {
                VStack(spacing: 20) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("正在自适应加载高清视频流...")
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.8))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                VStack(spacing: 20) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 50))
                        .foregroundStyle(.yellow)
                    Text("视频加载失败")
                        .font(.title2)
                        .foregroundStyle(.white)
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("重新加载") {
                        Task {
                            await loadVideo()
                        }
                    }
                    .buttonStyle(.glass)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if finalPlayerItem != nil {
                VideoPlayerViewControllerRepresentable(player: player, statsViewModel: statsViewModel, danmakuVM: danmakuVM, resumeTime: resumeTime)
                    .ignoresSafeArea()

                // 💬 弹幕渲染层:叠加在视频之上 (allowsHitTesting 穿透遥控器焦点)
                if danmakuEnabled, danmakuVM.sessionState == .active, player != nil {
                    DanmakuViewWrapper(viewModel: danmakuVM)
                        .allowsHitTesting(false)
                        .ignoresSafeArea()
                }

                // 🎬 试看片段提示横幅:未购买时仅能看预览,文案按大会员状态区分
                if isPreviewOnly, let hint = purchaseHintText {
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
                StatsOverlayView(statsViewModel: statsViewModel)
                //                .padding(0)
            }
        }
        .task {
            await loadVideo()
        }
        .onDisappear {
            print("🛑 [Player] Dismissing player, tearing down player items & cancelling network streams...")
            // 📡 退出前上报最终进度
            progressReporterTimer?.invalidate()
            progressReporterTimer = nil
            if let playbackEndObserver {
                NotificationCenter.default.removeObserver(playbackEndObserver)
            }
            playbackEndObserver = nil
            reportProgress(force: true)
            statsViewModel.stopMonitoring()
            danmakuVM.stop()
            finalPlayerItem?.cancelPendingSeeks()
            finalPlayerItem?.asset.cancelLoading()
            finalPlayerItem = nil
            player = nil
            hlsLoader = nil
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background || newPhase == .inactive {
                print("🌙 [Player] App entered background / inactive, reporting progress...")
                // 📡 切后台时上报当前进度
                reportProgress(force: true)
            }
        }
        // 💬 Info 面板中的弹幕开关同步启停弹幕会话
        .onChange(of: danmakuEnabled) { _, enabled in
            if enabled, let player, let cid = currentCid {
                danmakuVM.start(cid: cid, player: player, startTime: player.currentTime().seconds)
            } else if !enabled {
                danmakuVM.stop()
            }
        }
    }

    // TODO: 拆分 loadVideo 为职责单一的加载/降级/起播方法
    // swiftlint:disable:next function_body_length cyclomatic_complexity
    private func loadVideo() async {
        isLoading = true
        errorMessage = nil

        do {
            guard epId != nil || seasonId != nil else {
                throw NSError(
                    domain: "PlayerError", code: -3,
                    userInfo: [NSLocalizedDescriptionKey: "缺少剧集或季度 ID，无法播放"])
            }
            print("🚀 [Player] Resolving adaptive streams for epId: \(epId ?? 0)...")

            let requestedQn = 120
            var playResult: PlayURLResult
            do {
                playResult = try await BilibiliService.shared.fetchPlayURL(epId: epId, cid: nil, seasonId: seasonId, qn: requestedQn)
            } catch is CancellationError {
                return
            } catch {
                print("⚠️ [Player] qn=\(requestedQn) failed, trying qn=80 (1080P)...")
                playResult = try await BilibiliService.shared.fetchPlayURL(epId: epId, cid: nil, seasonId: seasonId, qn: 80)
            }

            // 🎬 检测试看状态:未购买时仅返回试看片段,播放器叠加提示横幅
            isPreviewOnly = playResult.isPreviewOnly
            purchaseHintText = playResult.purchaseHintText
            if isPreviewOnly {
                // swiftlint:disable line_length
                print(
                    "🔒 [Player] Preview-only stream detected (is_preview=\(playResult.isPreview ?? -1), has_paid=\(playResult.hasPaid.map(String.init) ?? "nil"), error_code=\(playResult.errorCode ?? 0), vip_status=\(playResult.vipStatus ?? 0)), hint: \(purchaseHintText ?? "nil")"
                )
                // swiftlint:enable line_length
            }

            let headers: [String: String] = [
                "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/146.0.0.0 Safari/537.36",
                "Referer": "https://www.bilibili.com/",
                "Origin": "https://www.bilibili.com",
                "Cookie": BilibiliNetworkConfig.shared.cookie
            ]

            var playerItem: AVPlayerItem?

            // 🌟 方案 A: DASH 流 (通过动态 HLS M3U8 生成器 + ResourceLoader)
            if let bestVideo = playResult.bestVideoTrack(maxQn: requestedQn),
                let videoUrlString = bestVideo.baseUrl,
                let videoURL = URL(string: videoUrlString)
            {
                print(
                    // swiftlint:disable:next line_length
                    "🌟 [Player] Selected video: \(bestVideo.width ?? 0)x\(bestVideo.height ?? 0) @ \(bestVideo.bandwidth ?? 0) bps, codecs: \(bestVideo.codecs ?? "")"
                )

                let bestAudio = playResult.bestAudioTrack
                let audioURL = (bestAudio?.baseUrl).flatMap { URL(string: $0) }

                let durationSeconds: Double
                if let ms = playResult.timelength, ms > 0 {
                    durationSeconds = Double(ms) / 1_000.0
                } else {
                    durationSeconds = 7_200.0
                }

                let loader = BiliHLSResourceLoader(
                    videoURL: videoURL,
                    audioURL: audioURL,
                    duration: durationSeconds,
                    videoTrack: bestVideo,
                    audioTrack: bestAudio,
                    headers: headers
                )
                self.hlsLoader = loader

                // ⚡️ 关键：在创建 AVURLAsset 之前先解析 sidx
                // 让 sidx 精确分片字节表在播放器请求 M3U8 前就已经准备好
                print("🔍 [Player] Pre-fetching sidx segment index...")
                await loader.prefetchSidx()
                print("✅ [Player] sidx pre-fetched: \(loader.videoSidxEntries.count) video, \(loader.audioSidxEntries.count) audio segments")

                guard let masterURL = URL(string: "bili-hls://localhost/master.m3u8") else {
                    throw NSError(domain: "PlayerError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid HLS Master URL"])
                }

                let options: [String: Any] = ["AVURLAssetHTTPHeaderFieldsKey": headers]
                let asset = AVURLAsset(url: masterURL, options: options)

                // ✅ 使用与 URLSession delegate 相同的串行队列，彻底消除竞态
                asset.resourceLoader.setDelegate(loader, queue: loader.resourceQueue)

                let item = AVPlayerItem(asset: asset)

                // 🏷️ 设置 externalMetadata (标题/副标题 + 异步封面),与 MP4 降级路径共用
                applyMetadata(to: item, coverURL: coverURL)

                // 🚀 阶段1：起播极速冲刺期 (Initial Burst Phase) -> 设为 25 秒缓冲区
                item.preferredForwardBufferDuration = 25.0
                playerItem = item

                self.statsViewModel.updateStreamInfo(videoTrack: bestVideo, audioTrack: bestAudio)
                print("✅ [Player] HLS M3U8 Asset ready (duration: \(durationSeconds)s), starting playback...")
            }

            // 🌟 方案 B：MP4 / FLV 整段流降级 (针对无 DASH、仅返回 durl 的试看/普通流)
            if playerItem == nil, let durlSegments = playResult.durl, !durlSegments.isEmpty {
                let mp4Options: [String: Any] = ["AVURLAssetHTTPHeaderFieldsKey": headers]

                if durlSegments.count == 1,
                    let singleUrlString = durlSegments.first?.url,
                    let singleURL = URL(string: singleUrlString)
                {
                    print("🎬 [Player] Playing single MP4 stream...")
                    let asset = AVURLAsset(url: singleURL, options: mp4Options)
                    // 验证可达性
                    _ = try await asset.loadTracks(withMediaType: .video)
                    let item = AVPlayerItem(asset: asset)
                    // 🏷️ MP4 降级路径同样设置 externalMetadata (标题/副标题 + 异步封面)
                    applyMetadata(to: item, coverURL: coverURL)
                    playerItem = item
                    self.statsViewModel.containerFormat = "Single MP4"
                } else {
                    print("🧩 [Player] Aggregating \(durlSegments.count) MP4 segments...")
                    let composition = AVMutableComposition()
                    guard
                        let compVideoTrack = composition.addMutableTrack(
                            withMediaType: .video,
                            preferredTrackID: kCMPersistentTrackID_Invalid),
                        let compAudioTrack = composition.addMutableTrack(
                            withMediaType: .audio,
                            preferredTrackID: kCMPersistentTrackID_Invalid)
                    else {
                        throw NSError(
                            domain: "PlayerError", code: -2,
                            userInfo: [NSLocalizedDescriptionKey: "无法创建合成轨道"])
                    }

                    var insertionPoint = CMTime.zero
                    for segment in durlSegments {
                        guard let urlString = segment.url, let segmentURL = URL(string: urlString) else { continue }
                        let segmentAsset = AVURLAsset(url: segmentURL, options: mp4Options)
                        async let vTracks = segmentAsset.loadTracks(withMediaType: .video)
                        async let aTracks = segmentAsset.loadTracks(withMediaType: .audio)
                        async let dur = segmentAsset.load(.duration)
                        let (svTracks, saTracks, duration) = try await (vTracks, aTracks, dur)
                        let timeRange = CMTimeRange(start: .zero, duration: duration)
                        if let vt = svTracks.first { try compVideoTrack.insertTimeRange(timeRange, of: vt, at: insertionPoint) }
                        if let at = saTracks.first { try compAudioTrack.insertTimeRange(timeRange, of: at, at: insertionPoint) }
                        insertionPoint = CMTimeAdd(insertionPoint, duration)
                    }
                    let item = AVPlayerItem(asset: composition)
                    // 🏷️ MP4 降级路径同样设置 externalMetadata (标题/副标题 + 异步封面)
                    applyMetadata(to: item, coverURL: coverURL)
                    playerItem = item
                    self.statsViewModel.containerFormat = "Multi MP4"
                }
            }

            guard playerItem != nil else {
                throw NSError(
                    domain: "PlayerError", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "无法解析播放流（可能需要大会员或 CDN 鉴权失败）"])
            }

            self.finalPlayerItem = playerItem
            let avPlayer = AVPlayer(playerItem: playerItem)
            self.player = avPlayer

            // 📡 进度上报:每 30s 心跳 + 播完上报 duration 标记看完
            progressReporterTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { _ in
                Task { @MainActor in
                    self.reportProgress(force: false)
                }
            }
            playbackEndObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: playerItem,
                queue: .main
            ) { _ in
                Task { @MainActor in
                    self.reportProgress(force: true, completed: true)
                }
            }

            // 💬 启动弹幕会话 (cid 取自 playurl 响应,用于 seg.so 弹幕接口)
            if let cid = playResult.cid {
                currentCid = cid
                print("💬 [Player] Starting danmaku session, cid: \(cid)")
                if danmakuEnabled {
                    danmakuVM.start(cid: cid, player: avPlayer, startTime: resumeTime)
                }
            } else if let epId = epId {
                // 🔄 playurl 响应无 cid 字段,从 season detail / ep 详情兜底
                do {
                    let cid = try await BilibiliService.shared.fetchEpisodeCid(epId: epId, seasonId: seasonId)
                    if let cid {
                        currentCid = cid
                        print("💬 [Player] cid resolved via fallback: \(cid)")
                        if danmakuEnabled {
                            danmakuVM.start(cid: cid, player: avPlayer, startTime: resumeTime)
                        }
                    } else {
                        print("⚠️ [Player] fetchEpisodeCid returned nil (epId: \(epId), seasonId: \(seasonId ?? -1))")
                    }
                } catch {
                    print("❌ [Player] fetchEpisodeCid failed: \(error) (epId: \(epId), seasonId: \(seasonId ?? -1))")
                }
            } else {
                print("⚠️ [Player] No cid available, danmaku disabled")
            }

            isLoading = false
        } catch {
            print("❌ [Player] Load error: \(error)")
            self.errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    /// 📡 上报当前观看进度 (默认 30s 节流;force 跳过;completed 表示该集播完,以 duration 标记看完)
    /// 数据源 = 本地播放记录 (LocalWatchHistoryStore);
    /// 远程上报 API (BilibiliService.reportWatchProgress, 需真实 aid 方能写入服务端历史) 为预留, 暂未接入
    private func reportProgress(force: Bool, completed: Bool = false) {
        let seconds: Double
        if completed, let duration = finalPlayerItem?.duration.seconds, duration.isFinite, duration > 0 {
            seconds = duration
        } else {
            seconds = player?.currentTime().seconds ?? 0
        }
        let t = Int(seconds)
        guard t > 0 else { return }
        if !force && abs(t - lastReportedProgress) < 30 { return }
        lastReportedProgress = t

        let duration = finalPlayerItem?.duration.seconds ?? 0
        let itemDuration = duration.isFinite && duration > 0 ? Int(duration) : 0
        LocalWatchHistoryStore.shared.record(
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
        // TODO: 预留远程上报: BilibiliService.shared.reportWatchProgress(epId:seasonId:cid:playedTime:)
        // 接入前提: 从 pgc/view/web/season 解析该集真实 aid (aid=0 时服务端静默丢弃, 不写入历史)
    }

    /// 🏷️ 设置 AVPlayerItem 的 externalMetadata (标题/副标题),并异步加载封面 artwork
    /// 方案 A (DASH/HLS) 与方案 B (MP4/durl 降级) 共用,保证所有播放路径的 Info 面板都有内容
    private func applyMetadata(to item: AVPlayerItem, coverURL: URL?) {
        print("🔍 [Player] applyMetadata: title=\(title ?? "nil"), subtitle=\(subtitle ?? "nil"), coverURL=\(coverURL?.absoluteString ?? "nil")")
        var metadata: [AVMetadataItem] = []

        // ⚠️ tvOS Info 面板显示三要素 (踩坑记录):
        // 1. 每项必须设置 locale,否则 Info 面板完全不渲染
        // 2. description 为 nil/空字符串时,海报会被隐藏 (tvOS 已知 bug),需用 " " 占位
        // 3. artwork 必须设置 dataType (PNG/JPEG),否则海报不显示
        if let title = title {
            let titleItem = AVMutableMetadataItem()
            titleItem.identifier = .commonIdentifierTitle
            titleItem.value = title as NSString
            titleItem.extendedLanguageTag = "und"
            titleItem.locale = Locale.current
            metadata.append(titleItem)
        }

        // description 恒有值:subtitle 为空时用单个空格占位,避免海报被隐藏
        let subtitleText = (subtitle ?? "").isEmpty ? " " : subtitle ?? ""
        let subtitleItem = AVMutableMetadataItem()
        subtitleItem.identifier = .commonIdentifierDescription
        subtitleItem.value = subtitleText as NSString
        subtitleItem.extendedLanguageTag = "und"
        subtitleItem.locale = Locale.current
        metadata.append(subtitleItem)

        item.externalMetadata = metadata
        print("🔍 [Player] externalMetadata set with \(metadata.count) items")

        // 异步加载封面 artwork (Info 面板的海报)
        guard let coverURL else { return }
        Task {
            do {
                let (imageData, _) = try await withTimeout(seconds: 3.0) {
                    try await URLSession.shared.data(from: coverURL)
                }
                let artworkItem = AVMutableMetadataItem()
                artworkItem.identifier = .commonIdentifierArtwork
                artworkItem.value = imageData as NSData
                artworkItem.extendedLanguageTag = "und"
                artworkItem.locale = Locale.current
                // 根据图片魔数设置 dataType,否则 tvOS 不渲染海报
                let isPNG = imageData.count > 8 && imageData.prefix(8) == Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
                artworkItem.dataType = isPNG ? (kCMMetadataBaseDataType_PNG as String) : (kCMMetadataBaseDataType_JPEG as String)

                var updatedMetadata = metadata
                updatedMetadata.append(artworkItem)
                item.externalMetadata = updatedMetadata
            } catch {
                print("⚠️ [Player] Failed to fetch artwork: \(error)")
            }
        }
    }
}

// 封装 AVPlayerViewController 供 tvOS 原生 UI 播放控制
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

// Helper function to add timeout to async operations
private func withTimeout<T: Sendable>(seconds: TimeInterval, operation: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw NSError(domain: "TimeoutError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Operation timed out"])
        }
        let result =
            try await group.next() ?? { throw NSError(domain: "TimeoutError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Operation timed out"]) }()
        group.cancelAll()
        return result
    }
}
