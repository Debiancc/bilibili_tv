import SwiftUI
import AVKit
import Combine

struct BiliPlayerContainerView: View {
    let item: FeedItem
    
    @State private var statsViewModel = PlayerStatsViewModel()
    @State private var player: AVPlayer?
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
            
            var playResult: PlayURLResult
            do {
                playResult = try await BilibiliService.shared.fetchPlayURL(epId: item.episodeId, cid: nil, qn: 120)
            } catch {
                print("⚠️ [Player] 4K qn=120 request failed, falling back to 1080P qn=80...")
                playResult = try await BilibiliService.shared.fetchPlayURL(epId: item.episodeId, cid: nil, qn: 80)
            }
            
            let headers: [String: String] = [
                "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/146.0.0.0 Safari/537.36",
                "Referer": "https://www.bilibili.com/",
                "Origin": "https://www.bilibili.com",
                "Cookie": BilibiliNetworkConfig.shared.cookie
            ]
            
            // 💡 针对 .m4s 指定 MIME 格式，防止 CoreMedia 抛出 -11828 Cannot Open 错误
            var dashVideoOptions: [String: Any] = ["AVURLAssetHTTPHeaderFieldsKey": headers]
            dashVideoOptions["AVURLAssetOutOfBandMIMETypeKey"] = "video/mp4"
            
            var dashAudioOptions: [String: Any] = ["AVURLAssetHTTPHeaderFieldsKey": headers]
            dashAudioOptions["AVURLAssetOutOfBandMIMETypeKey"] = "audio/mp4"
            
            var finalPlayerItem: AVPlayerItem?
            
            // 🌟 方案 A：自适应 DASH 音视频复合架构 (带异常捕获防线)
            if let bestVideo = playResult.bestVideoTrack,
               let videoUrlString = bestVideo.baseUrl,
               let videoURL = URL(string: videoUrlString) {
                
                print("🌟 [Player] Selected best adaptive video track: \(bestVideo.width ?? 0)x\(bestVideo.height ?? 0) @ \(bestVideo.bandwidth ?? 0) bps, codecs: \(bestVideo.codecs ?? "")")
                
                do {
                    let videoAsset = AVURLAsset(url: videoURL, options: dashVideoOptions)
                    
                    if let bestAudio = playResult.bestAudioTrack,
                       let audioUrlString = bestAudio.baseUrl,
                       let audioURL = URL(string: audioUrlString) {
                        
                        print("🎧 [Player] Selected best audio track: \(bestAudio.bandwidth ?? 0) bps, codecs: \(bestAudio.codecs ?? "")")
                        let audioAsset = AVURLAsset(url: audioURL, options: dashAudioOptions)
                        let composition = AVMutableComposition()
                        
                        if let compVideoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
                           let assetVideoTrack = try await videoAsset.loadTracks(withMediaType: .video).first {
                            let timeRange = CMTimeRange(start: .zero, duration: try await videoAsset.load(.duration))
                            try compVideoTrack.insertTimeRange(timeRange, of: assetVideoTrack, at: .zero)
                        }
                        
                        if let compAudioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid),
                           let assetAudioTrack = try await audioAsset.loadTracks(withMediaType: .audio).first {
                            let timeRange = CMTimeRange(start: .zero, duration: try await audioAsset.load(.duration))
                            try compAudioTrack.insertTimeRange(timeRange, of: assetAudioTrack, at: .zero)
                        }
                        
                        finalPlayerItem = AVPlayerItem(asset: composition)
                        self.statsViewModel.updateStreamInfo(videoTrack: bestVideo, audioTrack: bestAudio)
                    } else {
                        finalPlayerItem = AVPlayerItem(asset: videoAsset)
                        self.statsViewModel.updateStreamInfo(videoTrack: bestVideo, audioTrack: nil)
                    }
                } catch {
                    print("⚠️ [Player] DASH composition failed (\(error.localizedDescription)), attempting fallback to MP4 stream...")
                }
            }
            
            // 🌟 方案 B：MP4 流容错降级处理
            if finalPlayerItem == nil, let durlSegments = playResult.durl, !durlSegments.isEmpty {
                let mp4Options: [String: Any] = ["AVURLAssetHTTPHeaderFieldsKey": headers]
                
                if durlSegments.count == 1, let singleUrlString = durlSegments.first?.url, let singleURL = URL(string: singleUrlString) {
                    print("🎬 [Player] Playing authenticated MP4 stream directly...")
                    let singleAsset = AVURLAsset(url: singleURL, options: mp4Options)
                    finalPlayerItem = AVPlayerItem(asset: singleAsset)
                    self.statsViewModel.containerFormat = "Single MP4"
                } else {
                    print("🧩 [Player] Aggregating \(durlSegments.count) MP4 segments into a continuous movie timeline...")
                    let composition = AVMutableComposition()
                    guard let compVideoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
                          let compAudioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                        throw NSError(domain: "PlayerError", code: -2, userInfo: [NSLocalizedDescriptionKey: "无法创建组合音视频轨道"])
                    }
                    
                    var insertionPoint = CMTime.zero
                    
                    for segment in durlSegments {
                        guard let urlString = segment.url, let segmentURL = URL(string: urlString) else { continue }
                        let segmentAsset = AVURLAsset(url: segmentURL, options: mp4Options)
                        let duration = try await segmentAsset.load(.duration)
                        let timeRange = CMTimeRange(start: .zero, duration: duration)
                        
                        if let videoTrack = try await segmentAsset.loadTracks(withMediaType: .video).first {
                            try compVideoTrack.insertTimeRange(timeRange, of: videoTrack, at: insertionPoint)
                        }
                        if let audioTrack = try await segmentAsset.loadTracks(withMediaType: .audio).first {
                            try compAudioTrack.insertTimeRange(timeRange, of: audioTrack, at: insertionPoint)
                        }
                        
                        insertionPoint = CMTimeAdd(insertionPoint, duration)
                    }
                    
                    finalPlayerItem = AVPlayerItem(asset: composition)
                    self.statsViewModel.containerFormat = "Multi MP4"
                }
            }
            
            guard let playerItem = finalPlayerItem else {
                throw NSError(domain: "PlayerError", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法解析或合成播放流"])
            }
            
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
