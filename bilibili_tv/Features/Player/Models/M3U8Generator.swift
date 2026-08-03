import Foundation

/// HLS 视频变体流模型
struct M3U8StreamVariant {
    let bandwidth: Int
    let codecs: String
    let supplementalCodecs: String?
    let resolution: String
    let frameRate: String?
    let videoRange: String?
    let hdcpLevel: String?
    let uri: String
    
    init(
        bandwidth: Int,
        codecs: String,
        supplementalCodecs: String? = nil,
        resolution: String,
        frameRate: String? = nil,
        videoRange: String? = nil,
        hdcpLevel: String? = nil,
        uri: String = "video.m3u8"
    ) {
        self.bandwidth = bandwidth
        self.codecs = codecs
        self.supplementalCodecs = supplementalCodecs
        self.resolution = resolution
        self.frameRate = frameRate
        self.videoRange = videoRange
        self.hdcpLevel = hdcpLevel
        self.uri = uri
    }
}

/// HLS 音频媒体流模型
struct M3U8AudioVariant {
    let groupID: String
    let name: String
    let isDefault: Bool
    let autoSelect: Bool
    let language: String
    let uri: String
    
    init(
        groupID: String = "audio",
        name: String = "Main Audio",
        isDefault: Bool = true,
        autoSelect: Bool = true,
        language: String = "zh",
        uri: String = "audio.m3u8"
    ) {
        self.groupID = groupID
        self.name = name
        self.isDefault = isDefault
        self.autoSelect = autoSelect
        self.language = language
        self.uri = uri
    }
}

/// HLS M3U8 Playlist 生成器（解耦无副作用纯逻辑）
struct M3U8Generator {
    
    /// 生成单流/基本 Master Playlist (master.m3u8)
    static func generateMasterPlaylist(
        bandwidth: Int,
        codecs: String,
        supplementalCodecs: String? = nil,
        resolution: String,
        frameRate: String? = nil,
        videoRange: String? = nil,
        hdcpLevel: String? = nil,
        audioName: String? = nil,
        hasAudio: Bool
    ) -> String {
        let videoVariant = M3U8StreamVariant(
            bandwidth: bandwidth,
            codecs: codecs,
            supplementalCodecs: supplementalCodecs,
            resolution: resolution,
            frameRate: frameRate,
            videoRange: videoRange,
            hdcpLevel: hdcpLevel,
            uri: "video.m3u8"
        )
        
        let audioVariants = hasAudio ? [
            M3U8AudioVariant(
                groupID: "audio",
                name: audioName ?? "Main Audio",
                isDefault: true,
                autoSelect: true,
                language: "zh",
                uri: "audio.m3u8"
            )
        ] : []
        
        return generateMultiVariantMasterPlaylist(variants: [videoVariant], audioVariants: audioVariants)
    }
    
    /// 生成包含多变体画质/音轨的 Multi-Variant Master Playlist
    static func generateMultiVariantMasterPlaylist(
        variants: [M3U8StreamVariant],
        audioVariants: [M3U8AudioVariant] = []
    ) -> String {
        var lines = [
            "#EXTM3U",
            "#EXT-X-VERSION:7",
            "#EXT-X-INDEPENDENT-SEGMENTS"
        ]
        
        for audio in audioVariants {
            let defaultStr = audio.isDefault ? "YES" : "NO"
            let autoStr = audio.autoSelect ? "YES" : "NO"
            lines.append(#"#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="\#(audio.groupID)",NAME="\#(audio.name)",DEFAULT=\#(defaultStr),AUTOSELECT=\#(autoStr),LANGUAGE="\#(audio.language)",URI="\#(audio.uri)""#)
        }
        
        let hasAudioGroup = !audioVariants.isEmpty
        
        for variant in variants {
            var attributes = [
                "BANDWIDTH=\(variant.bandwidth)",
                "CODECS=\"\(variant.codecs)\""
            ]
            
            if let supp = variant.supplementalCodecs, !supp.isEmpty {
                attributes.append("SUPPLEMENTAL-CODECS=\"\(supp)\"")
            }
            
            if hasAudioGroup {
                attributes.append("AUDIO=\"\(audioVariants.first?.groupID ?? "audio")\"")
            }
            
            attributes.append("RESOLUTION=\(variant.resolution)")
            
            if let fps = variant.frameRate, !fps.isEmpty {
                attributes.append("FRAME-RATE=\(fps)")
            }
            
            if let vRange = variant.videoRange, !vRange.isEmpty {
                attributes.append("VIDEO-RANGE=\(vRange)")
            }
            
            if let hdcp = variant.hdcpLevel, !hdcp.isEmpty {
                attributes.append("HDCP-LEVEL=\(hdcp)")
            }
            
            lines.append("#EXT-X-STREAM-INF:" + attributes.joined(separator: ","))
            lines.append(variant.uri)
        }
        
        return lines.joined(separator: "\n")
    }
    
    /// 生成基于 SIDX 切片的 Media Playlist (video.m3u8 / audio.m3u8)
    static func generateSegmentPlaylist(
        streamURI: String,
        entries: [SidxEntry],
        initRange: String? = nil,
        indexRange: String? = nil
    ) -> String {
        guard !entries.isEmpty else {
            return ""
        }
        
        let maxDur = entries.map { $0.durationSeconds }.max() ?? 10.0
        let targetDuration = Int(ceil(maxDur))
        
        let parsedInitRange = initRange ?? "0-932"
        let initEnd = Int(parsedInitRange.components(separatedBy: "-").last ?? "932") ?? 932
        
        let parsedIndexRange = indexRange ?? ""
        let indexEnd = Int(parsedIndexRange.components(separatedBy: "-").last ?? "") ?? initEnd
        let initLength = indexEnd + 1
        
        var lines = [
            "#EXTM3U",
            "#EXT-X-VERSION:7",
            "#EXT-X-TARGETDURATION:\(targetDuration)",
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
        return lines.joined(separator: "\n")
    }
    
    /// 生成无 SIDX 时的 Fallback 单段 M3U8
    static func generateFallbackPlaylist(
        streamURI: String,
        duration: Double
    ) -> String {
        let targetDuration = Int(ceil(duration))
        return """
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
    }
}
