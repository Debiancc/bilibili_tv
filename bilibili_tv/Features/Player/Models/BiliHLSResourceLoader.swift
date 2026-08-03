import Foundation
import AVFoundation
import UniformTypeIdentifiers

// 从 sidx Box 解析出的精确分片信息
struct SidxEntry {
    let byteStart: Int64
    let byteEnd: Int64
    let durationSeconds: Double
}

final class BiliHLSResourceLoader: NSObject, AVAssetResourceLoaderDelegate {
    private let videoURL: URL
    private let audioURL: URL?
    private let duration: Double
    private let bandwidth: Int
    private let resolution: String
    private let codecs: String
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
        self.duration = duration > 0 ? duration : 7200.0
        self.bandwidth = videoTrack?.bandwidth ?? 5000000
        let w = videoTrack?.width ?? 1920
        let h = videoTrack?.height ?? 1080
        
        // 💡 针对宽银幕 4K 电影 (如 4096x1716) 进行分辨率伪装：
        // 苹果 AVPlayerViewController 原生的 4K 角标点亮逻辑严格要求 height >= 2160。
        // 为了点亮 UI 角标，如果在 4K 级别，强行给 HLS 写上 3840x2160 (不影响底层按实际 4096x1716 解码渲染)
        if w >= 3840 {
            self.resolution = "3840x2160"
        } else {
            self.resolution = "\(w)x\(h)"
        }
        
        var codecString = videoTrack?.codecs ?? "avc1.640033"
        if let audioCodec = audioTrack?.codecs {
            codecString += ",\(audioCodec)"
        }
        self.codecs = codecString
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
            let sidxEndByte   = Int64(indexRange.components(separatedBy: "-").last  ?? "0") ?? 0
            let mediaStart    = sidxEndByte + 1  // 媒体数据从 sidx 结束后一字节开始
            
            let entries = parseSidx(data: data, mediaStartOffset: mediaStart)
            return entries
        } catch {
            print("❌ [sidx] Failed to fetch sidx: \(error)")
            return []
        }
    }
    
    // MARK: - sidx Binary Parser (ISO 14496-12)
    private static func parseSidx(data: Data, mediaStartOffset: Int64) -> [SidxEntry] {
        guard data.count >= 28 else {
            print("⚠️ [sidx] Data too small: \(data.count) bytes")
            return []
        }
        var offset = 0
        
        func readUInt8() -> UInt8 {
            guard offset < data.count else { return 0 }
            defer { offset += 1 }
            return data[offset]
        }
        func readUInt16() -> UInt16 {
            guard offset + 2 <= data.count else { return 0 }
            defer { offset += 2 }
            return data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt16.self).bigEndian }
        }
        func readUInt32() -> UInt32 {
            guard offset + 4 <= data.count else { return 0 }
            defer { offset += 4 }
            return data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self).bigEndian }
        }
        func readUInt64() -> UInt64 {
            guard offset + 8 <= data.count else { return 0 }
            defer { offset += 8 }
            return data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt64.self).bigEndian }
        }
        
        let boxSize = readUInt32()
        let boxType = readUInt32()
        
        // 期望是 'sidx' (0x73696478)
        guard boxType == 0x73696478 else {
            print("⚠️ [sidx] Unexpected box type: \(String(format: "%08X", boxType)), expected sidx(0x73696478). boxSize=\(boxSize)")
            return []
        }
        
        let version  = readUInt8()
        offset += 3   // flags
        offset += 4   // reference_ID
        let timescale = readUInt32()
        
        var firstOffset: Int64 = 0
        if version == 0 {
            offset += 4 // earliest_presentation_time (32-bit)
            firstOffset = Int64(readUInt32()) // first_offset (32-bit)
        } else {
            offset += 8 // earliest_presentation_time (64-bit)
            firstOffset = Int64(bitPattern: readUInt64()) // first_offset (64-bit)
        }
        
        offset += 2  // reserved (2 bytes)
        let referenceCount = readUInt16()  // ✅ 正确：2 字节，不是 4 字节！
        
        print("🔬 [sidx] version=\(version) timescale=\(timescale) firstOffset=\(firstOffset) referenceCount=\(referenceCount) mediaStart=\(mediaStartOffset)")
        
        // 媒体数据实际起始字节
        var currentByteOffset = mediaStartOffset + firstOffset
        var entries: [SidxEntry] = []
        
        for i in 0..<referenceCount {
            guard offset + 12 <= data.count else { break }
            
            let referenceInfo = readUInt32()
            let referenceType  = (referenceInfo >> 31) & 1
            let referencedSize = Int64(referenceInfo & 0x7FFFFFFF)
            let subsegmentDuration = readUInt32()
            offset += 4 // SAP info
            
            if referenceType == 0 { // 0 = media segment (1 = index segment，跳过)
                let durationSeconds = timescale > 0 ? Double(subsegmentDuration) / Double(timescale) : 0
                if i < 3 {
                    print("   sidx[\(i)] size=\(referencedSize) dur=\(subsegmentDuration)/\(timescale)=\(String(format: "%.2f", durationSeconds))s start=\(currentByteOffset)")
                }
                entries.append(SidxEntry(
                    byteStart: currentByteOffset,
                    byteEnd: currentByteOffset + referencedSize - 1,
                    durationSeconds: durationSeconds
                ))
                currentByteOffset += referencedSize
            } else {
                print("   sidx[\(i)] SKIPPED (reference_type=1 index segment, size=\(referencedSize))")
            }
        }
        return entries
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
            if audioURL != nil {
                manifest = """
                #EXTM3U
                #EXT-X-VERSION:7
                #EXT-X-INDEPENDENT-SEGMENTS

                #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio",NAME="Main Audio",DEFAULT=YES,AUTOSELECT=YES,URI="audio.m3u8"
                #EXT-X-STREAM-INF:BANDWIDTH=\(bandwidth),CODECS="\(codecs)",AUDIO="audio",RESOLUTION=\(resolution)
                video.m3u8
                """
            } else {
                manifest = """
                #EXTM3U
                #EXT-X-VERSION:7
                #EXT-X-INDEPENDENT-SEGMENTS

                #EXT-X-STREAM-INF:BANDWIDTH=\(bandwidth),CODECS="\(codecs)",RESOLUTION=\(resolution)
                video.m3u8
                """
            }
        } else if path == "video.m3u8" || path == "audio.m3u8" {
            let isVideo = path == "video.m3u8"
            let entries  = isVideo ? videoSidxEntries : audioSidxEntries
            
            if !entries.isEmpty {
                // ✅ 用 sidx 精确切片生成 M3U8，并使用 BYTERANGE 指向同一文件
                let maxDur = entries.map { $0.durationSeconds }.max() ?? 10.0
                let streamURI = isVideo ? videoURL.absoluteString : (audioURL?.absoluteString ?? "")
                let segmentBase = isVideo ? videoSegmentBase : audioSegmentBase
                let initRange = segmentBase?.initialization ?? "0-932"
                let initEnd = Int(initRange.components(separatedBy: "-").last ?? "932") ?? 932
                
                let indexRange = segmentBase?.indexRange ?? ""
                let indexEnd = Int(indexRange.components(separatedBy: "-").last ?? "") ?? initEnd
                let initLength = indexEnd + 1 // ✅ 将 init 和 sidx 合并作为 MAP 喂给 AVPlayer，解决 moof 绝对偏移量解析崩溃问题 (-12860)
                
                var lines = [
                    "#EXTM3U",
                    "#EXT-X-VERSION:7",
                    "#EXT-X-TARGETDURATION:\(Int(ceil(maxDur)))",
                    "#EXT-X-MEDIA-SEQUENCE:0",
                    "#EXT-X-PLAYLIST-TYPE:VOD",
                    "#EXT-X-MAP:URI=\"\(streamURI)\",BYTERANGE=\"\(initLength)@0\""
                ]
                for entry in entries {
                    let size = entry.byteEnd - entry.byteStart + 1
                    lines.append(String(format: "#EXTINF:%.3f,", entry.durationSeconds))
                    lines.append("#EXT-X-BYTERANGE:\(size)@\(entry.byteStart)")
                    lines.append(streamURI)
                }
                lines.append("#EXT-X-ENDLIST")
                manifest = lines.joined(separator: "\n")
                print("📋 [M3U8] Generated \(isVideo ? "video" : "audio") BYTERANGE playlist with \(entries.count) segments")
            } else {
                // Fallback: 单段整体
                let targetDuration = Int(ceil(duration))
                let streamURI = isVideo ? "video_stream.m4s" : "audio_stream.m4s"
                manifest = """
                #EXTM3U
                #EXT-X-VERSION:7
                #EXT-X-TARGETDURATION:\(targetDuration)
                #EXT-X-MEDIA-SEQUENCE:0
                #EXT-X-PLAYLIST-TYPE:VOD
                #EXT-X-MAP:URI="\(streamURI)"
                #EXTINF:\(String(format: "%.3f", duration)),
                \(streamURI)
                #EXT-X-ENDLIST
                """
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
