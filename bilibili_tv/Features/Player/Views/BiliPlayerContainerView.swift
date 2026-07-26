import SwiftUI
import AVKit
import Combine

struct BiliPlayerContainerView: View {
    let item: FeedItem
    
    @State private var statsViewModel = PlayerStatsViewModel()
    @State private var player: AVPlayer?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var resourceLoader: BiliResourceLoader?
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
                        .font(.system(size: 70))
                        .foregroundColor(.orange)
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
            } else if let player = player {
                // 原生 tvOS AVPlayer 视图
                VideoPlayerViewControllerRepresentable(player: player)
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
            player?.pause()
            player?.currentItem?.cancelPendingSeeks()
            player?.currentItem?.asset.cancelLoading()
            player?.replaceCurrentItem(with: nil)
            player = nil
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .background || newPhase == .inactive {
                print("🌙 [Player] App entered background / inactive, pausing video playback...")
                player?.pause()
            }
        }
    }
    
    private func loadVideo() async {
        isLoading = true
        errorMessage = nil
        
        do {
            print("🚀 [Player] Resolving adaptive streams for epId: \(item.episodeId ?? 0)...")
            
            let requestedQn = 120
            var playResult: PlayURLResult
            do {
                playResult = try await BilibiliService.shared.fetchPlayURL(epId: item.episodeId, cid: nil, qn: requestedQn)
            } catch {
                print("⚠️ [Player] qn=\(requestedQn) failed, trying qn=80 (1080P)...")
                playResult = try await BilibiliService.shared.fetchPlayURL(epId: item.episodeId, cid: nil, qn: 80)
            }
            
            let headers: [String: String] = [
                "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/146.0.0.0 Safari/537.36",
                "Referer": "https://www.bilibili.com/",
                "Origin": "https://www.bilibili.com",
                "Cookie": BilibiliNetworkConfig.shared.cookie
            ]
            
            var finalPlayerItem: AVPlayerItem?
            
            // 🌟 方案 A: DASH 流
            if let bestVideo = playResult.bestVideoTrack(maxQn: requestedQn),
               let videoUrlString = bestVideo.baseUrl,
               let videoURL = URL(string: videoUrlString) {
                
                print("🌟 [Player] Selected video: \(bestVideo.width ?? 0)x\(bestVideo.height ?? 0) @ \(bestVideo.bandwidth ?? 0) bps, codecs: \(bestVideo.codecs ?? "")")
                
                let bestAudio = playResult.bestAudioTrack
                let audioURL = (bestAudio?.baseUrl).flatMap { URL(string: $0) }
                
                // 初始化代理并保存以防释放
                let loader = BiliResourceLoader(videoURL: videoURL, audioURL: audioURL, headers: headers)
                self.resourceLoader = loader
                
                var vComp = URLComponents(url: videoURL, resolvingAgainstBaseURL: false)!
                vComp.scheme = "bili-video"
                let customVideoURL = vComp.url!
                
                let videoAsset = AVURLAsset(url: customVideoURL)
                videoAsset.resourceLoader.setDelegate(loader, queue: DispatchQueue.main)
                
                // ✅ 修复1：使用 API 的 timelength 替代 load(.duration)
                let apiDuration: CMTime
                if let ms = playResult.timelength, ms > 0 {
                    apiDuration = CMTime(value: CMTimeValue(ms), timescale: 1000)
                    print("⏱ [Player] API duration: \(Double(ms)/1000.0)s (skipping moov box scan)")
                } else {
                    print("⏱ [Player] timelength missing, fallback to load(.duration)...")
                    apiDuration = try await videoAsset.load(.duration)
                }
                
                // ✅ 修复2：通过 ResourceLoader 极速加载 tracks，不依赖内部 HTTP/2
                print("⏳ [Player] Loading video tracks via ResourceLoader...")
                let videoTracks = try await videoAsset.loadTracks(withMediaType: .video)
                
                guard let firstVideoTrack = videoTracks.first else {
                    throw NSError(domain: "PlayerError", code: -3,
                                  userInfo: [NSLocalizedDescriptionKey: "视频轨道为空（CDN 403/需要登录/URL 过期）"])
                }
                
                if let aUrl = audioURL, let bAudio = bestAudio {
                    print("🎧 [Player] Selected audio: \(bAudio.bandwidth ?? 0) bps, codecs: \(bAudio.codecs ?? "")")
                    
                    var aComp = URLComponents(url: aUrl, resolvingAgainstBaseURL: false)!
                    aComp.scheme = "bili-audio"
                    let customAudioURL = aComp.url!
                    
                    let audioAsset = AVURLAsset(url: customAudioURL)
                    audioAsset.resourceLoader.setDelegate(loader, queue: DispatchQueue.main)
                    let audioTracks = try await audioAsset.loadTracks(withMediaType: .audio)
                    
                    let composition = AVMutableComposition()
                    let fullRange = CMTimeRange(start: .zero, duration: apiDuration)
                    
                    if let compVideoTrack = composition.addMutableTrack(withMediaType: .video,
                                                                        preferredTrackID: kCMPersistentTrackID_Invalid) {
                        try compVideoTrack.insertTimeRange(fullRange, of: firstVideoTrack, at: .zero)
                    }
                    
                    if let firstAudioTrack = audioTracks.first,
                       let compAudioTrack = composition.addMutableTrack(withMediaType: .audio,
                                                                        preferredTrackID: kCMPersistentTrackID_Invalid) {
                        try compAudioTrack.insertTimeRange(fullRange, of: firstAudioTrack, at: .zero)
                    }
                    
                    let item = AVPlayerItem(asset: composition)
                    item.preferredForwardBufferDuration = 120
                    finalPlayerItem = item
                    self.statsViewModel.updateStreamInfo(videoTrack: bestVideo, audioTrack: bestAudio)
                    print("✅ [Player] DASH Composition ready (duration: \(apiDuration.seconds)s), starting playback...")
                    
                } else {
                    let item = AVPlayerItem(asset: videoAsset)
                    item.preferredForwardBufferDuration = 120
                    finalPlayerItem = item
                    self.statsViewModel.updateStreamInfo(videoTrack: bestVideo, audioTrack: nil)
                }
            }
            
            // 🌟 方案 B：MP4 / FLV 整段流降级
            if finalPlayerItem == nil, let durlSegments = playResult.durl, !durlSegments.isEmpty {
                let mp4Options: [String: Any] = ["AVURLAssetHTTPHeaderFieldsKey": headers]
                
                if durlSegments.count == 1,
                   let singleUrlString = durlSegments.first?.url,
                   let singleURL = URL(string: singleUrlString) {
                    print("🎬 [Player] Playing single MP4 stream...")
                    let asset = AVURLAsset(url: singleURL, options: mp4Options)
                    // 验证可达性
                    _ = try await asset.loadTracks(withMediaType: .video)
                    finalPlayerItem = AVPlayerItem(asset: asset)
                    self.statsViewModel.containerFormat = "Single MP4"
                } else {
                    print("🧩 [Player] Aggregating \(durlSegments.count) MP4 segments...")
                    let composition = AVMutableComposition()
                    guard let compVideoTrack = composition.addMutableTrack(withMediaType: .video,
                                                                            preferredTrackID: kCMPersistentTrackID_Invalid),
                          let compAudioTrack = composition.addMutableTrack(withMediaType: .audio,
                                                                            preferredTrackID: kCMPersistentTrackID_Invalid) else {
                        throw NSError(domain: "PlayerError", code: -2,
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
                    finalPlayerItem = AVPlayerItem(asset: composition)
                    self.statsViewModel.containerFormat = "Multi MP4"
                }
            }
            
            guard let playerItem = finalPlayerItem else {
                throw NSError(domain: "PlayerError", code: -1,
                              userInfo: [NSLocalizedDescriptionKey: "无法解析播放流（可能需要大会员或 CDN 鉴权失败）"])
            }
            
            // 监听 AVPlayerItem 错误
            let newPlayer = AVPlayer(playerItem: playerItem)
            self.player = newPlayer
            self.statsViewModel.startMonitoring(player: newPlayer)
            newPlayer.play()
            isLoading = false
            
        } catch {
            print("❌ [Player] Load error: \(error)")
            self.errorMessage = error.localizedDescription
            isLoading = false
        }
    }
}

// 封装 AVPlayerViewController 供 tvOS 原生播放
struct VideoPlayerViewControllerRepresentable: UIViewControllerRepresentable {
    let player: AVPlayer
    
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = true
        return controller
    }
    
    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        uiViewController.player = player
    }
}
