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

/// 大端序 SIDX box 二进制构造器（ISO 14496-12，支持 version 0/1 头）
private struct SidxBoxBuilder {
    struct Reference {
        var type: UInt8 = 0
        var size: UInt32 = 0
        var duration: UInt32 = 0
    }

    var version: UInt8 = 0
    var timescale: UInt32 = 1_000
    var firstOffset: UInt64 = 0
    var references: [Reference] = []

    func build() -> Data {
        var data = Data()
        // v0 头 = size(4)+type(4)+ver/flags(4)+refID(4)+timescale(4)+EPT(4)+first_offset(4)+reserved(2)+count(2) = 32
        // v1 头 = v0 中 EPT/first_offset 各扩 64 位 → 40
        let boxSize = (version == 0 ? 32 : 40) + references.count * 12
        func append(_ bytes: [UInt8]) { data.append(contentsOf: bytes) }
        func appendUInt16(_ v: UInt16) { withUnsafeBytes(of: v.bigEndian) { data.append(contentsOf: $0) } }
        func appendUInt32(_ v: UInt32) { withUnsafeBytes(of: v.bigEndian) { data.append(contentsOf: $0) } }
        func appendUInt64(_ v: UInt64) { withUnsafeBytes(of: v.bigEndian) { data.append(contentsOf: $0) } }

        appendUInt32(UInt32(boxSize))
        append([0x73, 0x69, 0x64, 0x78])  // 'sidx'
        append([version, 0x00, 0x00, 0x00])  // version + flags
        appendUInt32(1)  // reference_ID
        appendUInt32(timescale)
        if version == 0 {
            appendUInt32(0)  // earliest_presentation_time (32-bit)
            appendUInt32(UInt32(firstOffset))  // first_offset (32-bit)
        } else {
            appendUInt64(0)  // earliest_presentation_time (64-bit)
            appendUInt64(firstOffset)  // first_offset (64-bit)
        }
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

    @Test func version1Header_uses64BitFirstOffsetAndEPT() {
        // v1 头 = 40 字节（EPT/first_offset 各 64 位）；firstOffset 超出 UInt32.max（4_294_967_295）
        // 验证 64 位分支正确读出（若误按 32 位截断,byteStart 会是 1_000）
        var builder = SidxBoxBuilder()
        builder.version = 1
        builder.firstOffset = 5_000_000_000
        builder.references = [.init(type: 0, size: 500, duration: 4_200)]
        let entries = parse(builder)

        #expect(entries.count == 1)
        #expect(entries[0].byteStart == 5_000_001_000)
        #expect(entries[0].byteEnd == 5_000_001_000 + 500 - 1)
        #expect(entries[0].durationSeconds == 4.2)
    }

    @Test func version1_firstOffsetAboveInt64Max_isRejected() {
        // first_offset = UInt64(Int64.max) + 1:Int64(bitPattern:) 会映射成负数,
        // 产生负字节区间;解析器应整体拒绝并返回空
        var builder = SidxBoxBuilder()
        builder.version = 1
        builder.firstOffset = UInt64(Int64.max) + 1
        builder.references = [.init(type: 0, size: 500, duration: 4_200)]
        let entries = parse(builder)

        #expect(entries.isEmpty)
    }

    @Test func version1_firstOffsetOverflow_mediaStartAdditionIsRejected() {
        // firstOffset == Int64.max 且 mediaStartOffset > 0:两者相加溢出 Int64,
        // 未做 checked addition 会 trap;解析器应拒绝并返回空
        var builder = SidxBoxBuilder()
        builder.version = 1
        builder.firstOffset = UInt64(Int64.max)
        builder.references = [.init(type: 0, size: 500, duration: 4_200)]
        let entries = parse(builder, mediaStartOffset: 1)

        #expect(entries.isEmpty)
    }

    @Test func zeroReferencedSize_producesEmptyByteRange() {
        var builder = SidxBoxBuilder()
        builder.references = [.init(type: 0, size: 0, duration: 1_000)]
        let entries = parse(builder)

        // size=0:byteEnd = start - 1（保留现有行为,不崩溃即可）
        #expect(entries.count == 1)
        #expect(entries[0].byteStart == 1_000)
        #expect(entries[0].byteEnd == 999)
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

    @Test func slicedDataWithNonZeroStartIndex_parsesCorrectly() {
        // Data 切片（data[start..<end]）可能携带非零 startIndex,依赖它做绝对下标会 trap;
        // 解析器应归一化后再读（回归: SidxBitReader 曾直接 data[offset]）
        var builder = SidxBoxBuilder()
        builder.references = [.init(type: 0, size: 500, duration: 4_200)]
        let box = builder.build()
        let padded = Data([0xAA, 0xBB, 0xCC, 0xDD, 0xEE]) + box  // 前置 5 字节垃圾
        let slice = padded[5..<padded.count]

        let entries = SidxParser.parse(data: slice, mediaStartOffset: 1_000)

        #expect(entries.count == 1)
        #expect(entries[0].byteStart == 1_000)
        #expect(entries[0].byteEnd == 1_499)
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
