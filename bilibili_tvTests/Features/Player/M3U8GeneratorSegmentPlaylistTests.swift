import Foundation
import Testing

@testable import bilibili_tv

struct M3U8GeneratorSegmentPlaylistTests {
    @Test func testGenerateSegmentPlaylist_validSidxEntries() {
        let entries = [
            SidxEntry(byteStart: 1_451, byteEnd: 2_045, durationSeconds: 4.200),
            SidxEntry(byteStart: 2_046, byteEnd: 5_120, durationSeconds: 6.500),
            SidxEntry(byteStart: 5_121, byteEnd: 8_192, durationSeconds: 5.100)
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
            SidxEntry(byteStart: 933, byteEnd: 2_000, durationSeconds: 2.0)
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
}
