import Testing
import Foundation
@testable import bilibili_tv

struct M3U8GeneratorTests {
    
    // MARK: - Master Playlist Tests
    
    @Test func testGenerateMasterPlaylist_withAudioTrack() {
        let master = M3U8Generator.generateMasterPlaylist(
            bandwidth: 9403729,
            codecs: "avc1.64002A, mp4a.40.2",
            resolution: "1920x1080",
            hasAudio: true
        )
        
        #expect(master.contains("#EXTM3U"))
        #expect(master.contains("#EXT-X-VERSION:7"))
        #expect(master.contains("#EXT-X-INDEPENDENT-SEGMENTS"))
        #expect(master.contains(#"#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio",NAME="Main Audio",DEFAULT=YES,AUTOSELECT=YES,LANGUAGE="zh",URI="audio.m3u8""#))
        #expect(master.contains(#"#EXT-X-STREAM-INF:BANDWIDTH=9403729,CODECS="avc1.64002A, mp4a.40.2",AUDIO="audio",RESOLUTION=1920x1080"#))
        #expect(master.contains("video.m3u8"))
    }
    
    @Test func testGenerateMasterPlaylist_withoutAudioTrack() {
        let master = M3U8Generator.generateMasterPlaylist(
            bandwidth: 4000000,
            codecs: "avc1.4d401f",
            resolution: "1280x720",
            hasAudio: false
        )
        
        #expect(master.contains("#EXTM3U"))
        #expect(master.contains("#EXT-X-VERSION:7"))
        #expect(master.contains("#EXT-X-INDEPENDENT-SEGMENTS"))
        #expect(!master.contains("#EXT-X-MEDIA:TYPE=AUDIO"))
        #expect(master.contains(#"#EXT-X-STREAM-INF:BANDWIDTH=4000000,CODECS="avc1.4d401f",RESOLUTION=1280x720"#))
        #expect(master.contains("video.m3u8"))
    }
    
    @Test func testGenerateMasterPlaylist_4K_HEVC() {
        let master = M3U8Generator.generateMasterPlaylist(
            bandwidth: 25000000,
            codecs: "hvc1.1.6.L150.90, mp4a.40.2",
            resolution: "3840x2160",
            hasAudio: true
        )
        
        #expect(master.contains("RESOLUTION=3840x2160"))
        #expect(master.contains("BANDWIDTH=25000000"))
        #expect(master.contains(#"CODECS="hvc1.1.6.L150.90, mp4a.40.2""#))
    }
    
    @Test func testGenerateMasterPlaylist_HDR10_PQ() {
        let master = M3U8Generator.generateMasterPlaylist(
            bandwidth: 28000000,
            codecs: "hvc1.2.4.L153.B0, mp4a.40.2",
            resolution: "3840x2160",
            videoRange: "PQ",
            hasAudio: true
        )
        
        #expect(master.contains("VIDEO-RANGE=PQ"))
        #expect(master.contains("RESOLUTION=3840x2160"))
    }
    
    @Test func testGenerateMasterPlaylist_DolbyVision() {
        let master = M3U8Generator.generateMasterPlaylist(
            bandwidth: 32000000,
            codecs: "dvh1.05.06, ec-3",
            resolution: "3840x2160",
            videoRange: "PQ",
            hasAudio: true
        )
        
        #expect(master.contains(#"CODECS="dvh1.05.06, ec-3""#))
        #expect(master.contains("VIDEO-RANGE=PQ"))
        #expect(master.contains("RESOLUTION=3840x2160"))
    }
    
    @Test func testGenerateMasterPlaylist_HDCPProtection() {
        let master = M3U8Generator.generateMasterPlaylist(
            bandwidth: 35000000,
            codecs: "dvh1.08.07, ec-3",
            resolution: "3840x2160",
            videoRange: "PQ",
            hdcpLevel: "TYPE-1",
            hasAudio: true
        )
        
        #expect(master.contains("HDCP-LEVEL=TYPE-1"))
        #expect(master.contains("VIDEO-RANGE=PQ"))
    }
    
    @Test func testGenerateMasterPlaylist_DolbyVisionProfile8_SupplementalCodecs() {
        let master = M3U8Generator.generateMasterPlaylist(
            bandwidth: 30000000,
            codecs: "hvc1.2.4.L153.b0, ec-3",
            supplementalCodecs: "dvh1.08.07/db4h",
            resolution: "3840x2160",
            frameRate: "60",
            videoRange: "HLG",
            hasAudio: true
        )
        
        #expect(master.contains(#"CODECS="hvc1.2.4.L153.b0, ec-3""#))
        #expect(master.contains(#"SUPPLEMENTAL-CODECS="dvh1.08.07/db4h""#))
        #expect(master.contains("FRAME-RATE=60"))
        #expect(master.contains("VIDEO-RANGE=HLG"))
    }
    
    @Test func testGenerateMasterPlaylist_CustomAudioNameAndFrameRate() {
        let master = M3U8Generator.generateMasterPlaylist(
            bandwidth: 12000000,
            codecs: "hvc1.1.6.L150.90",
            resolution: "1920x1080",
            frameRate: "59.940",
            audioName: "Main Audio (320kbps)",
            hasAudio: true
        )
        
        #expect(master.contains(#"NAME="Main Audio (320kbps)""#))
        #expect(master.contains("FRAME-RATE=59.940"))
    }
    
    // MARK: - Multi-Variant Master Playlist Tests
    
    @Test func testGenerateMultiVariantMasterPlaylist_MultiQualityAdaptive() {
        let v4k = M3U8StreamVariant(
            bandwidth: 25000000,
            codecs: "hvc1.1.6.L150.90",
            resolution: "3840x2160",
            frameRate: "60",
            videoRange: "PQ",
            uri: "video_4k.m3u8"
        )
        let v1080p = M3U8StreamVariant(
            bandwidth: 8000000,
            codecs: "avc1.64002A",
            resolution: "1920x1080",
            frameRate: "60",
            videoRange: "SDR",
            uri: "video_1080p.m3u8"
        )
        let v720p = M3U8StreamVariant(
            bandwidth: 3000000,
            codecs: "avc1.64001F",
            resolution: "1280x720",
            frameRate: "30",
            videoRange: "SDR",
            uri: "video_720p.m3u8"
        )
        
        let master = M3U8Generator.generateMultiVariantMasterPlaylist(
            variants: [v4k, v1080p, v720p]
        )
        
        #expect(master.contains("BANDWIDTH=25000000"))
        #expect(master.contains("video_4k.m3u8"))
        #expect(master.contains("BANDWIDTH=8000000"))
        #expect(master.contains("video_1080p.m3u8"))
        #expect(master.contains("BANDWIDTH=3000000"))
        #expect(master.contains("video_720p.m3u8"))
        
        // Verify ordering: 4K must appear before 1080P, 1080P before 720P
        let idx4k = master.range(of: "video_4k.m3u8")!.lowerBound
        let idx1080p = master.range(of: "video_1080p.m3u8")!.lowerBound
        let idx720p = master.range(of: "video_720p.m3u8")!.lowerBound
        #expect(idx4k < idx1080p)
        #expect(idx1080p < idx720p)
    }
    
    @Test func testGenerateMultiVariantMasterPlaylist_EmptyVariants() {
        let master = M3U8Generator.generateMultiVariantMasterPlaylist(variants: [])
        
        #expect(master.contains("#EXTM3U"))
        #expect(!master.contains("#EXT-X-STREAM-INF"))
    }
    
    @Test func testGenerateMultiVariantMasterPlaylist_AudioPriorityChain() {
        let video = M3U8StreamVariant(
            bandwidth: 15000000,
            codecs: "hvc1.1.6.L150.90",
            resolution: "1920x1080",
            uri: "video.m3u8"
        )
        
        let dolbyAtmos = M3U8AudioVariant(
            groupID: "audio",
            name: "Dolby Atmos (E-AC3-JOC)",
            isDefault: true,
            autoSelect: true,
            uri: "audio_dolby.m3u8"
        )
        let flacHiRes = M3U8AudioVariant(
            groupID: "audio",
            name: "Hi-Res Lossless (FLAC)",
            isDefault: false,
            autoSelect: true,
            uri: "audio_flac.m3u8"
        )
        let aacStandard = M3U8AudioVariant(
            groupID: "audio",
            name: "Standard Audio (AAC)",
            isDefault: false,
            autoSelect: true,
            uri: "audio_aac.m3u8"
        )
        
        let master = M3U8Generator.generateMultiVariantMasterPlaylist(
            variants: [video],
            audioVariants: [dolbyAtmos, flacHiRes, aacStandard]
        )
        
        #expect(master.contains(#"NAME="Dolby Atmos (E-AC3-JOC)""#))
        #expect(master.contains("DEFAULT=YES"))
        #expect(master.contains(#"NAME="Hi-Res Lossless (FLAC)""#))
        #expect(master.contains(#"NAME="Standard Audio (AAC)""#))
        #expect(master.contains("DEFAULT=NO"))
    }
    
    @Test func testGenerateMultiVariantMasterPlaylist_MultiCDNFailover() {
        let primaryCDN = M3U8StreamVariant(
            bandwidth: 10000000,
            codecs: "avc1.64002A",
            resolution: "1920x1080",
            uri: "https://cdn-primary.bilivideo.com/video.m3u8"
        )
        let backupCDN = M3U8StreamVariant(
            bandwidth: 10000000,
            codecs: "avc1.64002A",
            resolution: "1920x1080",
            uri: "https://cdn-backup.bilivideo.com/video.m3u8"
        )
        
        let master = M3U8Generator.generateMultiVariantMasterPlaylist(
            variants: [primaryCDN, backupCDN]
        )
        
        #expect(master.contains("https://cdn-primary.bilivideo.com/video.m3u8"))
        #expect(master.contains("https://cdn-backup.bilivideo.com/video.m3u8"))
    }
    
    // MARK: - Segment Media Playlist Tests
    
    @Test func testGenerateSegmentPlaylist_validSidxEntries() {
        let entries = [
            SidxEntry(byteStart: 1451, byteEnd: 2045, durationSeconds: 4.200),
            SidxEntry(byteStart: 2046, byteEnd: 5120, durationSeconds: 6.500),
            SidxEntry(byteStart: 5121, byteEnd: 8192, durationSeconds: 5.100)
        ]
        
        let playlist = M3U8Generator.generateSegmentPlaylist(
            streamURI: "https://bilivideo.com/video.m4s",
            entries: entries,
            initRange: "0-932",
            indexRange: "933-1450"
        )
        
        #expect(playlist.contains("#EXTM3U"))
        #expect(playlist.contains("#EXT-X-VERSION:7"))
        // Target duration should be ceil(6.500) = 7
        #expect(playlist.contains("#EXT-X-TARGETDURATION:7"))
        #expect(playlist.contains("#EXT-X-MEDIA-SEQUENCE:0"))
        #expect(playlist.contains("#EXT-X-PLAYLIST-TYPE:VOD"))
        
        // MAP BYTERANGE should end at 1450 + 1 = 1451
        #expect(playlist.contains(#"#EXT-X-MAP:URI="https://bilivideo.com/video.m4s",BYTERANGE="1451@0""#))
        
        // Segment 1: size = 2045 - 1451 + 1 = 595
        #expect(playlist.contains("#EXTINF:4.200,"))
        #expect(playlist.contains("#EXT-X-BYTERANGE:595@1451"))
        
        // Segment 2: size = 5120 - 2046 + 1 = 3075
        #expect(playlist.contains("#EXTINF:6.500,"))
        #expect(playlist.contains("#EXT-X-BYTERANGE:3075@2046"))
        
        // Segment 3: size = 8192 - 5121 + 1 = 3072
        #expect(playlist.contains("#EXTINF:5.100,"))
        #expect(playlist.contains("#EXT-X-BYTERANGE:3072@5121"))
        
        #expect(playlist.contains("#EXT-X-ENDLIST"))
    }
    
    @Test func testGenerateSegmentPlaylist_emptyEntries() {
        let playlist = M3U8Generator.generateSegmentPlaylist(
            streamURI: "https://bilivideo.com/video.m4s",
            entries: [],
            initRange: "0-932",
            indexRange: "933-1450"
        )
        
        #expect(playlist.isEmpty)
    }
    
    @Test func testGenerateSegmentPlaylist_nilRangesFallback() {
        let entries = [
            SidxEntry(byteStart: 933, byteEnd: 2000, durationSeconds: 2.0)
        ]
        
        let playlist = M3U8Generator.generateSegmentPlaylist(
            streamURI: "https://bilivideo.com/audio.m4s",
            entries: entries,
            initRange: nil as String?,
            indexRange: nil as String?
        )
        
        // When initRange/indexRange are nil, fallback uses initEnd = 932 -> length = 933
        #expect(playlist.contains(#"#EXT-X-MAP:URI="https://bilivideo.com/audio.m4s",BYTERANGE="933@0""#))
    }
    
    // MARK: - Fallback Playlist Tests
    
    @Test func testGenerateFallbackPlaylist() {
        let playlist = M3U8Generator.generateFallbackPlaylist(
            streamURI: "video_stream.m4s",
            duration: 124.321
        )
        
        #expect(playlist.contains("#EXTM3U"))
        #expect(playlist.contains("#EXT-X-VERSION:7"))
        #expect(playlist.contains("#EXT-X-TARGETDURATION:125"))
        #expect(playlist.contains("#EXT-X-MEDIA-SEQUENCE:0"))
        #expect(playlist.contains("#EXT-X-PLAYLIST-TYPE:VOD"))
        #expect(playlist.contains(#"#EXT-X-MAP:URI="video_stream.m4s""#))
        #expect(playlist.contains("#EXTINF:124.321,"))
        #expect(playlist.contains("video_stream.m4s"))
        #expect(playlist.contains("#EXT-X-ENDLIST"))
    }
    
    // MARK: - deriveVideoProperties Tests (codec → videoRange glue logic)
    
    @Test func testDeriveVideoProperties_SDR_AVC() {
        let props = M3U8Generator.deriveVideoProperties(
            codecs: "avc1.640033",
            qualityId: 80,
            drmType: 0,
            frameRate: "30"
        )
        
        #expect(props.codecs == "avc1.640033")
        #expect(props.supplementalCodecs == nil)
        #expect(props.videoRange == nil)  // SDR → omit VIDEO-RANGE
        #expect(props.hdcpLevel == nil)
        #expect(props.frameRate == "30")
    }
    
    @Test func testDeriveVideoProperties_HDR10_byQualityId125() {
        // B站 qualityId 125 = HDR10, even if codec string doesn't start with hvc1.2
        let props = M3U8Generator.deriveVideoProperties(
            codecs: "hev1.2.4.L156.90",
            qualityId: 125,
            drmType: 0,
            frameRate: "24"
        )
        
        #expect(props.videoRange == "PQ")
        #expect(props.codecs == "hev1.2.4.L156.90")  // no rewrite
        #expect(props.supplementalCodecs == nil)
    }
    
    @Test func testDeriveVideoProperties_HDR10_byCodecPrefix() {
        let props = M3U8Generator.deriveVideoProperties(
            codecs: "hvc1.2.4.L153.B0",
            qualityId: nil,
            drmType: 0,
            frameRate: "60"
        )
        
        #expect(props.videoRange == "PQ")
        #expect(props.frameRate == "60")
    }
    
    @Test func testDeriveVideoProperties_DolbyVisionProfile5() {
        let props = M3U8Generator.deriveVideoProperties(
            codecs: "dvh1.05.06",
            qualityId: 126,
            drmType: 0,
            frameRate: "23.976"
        )
        
        #expect(props.codecs == "dvh1.05.06")  // Profile 5: no rewrite
        #expect(props.supplementalCodecs == nil)
        #expect(props.videoRange == "PQ")
    }
    
    @Test func testDeriveVideoProperties_DolbyVisionProfile8_HLG_dvh10807() {
        // dvh1.08.07 → HLG, NOT PQ (this was the P0 bug)
        let props = M3U8Generator.deriveVideoProperties(
            codecs: "dvh1.08.07",
            qualityId: 126,
            drmType: 0,
            frameRate: "24"
        )
        
        #expect(props.codecs == "hvc1.2.4.L153.b0")  // rewritten
        #expect(props.supplementalCodecs == "dvh1.08.07/db4h")
        #expect(props.videoRange == "HLG")  // ← MUST be HLG
    }
    
    @Test func testDeriveVideoProperties_DolbyVisionProfile8_HLG_dvh10803() {
        let props = M3U8Generator.deriveVideoProperties(
            codecs: "dvh1.08.03",
            qualityId: 126,
            drmType: 0,
            frameRate: "30"
        )
        
        #expect(props.codecs == "hvc1.2.4.L153.b0")
        #expect(props.supplementalCodecs == "dvh1.08.03/db4h")
        #expect(props.videoRange == "HLG")
    }
    
    @Test func testDeriveVideoProperties_DolbyVisionProfile8_PQ_dvh10806() {
        // dvh1.08.06 → PQ (different compatibility ID)
        let props = M3U8Generator.deriveVideoProperties(
            codecs: "dvh1.08.06",
            qualityId: 126,
            drmType: 0,
            frameRate: "24"
        )
        
        #expect(props.codecs == "hvc1.2.4.L150")  // different base layer
        #expect(props.supplementalCodecs == "dvh1.08.06/db1p")
        #expect(props.videoRange == "PQ")  // ← PQ for this variant
    }
    
    @Test func testDeriveVideoProperties_HDCP_whenDrmTypePositive() {
        let props = M3U8Generator.deriveVideoProperties(
            codecs: "avc1.640033",
            qualityId: 80,
            drmType: 1,
            frameRate: "30"
        )
        
        #expect(props.hdcpLevel == "TYPE-1")
    }
    
    @Test func testDeriveVideoProperties_FrameRate_clamps60fps() {
        let props = M3U8Generator.deriveVideoProperties(
            codecs: "avc1.640033",
            qualityId: 80,
            drmType: 0,
            frameRate: "120"
        )
        
        #expect(props.frameRate == "60")
    }
    
    @Test func testDeriveVideoProperties_FrameRate_defaultsTo30WhenNil() {
        let props = M3U8Generator.deriveVideoProperties(
            codecs: "avc1.640033",
            qualityId: nil,
            drmType: nil,
            frameRate: nil
        )
        
        #expect(props.frameRate == "30")
    }
}
