import Foundation
import Testing

@testable import bilibili_tv

struct M3U8GeneratorMasterPlaylistTests {
    @Test func testGenerateMasterPlaylist_withAudioTrack() {
        let master = M3U8Generator.generateMasterPlaylist(
            bandwidth: 9_403_729,
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
            bandwidth: 4_000_000,
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
            bandwidth: 25_000_000,
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
            bandwidth: 28_000_000,
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
            bandwidth: 32_000_000,
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
            bandwidth: 35_000_000,
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
            bandwidth: 30_000_000,
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
            bandwidth: 12_000_000,
            codecs: "hvc1.1.6.L150.90",
            resolution: "1920x1080",
            frameRate: "59.940",
            audioName: "Main Audio (320kbps)",
            hasAudio: true
        )

        #expect(master.contains(#"NAME="Main Audio (320kbps)""#))
        #expect(master.contains("FRAME-RATE=59.940"))
    }
}
