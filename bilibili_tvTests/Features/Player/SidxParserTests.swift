//
//  SidxParserTests.swift
//  bilibili_tvTests
//
//  Regression tests for `SidxParser`:
//  - byte-offset advancement must be monotonic even when type-1 (index)
//    references are skipped (previous bug: b02aab0)
//  - type-1 references must NOT create media segments
//  - byte ranges (start + size - 1) must be exact
//
//  Pure computation: no AVPlayer / AVAsset / network required.
//

import Foundation
import Testing

@testable import bilibili_tv

/// 大端序 SIDX box 二进制构造器（ISO 14496-12 sidx version 0）
private struct SidxBoxBuilder {
    struct Reference {
        var type: UInt8 = 0
        var size: UInt32 = 0
        var duration: UInt32 = 0
    }

    var timescale: UInt32 = 1_000
    var firstOffset: UInt32 = 0
    var references: [Reference] = []

    func build() -> Data {
        var data = Data()
        let boxSize = 32 + references.count * 12
        func append(_ bytes: [UInt8]) { data.append(contentsOf: bytes) }
        func appendUInt16(_ v: UInt16) { withUnsafeBytes(of: v.bigEndian) { data.append(contentsOf: $0) } }
        func appendUInt32(_ v: UInt32) { withUnsafeBytes(of: v.bigEndian) { data.append(contentsOf: $0) } }

        appendUInt32(UInt32(boxSize))
        append([0x73, 0x69, 0x64, 0x78])  // 'sidx'
        append([0x00, 0x00, 0x00, 0x00])  // version 0 + flags
        appendUInt32(1)  // reference_ID
        appendUInt32(timescale)
        appendUInt32(0)  // earliest_presentation_time (32-bit)
        appendUInt32(firstOffset)
        appendUInt16(0)  // reserved
        appendUInt16(UInt16(references.count))
        for ref in references {
            appendUInt32((UInt32(ref.type) << 31) | ref.size)
            appendUInt32(ref.duration)
            appendUInt32(0)  // SAP info
        }
        return data
    }
}

struct SidxParserTests {
    private func parse(_ builder: SidxBoxBuilder, mediaStartOffset: Int64 = 1_000) -> [SidxEntry] {
        SidxParser.parse(data: builder.build(), mediaStartOffset: mediaStartOffset)
    }

    // MARK: - 正常引用:type-0 → type-0

    @Test func twoMediaSegments_offsetsAdvanceCorrectly() {
        var builder = SidxBoxBuilder()
        builder.references = [
            .init(type: 0, size: 500, duration: 4_200),
            .init(type: 0, size: 300, duration: 6_500)
        ]
        let entries = parse(builder)

        #expect(entries.count == 2)
        #expect(entries[0].byteStart == 1_000)
        #expect(entries[0].byteEnd == 1_000 + 500 - 1)
        #expect(entries[0].durationSeconds == 4.2)
        // 第二个段从第一个段结束的下一字节开始
        #expect(entries[1].byteStart == 1_500)
        #expect(entries[1].byteEnd == 1_500 + 300 - 1)
        #expect(entries[1].durationSeconds == 6.5)
    }

    @Test func multipleReferences_allByteRangesExact() {
        var builder = SidxBoxBuilder()
        builder.references = [
            .init(type: 0, size: 100, duration: 1_000),
            .init(type: 0, size: 200, duration: 2_000),
            .init(type: 0, size: 400, duration: 4_000)
        ]
        let entries = parse(builder, mediaStartOffset: 0)

        #expect(entries.count == 3)
        let expected = [
            (start: Int64(0), end: Int64(99)),
            (start: Int64(100), end: Int64(299)),
            (start: Int64(300), end: Int64(699))
        ]
        for (entry, exp) in zip(entries, expected) {
            #expect(entry.byteStart == exp.start)
            #expect(entry.byteEnd == exp.end)
        }
    }

    @Test func mediaStartOffsetAndFirstOffset_bothApplied() {
        var builder = SidxBoxBuilder()
        builder.firstOffset = 50
        builder.references = [.init(type: 0, size: 100, duration: 1_000)]
        let entries = parse(builder, mediaStartOffset: 2_000)

        // mediaStart = mediaStartOffset + firstOffset
        #expect(entries[0].byteStart == 2_050)
        #expect(entries[0].byteEnd == 2_149)
    }

    // MARK: - 混合引用:type-1 必须推进偏移但不产生条目

    @Test func type1ThenType0_indexSegmentAdvancesOffset() {
        var builder = SidxBoxBuilder()
        builder.references = [
            .init(type: 1, size: 100, duration: 0),  // index segment
            .init(type: 0, size: 500, duration: 4_200)
        ]
        let entries = parse(builder)

        // 仅一个媒体段，且起点 = mediaStart + type-1 的大小
        #expect(entries.count == 1)
        #expect(entries[0].byteStart == 1_100)
        #expect(entries[0].byteEnd == 1_100 + 500 - 1)
    }

    @Test func type0ThenType1ThenType0_offsetAdvancesThroughMiddleIndex() {
        var builder = SidxBoxBuilder()
        builder.references = [
            .init(type: 0, size: 300, duration: 3_000),
            .init(type: 1, size: 150, duration: 0),
            .init(type: 0, size: 200, duration: 2_000)
        ]
        let entries = parse(builder)

        #expect(entries.count == 2)
        #expect(entries[0].byteStart == 1_000)
        #expect(entries[0].byteEnd == 1_000 + 300 - 1)
        // 第二个媒体段起点 = 1000 + 300 + 150（跳过 type-1 的字节空间）
        #expect(entries[1].byteStart == 1_450)
        #expect(entries[1].byteEnd == 1_450 + 200 - 1)
    }

    @Test func type1ThenType1ThenType0_consecutiveIndexSegments() {
        var builder = SidxBoxBuilder()
        builder.references = [
            .init(type: 1, size: 80, duration: 0),
            .init(type: 1, size: 120, duration: 0),
            .init(type: 0, size: 400, duration: 4_000)
        ]
        let entries = parse(builder)

        #expect(entries.count == 1)
        #expect(entries[0].byteStart == 1_000 + 80 + 120)
        #expect(entries[0].byteEnd == 1_200 - 1 + 400)
    }

    @Test func type1Only_noMediaSegments() {
        var builder = SidxBoxBuilder()
        builder.references = [.init(type: 1, size: 1_000, duration: 0)]
        let entries = parse(builder)

        #expect(entries.isEmpty)
    }

    // MARK: - 边界情况

    @Test func zeroReferencedSize_producesSingleByteRange() {
        var builder = SidxBoxBuilder()
        builder.references = [.init(type: 0, size: 0, duration: 1_000)]
        let entries = parse(builder)

        // size=0:byteEnd = start - 1（保留现有行为,不崩溃即可）
        #expect(entries.count == 1)
        #expect(entries[0].byteStart == 1_000)
    }

    @Test func zeroReferencedSize_type1_thenMedia() {
        var builder = SidxBoxBuilder()
        builder.references = [
            .init(type: 1, size: 0, duration: 0),
            .init(type: 0, size: 300, duration: 3_000)
        ]
        let entries = parse(builder)

        #expect(entries.count == 1)
        #expect(entries[0].byteStart == 1_000)
    }

    @Test func emptyReferences_returnsEmpty() {
        let entries = parse(SidxBoxBuilder())
        #expect(entries.isEmpty)
    }

    @Test func truncatedData_returnsEmpty() {
        var builder = SidxBoxBuilder()
        builder.references = [.init(type: 0, size: 100, duration: 1_000)]
        let full = builder.build()
        let truncated = full.prefix(full.count - 5)

        let entries = SidxParser.parse(data: Data(truncated), mediaStartOffset: 0)
        // 头部 32 字节完整,但 reference 表不足 12 字节,循环守卫提前退出
        #expect(entries.isEmpty)
    }

    @Test func dataTooSmall_returnsEmpty() {
        let entries = SidxParser.parse(data: Data([0x00, 0x01, 0x02]), mediaStartOffset: 0)
        #expect(entries.isEmpty)
    }

    @Test func wrongBoxType_returnsEmpty() {
        var builder = SidxBoxBuilder()
        builder.references = [.init(type: 0, size: 100, duration: 1_000)]
        var full = builder.build()
        full[4] = 0x66  // 改写 'sidx' 为其他 box type

        let entries = SidxParser.parse(data: full, mediaStartOffset: 0)
        #expect(entries.isEmpty)
    }

    // MARK: - 不变量:偏移单调性

    @Test func offsetsAreMonotonic_acrossMixedReferences() {
        var builder = SidxBoxBuilder()
        builder.references = [
            .init(type: 1, size: 50, duration: 0),
            .init(type: 0, size: 200, duration: 2_000),
            .init(type: 1, size: 30, duration: 0),
            .init(type: 0, size: 100, duration: 1_000),
            .init(type: 0, size: 250, duration: 2_500)
        ]
        let entries = parse(builder)

        #expect(entries.count == 3)
        var previousStart: Int64?
        for entry in entries {
            if let prev = previousStart {
                #expect(entry.byteStart >= prev)
            }
            #expect(entry.byteEnd >= entry.byteStart - 1)
            previousStart = entry.byteStart
        }
        #expect(entries[0].byteStart == 1_050)
        #expect(entries[1].byteStart == 1_280)
        #expect(entries[2].byteStart == 1_380)
    }
}
