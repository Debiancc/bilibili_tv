import Foundation
import Testing

@testable import bilibili_tv

struct M3U8GeneratorMultiVariantTests {
    @Test func testGenerateMultiVariantMasterPlaylist_MultiQualityAdaptive() throws {
        let v4k = M3U8StreamVariant(
            bandwidth: 25_000_000,
            codecs: "hvc1.1.6.L150.90",
            resolution: "3840x2160",
            frameRate: "60",
            videoRange: "PQ",
            uri: "video_4k.m3u8"
        )
        let v1080p = M3U8StreamVariant(
            bandwidth: 8_000_000,
            codecs: "avc1.64002A",
            resolution: "1920x1080",
            frameRate: "60",
            videoRange: "SDR",
            uri: "video_1080p.m3u8"
        )
        let v720p = M3U8StreamVariant(
            bandwidth: 3_000_000,
            codecs: "avc1.64001F",
            resolution: "1280x720",
            frameRate: "30",
            videoRange: "SDR",
            uri: "video_720p.m3u8"
        )

        let master = M3U8Generator.generateMultiVariantMasterPlaylist(
            variants: [v1080p, v4k, v720p]
        )

        #expect(master.contains("BANDWIDTH=25000000"))
        #expect(master.contains("video_4k.m3u8"))
        #expect(master.contains("BANDWIDTH=8000000"))
        #expect(master.contains("video_1080p.m3u8"))
        #expect(master.contains("BANDWIDTH=3000000"))
        #expect(master.contains("video_720p.m3u8"))

        // 生成器不重排 variant，保持调用方传入顺序
        let idx1080p = try #require(master.range(of: "video_1080p.m3u8")).lowerBound
        let idx4k = try #require(master.range(of: "video_4k.m3u8")).lowerBound
        let idx720p = try #require(master.range(of: "video_720p.m3u8")).lowerBound
        #expect(idx1080p < idx4k)
        #expect(idx4k < idx720p)
    }

    @Test func testGenerateMultiVariantMasterPlaylist_EmptyVariants() {
        let master = M3U8Generator.generateMultiVariantMasterPlaylist(variants: [])

        #expect(master.contains("#EXTM3U"))
        #expect(!master.contains("#EXT-X-STREAM-INF"))
    }

    @Test func testGenerateMultiVariantMasterPlaylist_AudioPriorityChain() {
        let video = M3U8StreamVariant(
            bandwidth: 15_000_000,
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
            bandwidth: 10_000_000,
            codecs: "avc1.64002A",
            resolution: "1920x1080",
            uri: "https://cdn-primary.bilivideo.com/video.m3u8"
        )
        let backupCDN = M3U8StreamVariant(
            bandwidth: 10_000_000,
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
}
