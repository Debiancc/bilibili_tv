import SwiftUI
import AVKit
import AVFoundation

struct BiliPlayerContainerView: View {
    let epId: Int?
    let seasonId: Int?
    var title: String? = nil
    var subtitle: String? = nil
    var coverURL: URL? = nil
    
    @State private var statsViewModel = PlayerStatsViewModel()
    @State private var finalPlayerItem: AVPlayerItem?
    @State private var hlsLoader: BiliHLSResourceLoader?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            
            if isLoading {
                VStack(spacing: 20) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("正在自适应加载高清视频流...")
                        .font(.headline)
                        .foregroundColor(.white.opacity(0.8))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                VStack(spacing: 20) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.yellow)
                    Text("视频加载失败")
                        .font(.title2)
                        .foregroundColor(.white)
                    Text(error)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Button("重新加载") {
                        Task {
                            await loadVideo()
                        }
                    }
                    .buttonStyle(.card)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let item = finalPlayerItem {
                VideoPlayerViewControllerRepresentable(playerItem: item)
                    .ignoresSafeArea()
                
                // 📊 统计调试面板小窗 (Stats for nerds)
                StatsOverlayView(statsViewModel: statsViewModel)
                
                // 顶部控制辅助栏
                HStack {
                    Button(action: {
                        statsViewModel.isVisible.toggle()
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "chart.bar.xaxis")
                            Text(statsViewModel.isVisible ? "隐藏码率统计" : "显示码率统计 (Stats)")
                        }
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(8)
                    }
                    .buttonStyle(.card)
                    
                    Spacer()
                }
                .padding(30)
            }
        }
        .task {
            await loadVideo()
        }
        .onDisappear {
            print("🛑 [Player] Dismissing player, tearing down player items & cancelling network streams...")
            statsViewModel.stopMonitoring()
            finalPlayerItem?.cancelPendingSeeks()
            finalPlayerItem?.asset.cancelLoading()
            finalPlayerItem = nil
            hlsLoader = nil
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .background || newPhase == .inactive {
                print("🌙 [Player] App entered background / inactive...")
            }
        }
    }
    
    private func loadVideo() async {
        isLoading = true
        errorMessage = nil
        
        do {
            guard epId != nil || seasonId != nil else {
                throw NSError(domain: "PlayerError", code: -3,
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
               let videoURL = URL(string: videoUrlString) {
                
                print("🌟 [Player] Selected video: \(bestVideo.width ?? 0)x\(bestVideo.height ?? 0) @ \(bestVideo.bandwidth ?? 0) bps, codecs: \(bestVideo.codecs ?? "")")
                
                let bestAudio = playResult.bestAudioTrack
                let audioURL = (bestAudio?.baseUrl).flatMap { URL(string: $0) }
                
                let durationSeconds: Double
                if let ms = playResult.timelength, ms > 0 {
                    durationSeconds = Double(ms) / 1000.0
                } else {
                    durationSeconds = 7200.0
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
                
                var metadata: [AVMetadataItem] = []
                if let title = title {
                    let titleItem = AVMutableMetadataItem()
                    titleItem.identifier = .commonIdentifierTitle
                    titleItem.value = title as NSString
                    titleItem.extendedLanguageTag = "und"
                    metadata.append(titleItem)
                }
                
                if let subtitle = subtitle {
                    let subtitleItem = AVMutableMetadataItem()
                    subtitleItem.identifier = .commonIdentifierDescription
                    subtitleItem.value = subtitle as NSString
                    subtitleItem.extendedLanguageTag = "und"
                    metadata.append(subtitleItem)
                }
                
                item.externalMetadata = metadata

                // 🚀 阶段1：起播极速冲刺期 (Initial Burst Phase) -> 设为 25 秒缓冲区
                item.preferredForwardBufferDuration = 25.0
                playerItem = item

                // Fetch artwork asynchronously after player item is assigned
                if let coverURL = coverURL {
                    Task {
                        do {
                            let (imageData, _) = try await withTimeout(seconds: 3.0) {
                                try await URLSession.shared.data(from: coverURL)
                            }
                            let artworkItem = AVMutableMetadataItem()
                            artworkItem.identifier = .commonIdentifierArtwork
                            artworkItem.value = imageData as NSData
                            artworkItem.dataType = kCMMetadataBaseDataType_RawData as String

                            var updatedMetadata = metadata
                            updatedMetadata.append(artworkItem)
                            item.externalMetadata = updatedMetadata
                        } catch {
                            print("⚠️ [Player] Failed to fetch artwork: \(error)")
                        }
                    }
                }
                self.statsViewModel.updateStreamInfo(videoTrack: bestVideo, audioTrack: bestAudio)
                print("✅ [Player] HLS M3U8 Asset ready (duration: \(durationSeconds)s), starting playback...")
            }
            
//            // 🌟 方案 B：MP4 / FLV 整段流降级
//            if finalPlayerItem == nil, let durlSegments = playResult.durl, !durlSegments.isEmpty {
//                let mp4Options: [String: Any] = ["AVURLAssetHTTPHeaderFieldsKey": headers]
//                
//                if durlSegments.count == 1,
//                   let singleUrlString = durlSegments.first?.url,
//                   let singleURL = URL(string: singleUrlString) {
//                    print("🎬 [Player] Playing single MP4 stream...")
//                    let asset = AVURLAsset(url: singleURL, options: mp4Options)
//                    // 验证可达性
//                    _ = try await asset.loadTracks(withMediaType: .video)
//                    finalPlayerItem = AVPlayerItem(asset: asset)
//                    self.statsViewModel.containerFormat = "Single MP4"
//                } else {
//                    print("🧩 [Player] Aggregating \(durlSegments.count) MP4 segments...")
//                    let composition = AVMutableComposition()
//                    guard let compVideoTrack = composition.addMutableTrack(withMediaType: .video,
//                                                                            preferredTrackID: kCMPersistentTrackID_Invalid),
//                          let compAudioTrack = composition.addMutableTrack(withMediaType: .audio,
//                                                                            preferredTrackID: kCMPersistentTrackID_Invalid) else {
//                        throw NSError(domain: "PlayerError", code: -2,
//                                      userInfo: [NSLocalizedDescriptionKey: "无法创建合成轨道"])
//                    }
//                    
//                    var insertionPoint = CMTime.zero
//                    for segment in durlSegments {
//                        guard let urlString = segment.url, let segmentURL = URL(string: urlString) else { continue }
//                        let segmentAsset = AVURLAsset(url: segmentURL, options: mp4Options)
//                        async let vTracks = segmentAsset.loadTracks(withMediaType: .video)
//                        async let aTracks = segmentAsset.loadTracks(withMediaType: .audio)
//                        async let dur = segmentAsset.load(.duration)
//                        let (svTracks, saTracks, duration) = try await (vTracks, aTracks, dur)
//                        let timeRange = CMTimeRange(start: .zero, duration: duration)
//                        if let vt = svTracks.first { try compVideoTrack.insertTimeRange(timeRange, of: vt, at: insertionPoint) }
//                        if let at = saTracks.first { try compAudioTrack.insertTimeRange(timeRange, of: at, at: insertionPoint) }
//                        insertionPoint = CMTimeAdd(insertionPoint, duration)
//                    }
//                    finalPlayerItem = AVPlayerItem(asset: composition)
//                    self.statsViewModel.containerFormat = "Multi MP4"
//                }
//            }

            guard playerItem != nil else {
                throw NSError(domain: "PlayerError", code: -1,
                              userInfo: [NSLocalizedDescriptionKey: "无法解析播放流（可能需要大会员或 CDN 鉴权失败）"])
            }

            self.finalPlayerItem = playerItem
            isLoading = false
            
        } catch {
            print("❌ [Player] Load error: \(error)")
            self.errorMessage = error.localizedDescription
            isLoading = false
        }
    }
}

// 封装 AVPlayerViewController 供 tvOS 原生 UI 播放控制
struct VideoPlayerViewControllerRepresentable: UIViewControllerRepresentable {
    let playerItem: AVPlayerItem
    
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let player = AVPlayer(playerItem: playerItem)
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = true
        player.play()
        
        // 🚀 阶段2：平稳巡航期 (Steady-State Cruise Phase) -> 4 秒后切回 10 秒缓冲区
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            playerItem.preferredForwardBufferDuration = 10.0
            print("⚓️ [Player] Transitioned to steady-state buffer target (10.0s)")
        }
        
        return controller
    }
    
    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
    }
    
    static func dismantleUIViewController(_ uiViewController: AVPlayerViewController, coordinator: ()) {
        uiViewController.player?.pause()
        uiViewController.player = nil
    }
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
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}

