//
//  PlayURLModelTests.swift
//  bilibili_tvTests
//
//  Regression tests for `PlayURLResult.isPreviewOnly`:
//  - `has_paid: false` must NOT mark a stream as preview-only (free content
//    also reports has_paid=false, per documented PGC responses)
//  - Only `is_preview: 1` or `error_code: -10403` indicate a preview stream
//

import Foundation
import Testing

@testable import bilibili_tv

struct PlayURLModelTests {
    private func decode(_ json: String) throws -> PlayURLResult {
        try JSONDecoder().decode(PlayURLResponse.self, from: Data(json.utf8)).activeResult!
    }

    @Test func playableFreeContent_hasPaidFalse_isNotPreviewOnly() throws {
        // Documented successful PGC response: is_preview=0, has_paid=false, nonempty durl
        let result = try decode(
            """
            {
                "code": 0,
                "message": "success",
                "result": {
                    "is_preview": 0,
                    "has_paid": false,
                    "error_code": 0,
                    "durl": [{"order": 1, "length": 360000, "size": 1000, "url": "https://example.com/v.mp4"}]
                }
            }
            """)

        #expect(result.isPreviewOnly == false)
    }

    @Test func previewStream_isPreview1_isPreviewOnly() throws {
        let result = try decode(
            """
            {
                "code": 0,
                "message": "success",
                "result": {
                    "is_preview": 1,
                    "has_paid": false,
                    "error_code": -10403,
                    "durl": [{"order": 1, "length": 360193, "size": 1000, "url": "https://example.com/v.mp4"}]
                }
            }
            """)

        #expect(result.isPreviewOnly == true)
    }

    @Test func previewStream_errorCode10403_isPreviewOnly() throws {
        let result = try decode(
            """
            {
                "code": 0,
                "message": "success",
                "result": {
                    "is_preview": 0,
                    "has_paid": false,
                    "error_code": -10403,
                    "durl": [{"order": 1, "length": 360193, "size": 1000, "url": "https://example.com/v.mp4"}]
                }
            }
            """)

        #expect(result.isPreviewOnly == true)
    }
}
