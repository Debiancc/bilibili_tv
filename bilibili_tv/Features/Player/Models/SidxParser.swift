import Foundation

// 从 sidx Box 解析出的精确分片信息
struct SidxEntry {
    let byteStart: Int64
    let byteEnd: Int64
    let durationSeconds: Double
}

/// sidx 二进制解析器（ISO 14496-12）：纯计算核心，不依赖 AVFoundation / 网络 / UI
enum SidxParser {
    /// 解析 sidx box，返回媒体段（reference_type=0）的字节区间条目
    static func parse(data: Data, mediaStartOffset: Int64) -> [SidxEntry] {
        guard data.count >= 28 else {
            print("⚠️ [sidx] Data too small: \(data.count) bytes")
            return []
        }
        var reader = SidxBitReader(data: data)

        let boxSize = reader.readUInt32()
        let boxType = reader.readUInt32()

        // 期望是 'sidx' (0x73696478)
        guard boxType == 0x7369_6478 else {
            print("⚠️ [sidx] Unexpected box type: \(String(format: "%08X", boxType)), expected sidx(0x73696478). boxSize=\(boxSize)")
            return []
        }

        let version = reader.readUInt8()
        reader.skip(3)  // flags
        reader.skip(4)  // reference_ID
        let timescale = reader.readUInt32()

        var firstOffset: Int64 = 0
        if version == 0 {
            reader.skip(4)  // earliest_presentation_time (32-bit)
            firstOffset = Int64(reader.readUInt32())  // first_offset (32-bit)
        } else {
            reader.skip(8)  // earliest_presentation_time (64-bit)
            firstOffset = Int64(bitPattern: reader.readUInt64())  // first_offset (64-bit)
        }

        reader.skip(2)  // reserved (2 bytes)
        let referenceCount = reader.readUInt16()  // ✅ 正确：2 字节，不是 4 字节！

        print("🔬 [sidx] version=\(version) timescale=\(timescale) firstOffset=\(firstOffset) referenceCount=\(referenceCount) mediaStart=\(mediaStartOffset)")

        return parseSidxReferences(
            reader: &reader,
            count: Int(referenceCount),
            timescale: timescale,
            mediaStart: mediaStartOffset + firstOffset
        )
    }

    /// 遍历 reference 表,把媒体段 (reference_type=0) 组装为字节区间条目
    private static func parseSidxReferences(
        reader: inout SidxBitReader,
        count: Int,
        timescale: UInt32,
        mediaStart: Int64
    ) -> [SidxEntry] {
        // 媒体数据实际起始字节
        var currentByteOffset = mediaStart
        var entries: [SidxEntry] = []

        for i in 0..<count {
            guard reader.offset + 12 <= reader.data.count else { break }

            let referenceInfo = reader.readUInt32()
            let referenceType = (referenceInfo >> 31) & 1
            let referencedSize = Int64(referenceInfo & 0x7FFF_FFFF)
            let subsegmentDuration = reader.readUInt32()
            reader.skip(4)  // SAP info

            if referenceType == 0 {  // 0 = media segment (1 = index segment，跳过)
                let durationSeconds = timescale > 0 ? Double(subsegmentDuration) / Double(timescale) : 0
                if i < 3 {
                    print(
                        // swiftlint:disable:next line_length
                        "   sidx[\(i)] size=\(referencedSize) dur=\(subsegmentDuration)/\(timescale)=\(String(format: "%.2f", durationSeconds))s start=\(currentByteOffset)"
                    )
                }
                entries.append(
                    SidxEntry(
                        byteStart: currentByteOffset,
                        byteEnd: currentByteOffset + referencedSize - 1,
                        durationSeconds: durationSeconds
                    ))
            } else {
                print("   sidx[\(i)] SKIPPED (reference_type=1 index segment, size=\(referencedSize))")
            }
            // type-1 引用同样占据字节空间,必须推进偏移,否则后续 type-0 条目起点错位
            currentByteOffset += referencedSize
        }
        return entries
    }
}

/// sidx 二进制读取器:大端序顺序读取 + 跳过,越界返回 0 保持解析韧性
private struct SidxBitReader {
    let data: Data
    var offset = 0

    mutating func readUInt8() -> UInt8 {
        guard offset < data.count else { return 0 }
        defer { offset += 1 }
        return data[offset]
    }
    mutating func readUInt16() -> UInt16 {
        guard offset + 2 <= data.count else { return 0 }
        defer { offset += 2 }
        return data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt16.self).bigEndian }
    }
    mutating func readUInt32() -> UInt32 {
        guard offset + 4 <= data.count else { return 0 }
        defer { offset += 4 }
        return data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self).bigEndian }
    }
    mutating func readUInt64() -> UInt64 {
        guard offset + 8 <= data.count else { return 0 }
        defer { offset += 8 }
        return data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt64.self).bigEndian }
    }
    mutating func skip(_ count: Int) {
        offset = min(offset + count, data.count)
    }
}
