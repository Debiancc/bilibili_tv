import Foundation
import Testing

@testable import bilibili_tv

struct M3U8GeneratorDeriveVideoPropertiesTests {
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
