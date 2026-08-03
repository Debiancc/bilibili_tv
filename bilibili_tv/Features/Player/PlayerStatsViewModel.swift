import Foundation
import AVFoundation
import Observation

/// 🌟 特性 1：使用 Swift 6 原生 @Observable 宏的 PlayerStatsViewModel
@Observable
@MainActor
class PlayerStatsViewModel {
    var isVisible: Bool = {
        if UserDefaults.standard.object(forKey: "isDebugStatsEnabled") == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: "isDebugStatsEnabled")
    }()
    
    // 基础流属性
    var resolution: String = "未知"
    var frameRate: String = "未知"
    var videoCodec: String = "未知"
    var audioCodec: String = "未知"
    var videoBitrate: String = "未知"
    var audioBitrate: String = "未知"
    var containerFormat: String = "DASH (.m4s)"
    var streamURL: String = "无"
    
    // 实时播放属性
    var currentPLayhead: String = "00:00:00"
    var bufferedDuration: String = "0.00 s"
    var droppedFrames: String = "0"
    var playerState: String = "初始化"
    var connectionSpeed: String = "0 Kbps"
    var volume: String = "100%"
    
    @ObservationIgnored
    private nonisolated(unsafe) var statsTimer: Timer?
    private weak var player: AVPlayer?
    
    deinit {
        statsTimer?.invalidate()
    }
    
    /// 开始对当前 AVPlayer 进行高频性能抓取与监控
    func startMonitoring(player: AVPlayer) {
        stopMonitoring()
        self.player = player
        
        // 每秒抓取一次播放器性能数据
        statsTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateStats()
            }
        }
    }
    
    /// 停止监控
    func stopMonitoring() {
        statsTimer?.invalidate()
        statsTimer = nil
    }
    
    /// 刷新视音频极客面板数据
    func updateStats() {
        guard let player = player, let currentItem = player.currentItem else {
            playerState = "无媒体项"
            return
        }
        
        // 1. 提取当前播放时间
        let currentTime = currentItem.currentTime().seconds
        if !currentTime.isNaN && !currentTime.isInfinite {
            let hours = Int(currentTime) / 3600
            let minutes = (Int(currentTime) % 3600) / 60
            let seconds = Int(currentTime) % 60
            currentPLayhead = String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        }
        
        // 2. 提取当前已缓冲长度
        if let firstRange = currentItem.loadedTimeRanges.first?.timeRangeValue {
            let startSeconds = firstRange.start.seconds
            let durationSeconds = firstRange.duration.seconds
            let bufferEnd = startSeconds + durationSeconds
            let remainingBuffer = max(0, bufferEnd - currentTime)
            bufferedDuration = String(format: "%.2f s", remainingBuffer)
        } else {
            bufferedDuration = "0.00 s"
        }
        
        // 3. 提取播放器状态 (基于 timeControlStatus 更加准确)
        playerState = switch player.timeControlStatus {
        case .playing: "正在播放"
        case .paused: "已暂停"
        case .waitingToPlayAtSpecifiedRate: "缓冲中"
        @unknown default: "未知"
        }
        
        // 4. 提取 YouTube 风格的其他进阶指标 (AccessLog)
        if let accessLog = currentItem.accessLog(), let lastEvent = accessLog.events.last {
            droppedFrames = "\(lastEvent.numberOfDroppedVideoFrames)"
            
            let bitrate = lastEvent.observedBitrate
            if bitrate > 0 {
                connectionSpeed = String(format: "%.0f Kbps", bitrate / 1024)
            } else {
                connectionSpeed = "0 Kbps"
            }
        } else {
            connectionSpeed = "0 Kbps"
        }
        }
        
        // 5. 音量
        volume = String(format: "%.0f%%", player.volume * 100)
    }
    
    /// 根据底层 API 解析出来的流媒体属性更新数据
    func updateStreamInfo(videoTrack: DashVideoItem?, audioTrack: DashAudioItem?) {
        if let v = videoTrack {
            if let w = v.width, let h = v.height {
                resolution = "\(w)x\(h)"
            }
            if let fps = v.frameRate {
                frameRate = "\(fps) fps"
            }
            if let code = v.codecs {
                videoCodec = code
            }
            if let band = v.bandwidth {
                let kbps = band / 1000
                videoBitrate = "\(kbps) kbps"
            }
            if let url = v.baseUrl {
                streamURL = url
            }
        }
        
        if let a = audioTrack {
            if let code = a.codecs {
                audioCodec = code
            }
            if let band = a.bandwidth {
                let kbps = band / 1000
                audioBitrate = "\(kbps) kbps"
            }
        }
    }
}
