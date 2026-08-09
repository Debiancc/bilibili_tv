//
//  LogoTrimmingProcessorTests.swift
//  bilibili_tvTests
//
//  Tests for LogoTrimmingProcessor and UIImage.trimmingTransparentPixels(),
//  covering the transparent-pixel bounding box detection, threshold behavior,
//  the "negligible crop" bail-out, and Kingfisher ImageProcessor conformance.
//

import Kingfisher
import Testing
import UIKit

@testable import bilibili_tv

struct LogoTrimmingProcessorTests {
    // MARK: - Test Helpers

    /// Builds a UIImage with a precisely controlled per-pixel alpha channel, using
    /// the same premultipliedLast RGBA byte layout that `trimmingTransparentPixels()`
    /// itself uses internally, so tests are not subject to color-management rounding.
    private func makeTestImage(width: Int, height: Int, scale: CGFloat = 1.0, alphaAt: (Int, Int) -> UInt8) -> UIImage {
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixelData = [UInt8](repeating: 0, count: height * bytesPerRow)

        for y in 0..<height {
            for x in 0..<width {
                let idx = y * bytesPerRow + x * bytesPerPixel
                let a = alphaAt(x, y)
                pixelData[idx + 0] = a  // R (premultiplied, use same value as alpha)
                pixelData[idx + 1] = 0  // G
                pixelData[idx + 2] = 0  // B
                pixelData[idx + 3] = a  // A
            }
        }

        let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        let cgImage = context.makeImage()!
        return UIImage(cgImage: cgImage, scale: scale, orientation: .up)
    }

    // MARK: - trimmingTransparentPixels() core behavior

    @Test func cropsToOpaqueContentBoundingBox() {
        // 100x100 canvas, fully opaque 50x50 block at x:[20,70), y:[30,80)
        let image = makeTestImage(width: 100, height: 100) { x, y in
            (20..<70).contains(x) && (30..<80).contains(y) ? 255 : 0
        }

        let result = image.trimmingTransparentPixels()

        #expect(result != nil)
        #expect(result !== image)
        #expect(result?.cgImage?.width == 50)
        #expect(result?.cgImage?.height == 50)
    }

    @Test func singlePixelContent_returnsOriginalUnchanged() {
        // Only one qualifying pixel means minX == maxX (or minY == maxY),
        // which fails the `minX < maxX, minY < maxY` guard.
        let image = makeTestImage(width: 10, height: 10) { x, y in
            (x == 5 && y == 5) ? 255 : 0
        }

        let result = image.trimmingTransparentPixels()

        #expect(result === image)
    }

    @Test func fullyTransparentImage_returnsOriginalUnchanged() {
        let image = makeTestImage(width: 10, height: 10) { _, _ in 0 }

        let result = image.trimmingTransparentPixels()

        #expect(result === image)
    }

    @Test func defaultThreshold_excludesBoundaryAlphaAndIncludesAboveThreshold() {
        // Background exactly at the default threshold (10) should NOT qualify (`> alphaThreshold`),
        // while an inner block one unit above threshold (11) should be detected precisely.
        let image = makeTestImage(width: 20, height: 20) { x, y in
            if (5..<15).contains(x) && (5..<15).contains(y) {
                return 11
            }
            return 10
        }

        let result = image.trimmingTransparentPixels()

        #expect(result !== image)
        #expect(result?.cgImage?.width == 10)
        #expect(result?.cgImage?.height == 10)
    }

    @Test func customAlphaThreshold_excludesPixelsBelowGivenThreshold() {
        // A block of alpha=150 would normally qualify under the default threshold (10),
        // but with an explicit threshold of 200 no pixel qualifies, so the whole image
        // is returned unchanged (no bounding box found at all).
        let image = makeTestImage(width: 10, height: 10) { x, y in
            (2..<8).contains(x) && (2..<8).contains(y) ? 150 : 0
        }

        let result = image.trimmingTransparentPixels(alphaThreshold: 200)

        #expect(result === image)
    }

    @Test func negligibleCrop_returnsOriginalWhenContentCoversMoreThanNinetyFivePercent() {
        // Opaque region covers 99x99 out of 100x100 (98.01%), which is above the
        // 95% "not worth cropping" bail-out threshold.
        let image = makeTestImage(width: 100, height: 100) { x, y in
            (x < 99 && y < 99) ? 255 : 0
        }

        let result = image.trimmingTransparentPixels()

        #expect(result === image)
    }

    @Test func preservesScaleOfOriginalImage() {
        let image = makeTestImage(width: 100, height: 100, scale: 2.0) { x, y in
            (20..<70).contains(x) && (30..<80).contains(y) ? 255 : 0
        }

        let result = image.trimmingTransparentPixels()

        #expect(result?.scale == 2.0)
    }

    @Test func imageWithoutCGImage_returnsSameInstance() {
        let emptyImage = UIImage()

        let result = emptyImage.trimmingTransparentPixels()

        #expect(result === emptyImage)
    }

    // MARK: - LogoTrimmingProcessor (Kingfisher ImageProcessor conformance)

    @Test func processorIdentifier_matchesExpectedValue() {
        let processor = LogoTrimmingProcessor()
        #expect(processor.identifier == "com.bilibili.logo-trimming")
    }

    @Test func process_withImageItem_returnsTrimmedImage() {
        let image = makeTestImage(width: 100, height: 100) { x, y in
            (20..<70).contains(x) && (30..<80).contains(y) ? 255 : 0
        }
        let processor = LogoTrimmingProcessor()
        let options = KingfisherParsedOptionsInfo([])

        let result = processor.process(item: .image(image), options: options)

        #expect(result != nil)
        #expect(result?.cgImage?.width == 50)
        #expect(result?.cgImage?.height == 50)
    }

    @Test func process_withValidDataItem_returnsTrimmedImage() {
        let image = makeTestImage(width: 100, height: 100) { x, y in
            (20..<70).contains(x) && (30..<80).contains(y) ? 255 : 0
        }
        guard let pngData = image.pngData() else {
            Issue.record("Failed to generate PNG data for test fixture")
            return
        }
        let processor = LogoTrimmingProcessor()
        let options = KingfisherParsedOptionsInfo([])

        let result = processor.process(item: .data(pngData), options: options)

        #expect(result != nil)
        #expect(result?.cgImage?.width == 50)
        #expect(result?.cgImage?.height == 50)
    }

    @Test func process_withInvalidDataItem_returnsNil() {
        let processor = LogoTrimmingProcessor()
        let options = KingfisherParsedOptionsInfo([])
        let garbageData = Data([0x00, 0x01, 0x02, 0x03])

        let result = processor.process(item: .data(garbageData), options: options)

        #expect(result == nil)
    }
}
