import AVFoundation
import Foundation
import UniformTypeIdentifiers

final class BiliHLSResourceLoader: NSObject, AVAssetResourceLoaderDelegate {
    private let videoURL: URL
    private let audioURL: URL?
    private let duration: Double
    private let bandwidth: Int
    private let resolution: String
    private let codecs: String
    private let supplementalCodecs: String?
    private let frameRate: String?
    private let videoRange: String?
    private let hdcpLevel: String?
    private let audioName: String?
    private let videoSegmentBase: SegmentBaseInfo?
    private let audioSegmentBase: SegmentBaseInfo?
    private let headers: [String: String]

    // ✅ 用同一个串行队列同时驱动 ResourceLoader delegate 和 URLSession delegate，
    //    彻底消除 activeTasks / pendingRequests 的并发竞态（Race Condition）。
    let resourceQueue = DispatchQueue(label: "com.bilitv.hls.loader", qos: .userInitiated)

    // sidx 解析结果
    private(set) var videoSidxEntries: [SidxEntry] = []
    private(set) var audioSidxEntries: [SidxEntry] = []

    init(
        videoURL: URL,
        audioURL: URL?,
        duration: Double,
        videoTrack: DashVideoItem?,
        audioTrack: DashAudioItem?,
        headers: [String: String]
    ) {
        self.videoURL = videoURL
        self.audioURL = audioURL
        self.duration = duration > 0 ? duration : 7_200.0
        self.bandwidth = videoTrack?.bandwidth ?? 5_000_000
        let w = videoTrack?.width ?? 1_920
        let h = videoTrack?.height ?? 1_080

        // 💡 针对宽银幕 4K 电影 (如 4096x1716) 进行分辨率伪装：
        // 苹果 AVPlayerViewController 原生的 4K 角标点亮逻辑严格要求 height >= 2160。
        // 为了点亮 UI 角标，如果在 4K 级别，强行给 HLS 写上 3840x2160 (不影响底层按实际 4096x1716 解码渲染)
        if w >= 3_840 {
            self.resolution = "3840x2160"
        } else {
            self.resolution = "\(w)x\(h)"
        }

        let derived = M3U8Generator.deriveVideoProperties(
            codecs: videoTrack?.codecs ?? "avc1.640033",
            qualityId: videoTrack?.qualityId,
            drmType: videoTrack?.drmType,
            frameRate: videoTrack?.frameRate
        )

        if let audioCodec = audioTrack?.codecs {
            self.codecs = "\(derived.codecs),\(audioCodec)"
        } else {
            self.codecs = derived.codecs
        }
        self.supplementalCodecs = derived.supplementalCodecs
        self.videoRange = derived.videoRange
        self.hdcpLevel = derived.hdcpLevel
        self.frameRate = derived.frameRate

        if let audioBw = audioTrack?.bandwidth, audioBw > 0 {
            let kbps = audioBw / 1_000
            self.audioName = "Main Audio (\(kbps)kbps)"
        } else {
            self.audioName = nil
        }

        self.videoSegmentBase = videoTrack?.segmentBase
        self.audioSegmentBase = audioTrack?.segmentBase
        self.headers = headers
        super.init()
    }

    // MARK: - 预解析 sidx（在 AVURLAsset 创建前调用）
    func prefetchSidx() async {
        let vUrl = self.videoURL
        let aUrl = self.audioURL
        let vSb = self.videoSegmentBase
        let aSb = self.audioSegmentBase
        let hdrs = self.headers

        async let videoEntries: [SidxEntry] = {
            if let sb = vSb, let idxRange = sb.indexRange, !idxRange.isEmpty, let initRange = sb.initialization {
                return await Self.fetchAndParseSidx(from: vUrl, initRange: initRange, indexRange: idxRange, headers: hdrs)
            }
            return []
        }()

        async let audioEntries: [SidxEntry] = {
            if let sb = aSb, let idxRange = sb.indexRange, !idxRange.isEmpty, let initRange = sb.initialization, let url = aUrl {
                return await Self.fetchAndParseSidx(from: url, initRange: initRange, indexRange: idxRange, headers: hdrs)
            }
            return []
        }()

        let (v, a) = await (videoEntries, audioEntries)
        self.videoSidxEntries = v
        self.audioSidxEntries = a
        print("📐 [sidx] Video segments parsed: \(v.count) entries")
        print("📐 [sidx] Audio segments parsed: \(a.count) entries")
    }

    private static func fetchAndParseSidx(from url: URL, initRange: String, indexRange: String, headers: [String: String]) async -> [SidxEntry] {
        var request = URLRequest(url: url)
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        request.setValue("bytes=\(indexRange)", forHTTPHeaderField: "Range")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)

            // 解析 sidx 结束位置（索引范围结束字节 + 1）
            //            let sidxStartByte = Int64(indexRange.components(separatedBy: "-").first ?? "0") ?? 0
            let sidxEndByte = Int64(indexRange.components(separatedBy: "-").last ?? "0") ?? 0
            let mediaStart = sidxEndByte + 1  // 媒体数据从 sidx 结束后一字节开始

            let entries = SidxParser.parse(data: data, mediaStartOffset: mediaStart)
            return entries
        } catch {
            print("❌ [sidx] Failed to fetch sidx: \(error)")
            return []
        }
    }

    // MARK: - AVAssetResourceLoaderDelegate
    func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
    ) -> Bool {
        guard let url = loadingRequest.request.url else { return false }
        let path = url.lastPathComponent
        print("🌐 [HLS ResourceLoader] Requesting: \(url.absoluteString)")

        if path.hasSuffix(".m3u8") {
            return handleHLSPlaylist(loadingRequest: loadingRequest, url: url)
        }
        //        else if path.contains("segment") || path.hasSuffix(".m4s") {
        //            return handleSegmentProxy(loadingRequest: loadingRequest, url: url)
        //        }
        return false
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, didCancel loadingRequest: AVAssetResourceLoadingRequest) {
        print("🛑 [HLS ResourceLoader] didCancel loadingRequest for \(loadingRequest.request.url?.lastPathComponent ?? "unknown")")
    }

    // MARK: - HLS Manifest Generation
    private func handleHLSPlaylist(loadingRequest: AVAssetResourceLoadingRequest, url: URL) -> Bool {
        let path = url.lastPathComponent
        let manifest: String

        if path == "master.m3u8" {
            manifest = M3U8Generator.generateMasterPlaylist(
                bandwidth: bandwidth,
                codecs: codecs,
                supplementalCodecs: supplementalCodecs,
                resolution: resolution,
                frameRate: frameRate,
                videoRange: videoRange,
                hdcpLevel: hdcpLevel,
                audioName: audioName,
                hasAudio: audioURL != nil
            )
        } else if path == "video.m3u8" || path == "audio.m3u8" {
            let isVideo = path == "video.m3u8"
            let entries = isVideo ? videoSidxEntries : audioSidxEntries

            if !entries.isEmpty {
                let streamURI = isVideo ? videoURL.absoluteString : (audioURL?.absoluteString ?? "")
                let segmentBase = isVideo ? videoSegmentBase : audioSegmentBase
                manifest = M3U8Generator.generateSegmentPlaylist(
                    streamURI: streamURI,
                    entries: entries,
                    initRange: segmentBase?.initialization,
                    indexRange: segmentBase?.indexRange
                )
                print("📋 [M3U8] Generated \(isVideo ? "video" : "audio") BYTERANGE playlist with \(entries.count) segments")
            } else {
                let streamURI = isVideo ? "video_stream.m4s" : "audio_stream.m4s"
                manifest = M3U8Generator.generateFallbackPlaylist(
                    streamURI: streamURI,
                    duration: duration
                )
                print("⚠️ [M3U8] No sidx entries, using single-segment fallback for \(isVideo ? "video" : "audio")")
            }
        } else {
            return false
        }

        guard let data = manifest.data(using: .utf8) else { return false }
        let infoRequest = loadingRequest.contentInformationRequest
        infoRequest?.contentType = "application/vnd.apple.mpegurl"
        infoRequest?.contentLength = Int64(data.count)
        infoRequest?.isByteRangeAccessSupported = false
        loadingRequest.dataRequest?.respond(with: data)
        loadingRequest.finishLoading()
        return true
    }
}
