import AVFoundation
import Foundation

// MARK: - 播放流加载器（阶段三 3a）
//
// loadVideo 原为 BiliPlayerContainerView 中 74 行 + lint 豁免命令（function_body_length
// 与 cyclomatic_complexity）的 God 方法，按职责拆分为独立的构造步骤：
//   load(input:)                → 加载总流程（qn 降级 + 双方案 + metadata + cid 解析）
//   loadPlayerItem(input:)      → 方案 A (DASH/HLS) 优先，方案 B (MP4/durl) 降级
//   makeHLSPlayerItem(...)      → DASH 动态 M3U8 + sidx 预取
//   makeMP4PlayerItem(...)      → 单段 MP4 / 多段 AVMutableComposition 合成
//
// 并发/生命周期设计：加载流程整体挂在值类型的 PlayerLoadInput 输入上，挂起期间
// 不持有 PlayerViewModel —— 否则 @MainActor 实例方法挂起帧会强持有 VM，导致
// deinit 永不触发、loadTask 取消失效（见 PlayerViewModelTests 的 deinit 用例）。

/// 播放流加载所需的全部输入（值类型快照，避免加载挂起期间强持有 PlayerViewModel）
struct PlayerLoadInput {
    let epId: Int?
    let seasonId: Int?
    let title: String?
    let subtitle: String?
    let coverURL: URL?
    let service: any PlayerServicing
    let statsViewModel: PlayerStatsViewModel
}

/// 加载结果：playerItem 非 nil 即 ready；nil 时 error 携带失败信息
struct PlayerLoadOutcome {
    var playerItem: AVPlayerItem?
    var hlsLoader: BiliHLSResourceLoader?
    var isPreviewOnly = false
    var purchaseHintText: String?
    var currentCid: Int?
    var error: PlayerError?
}

/// 播放流加载器：不持有任何 ViewModel，仅在挂起结束后由 VM 回写状态
@MainActor
enum PlayerItemLoader {
    static func load(input: PlayerLoadInput) async -> PlayerLoadOutcome {
        var outcome = PlayerLoadOutcome()
        do {
            guard input.epId != nil || input.seasonId != nil else {
                outcome.error = .missingIdentifiers
                return outcome
            }
            print("🚀 [Player] Resolving adaptive streams for epId: \(input.epId ?? 0)...")

            let playResult = try await fetchPlayResult(input: input)

            // 🎬 检测试看状态:未购买时仅返回试看片段,播放器叠加提示横幅
            outcome.isPreviewOnly = playResult.isPreviewOnly
            outcome.purchaseHintText = playResult.purchaseHintText
            if outcome.isPreviewOnly {
                logPreviewState(playResult, hint: outcome.purchaseHintText)
            }

            let (playerItem, loader) = try await loadPlayerItem(from: playResult, input: input)
            guard let playerItem else {
                outcome.error = .sourceUnavailable
                return outcome
            }
            outcome.playerItem = playerItem
            outcome.hlsLoader = loader

            // 💬 cid 解析（弹幕会话由 View 在 .ready 后启动）
            outcome.currentCid = await resolveCid(from: playResult, input: input)
        } catch is CancellationError {
            print("❌ [Player] Load cancelled")
        } catch {
            print("❌ [Player] Load error: \(error)")
            outcome.error = PlayerError.normalize(error)
        }
        return outcome
    }

    /// 请求播放流：qn=120 (4K/杜比) 失败时精确降级到 qn=80 (1080P)，不跳级
    static func fetchPlayResult(input: PlayerLoadInput) async throws -> PlayURLResult {
        let requestedQn = 120
        do {
            return try await input.service.fetchPlayURL(
                epId: input.epId, cid: nil, seasonId: input.seasonId, qn: requestedQn)
        } catch is CancellationError {
            // 取消：保持原行为（直接退出，不进入降级）
            throw CancellationError()
        } catch {
            print("⚠️ [Player] qn=\(requestedQn) failed, trying qn=80 (1080P)...")
            return try await input.service.fetchPlayURL(
                epId: input.epId, cid: nil, seasonId: input.seasonId, qn: 80)
        }
    }

    /// 💬 解析弹幕 cid（playurl 响应优先，season/ep 详情兜底）
    static func resolveCid(from playResult: PlayURLResult, input: PlayerLoadInput) async -> Int? {
        if let cid = playResult.cid {
            print("💬 [Player] cid resolved from playurl response, cid: \(cid)")
            return cid
        }
        if let epId = input.epId {
            // 🔄 playurl 响应无 cid 字段,从 season detail / ep 详情兜底
            do {
                let cid = try await input.service.fetchEpisodeCid(epId: epId, seasonId: input.seasonId)
                if let cid {
                    print("💬 [Player] cid resolved via fallback: \(cid)")
                    return cid
                }
                print("⚠️ [Player] fetchEpisodeCid returned nil (epId: \(epId), seasonId: \(input.seasonId ?? -1))")
            } catch {
                print("❌ [Player] fetchEpisodeCid failed: \(error) (epId: \(epId), seasonId: \(input.seasonId ?? -1))")
            }
        } else {
            print("⚠️ [Player] No cid available, danmaku disabled")
        }
        return nil
    }

    static func logPreviewState(_ playResult: PlayURLResult, hint: String?) {
        print(
            "🔒 [Player] Preview-only stream detected "
                + "(is_preview=\(playResult.isPreview ?? -1), has_paid=\(playResult.hasPaid), "
                + "error_code=\(playResult.errorCode ?? 0), vip_status=\(playResult.vipStatus ?? 0)), hint: \(hint ?? "nil")"
        )
    }

    /// 构造 AVPlayerItem：优先 DASH（方案 A），无 DASH 时降级 MP4/durl（方案 B）。
    /// 返回 (item, loader)：loader 需由调用方持有强引用（AVAssetResourceLoaderDelegate 为 weak）。
    static func loadPlayerItem(from playResult: PlayURLResult, input: PlayerLoadInput) async throws -> (
        AVPlayerItem?, BiliHLSResourceLoader?
    ) {
        let headers = streamHeaders

        // 🌟 方案 A: DASH 流 (通过动态 HLS M3U8 生成器 + ResourceLoader)
        if let bestVideo = playResult.bestVideoTrack(maxQn: 120),
            let videoUrlString = bestVideo.baseUrl,
            let videoURL = URL(string: videoUrlString)
        {
            let (item, loader) = try await makeHLSPlayerItem(
                playResult: playResult, video: bestVideo, videoURL: videoURL, headers: headers, input: input)
            return (item, loader)
        }

        // 🌟 方案 B：MP4 / FLV 整段流降级 (针对无 DASH、仅返回 durl 的试看/普通流)
        if !playResult.durl.isEmpty {
            let item = try await makeMP4PlayerItem(durlSegments: playResult.durl, headers: headers, input: input)
            return (item, nil)
        }

        return (nil, nil)
    }

    /// 🌟 方案 A: DASH 流 (动态 HLS M3U8 生成器 + ResourceLoader)
    static func makeHLSPlayerItem(
        playResult: PlayURLResult,
        video: DashVideoItem,
        videoURL: URL,
        headers: [String: String],
        input: PlayerLoadInput
    ) async throws -> (AVPlayerItem, BiliHLSResourceLoader) {
        print(
            "🌟 [Player] Selected video: \(video.width ?? 0)x\(video.height ?? 0) @ \(video.bandwidth ?? 0) bps, codecs: \(video.codecs ?? "")"
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
            videoTrack: video,
            audioTrack: bestAudio,
            headers: headers
        )

        // ⚡️ 关键：在创建 AVURLAsset 之前先解析 sidx
        // 让 sidx 精确分片字节表在播放器请求 M3U8 前就已经准备好
        print("🔍 [Player] Pre-fetching sidx segment index...")
        await loader.prefetchSidx()
        print("✅ [Player] sidx pre-fetched: \(loader.videoSidxEntries.count) video, \(loader.audioSidxEntries.count) audio segments")

        guard let masterURL = URL(string: "bili-hls://localhost/master.m3u8") else {
            throw PlayerError.unknown(
                NSError(domain: "PlayerError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid HLS Master URL"]))
        }

        let options: [String: Any] = ["AVURLAssetHTTPHeaderFieldsKey": headers]
        let asset = AVURLAsset(url: masterURL, options: options)

        // ✅ 使用与 URLSession delegate 相同的串行队列，彻底消除竞态
        asset.resourceLoader.setDelegate(loader, queue: loader.resourceQueue)

        let item = AVPlayerItem(asset: asset)

        // 🏷️ 设置 externalMetadata (标题/副标题 + 异步封面),与 MP4 降级路径共用
        applyMetadata(to: item, title: input.title, subtitle: input.subtitle, coverURL: input.coverURL)

        // 🚀 阶段1：起播极速冲刺期 (Initial Burst Phase) -> 设为 25 秒缓冲区
        item.preferredForwardBufferDuration = 25.0

        input.statsViewModel.updateStreamInfo(videoTrack: video, audioTrack: bestAudio)
        print("✅ [Player] HLS M3U8 Asset ready (duration: \(durationSeconds)s), starting playback...")
        return (item, loader)
    }

    /// 🌟 方案 B：MP4 / FLV 整段流降级（单段直连 / 多段合成）
    static func makeMP4PlayerItem(
        durlSegments: [MP4URLItem], headers: [String: String], input: PlayerLoadInput
    ) async throws -> AVPlayerItem {
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
            applyMetadata(to: item, title: input.title, subtitle: input.subtitle, coverURL: input.coverURL)
            input.statsViewModel.containerFormat = "Single MP4"
            return item
        }

        return try await makeAggregatedMP4PlayerItem(
            durlSegments: durlSegments, mp4Options: mp4Options, input: input)
    }

    /// 🧩 多段 MP4:AVMutableComposition 按时间轴顺序合成
    static func makeAggregatedMP4PlayerItem(
        durlSegments: [MP4URLItem], mp4Options: [String: Any], input: PlayerLoadInput
    ) async throws -> AVPlayerItem {
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
            throw PlayerError.unsupportedFormat
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
        applyMetadata(to: item, title: input.title, subtitle: input.subtitle, coverURL: input.coverURL)
        input.statsViewModel.containerFormat = "Multi MP4"
        return item
    }

    /// 播放流 CDN 请求头（UA/Referer/Origin/Cookie），DASH 与 MP4 路径共用
    static var streamHeaders: [String: String] {
        [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/146.0.0.0 Safari/537.36",
            "Referer": "https://www.bilibili.com/",
            "Origin": "https://www.bilibili.com",
            "Cookie": BilibiliNetworkConfig.shared.cookie
        ]
    }
}
