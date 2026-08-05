import Foundation
import SwiftProtobuf

/// 弹幕数据层:拉取 seg.so protobuf 分段弹幕、基础过滤、分段缓存与预取
/// 参照 ATV-Bilibili-demo VideoDanmuProvider 逻辑 (PGC-only:仅 seg.so 数据源,不含 UP 主弹幕)
@MainActor
final class DanmakuProvider {
    struct Danmu {
        let id: Int64
        let text: String
        /// 弹幕出现位置(秒)
        let time: TimeInterval
        let mode: Int32
        let fontSize: Int32
        let color: UInt32
    }

    /// 每个弹幕分段的时长:6 分钟
    static let segmentDuration = 60 * 6
    /// 提前加载相邻分段的时间窗口:30 秒
    private static let advancedDuration = 30

    private var cid: Int?
    private var segmentDanmus: [Int: [Danmu]] = [:]
    private var segmentStatuses: [Int: Bool] = [:]
    private var segmentCursors: [Int: Int] = [:]

    private var lastTime: TimeInterval = 0
    private var lastSegmentIdx: Int = 0

    private func getSegmentIdx(time: TimeInterval) -> Int {
        Int(time) / Self.segmentDuration + 1
    }

    /// 初始化/切换视频:重置全部状态并预取起始分段
    func initVideo(cid id: Int, startPos: TimeInterval) async {
        cid = id
        segmentDanmus.removeAll(keepingCapacity: true)
        segmentStatuses.removeAll(keepingCapacity: true)
        segmentCursors.removeAll(keepingCapacity: true)
        lastTime = 0
        lastSegmentIdx = 0

        let startSegment = getSegmentIdx(time: startPos)
        await fetchSegment(startSegment)
    }

    /// 播放进度回调:按需拉取/预取分段,返回当前应发射的弹幕列表
    func playerTimeChange(time: TimeInterval) async -> [Danmu] {
        guard cid != nil else { return [] }

        await fetchMoreInBackground(time: time)

        let sidx = getSegmentIdx(time: time)
        guard let dms = segmentDanmus[sidx] else { return [] }

        // seek 检测:时间回退或跳变 > 5s 时,游标重置到目标时间点
        let diff = time - lastTime
        if diff > 5 || diff < 0 {
            segmentCursors[sidx] = dms.firstIndex(where: { $0.time > time }) ?? dms.count
        } else if sidx == lastSegmentIdx + 1 {
            segmentCursors[sidx] = 0
        }
        lastTime = time
        lastSegmentIdx = sidx

        var result: [Danmu] = []
        var cursor = segmentCursors[sidx] ?? 0
        while cursor < dms.count {
            let dm = dms[cursor]
            guard dm.time < time else { break }
            cursor += 1
            result.append(dm)
        }
        segmentCursors[sidx] = cursor
        return result
    }

    /// 拉取指定分段并缓存 (失败时清状态以便下次重试)
    private func fetchSegment(_ idx: Int) async {
        guard let cid else { return }
        segmentStatuses[idx] = true
        defer { if segmentDanmus[idx] == nil { segmentStatuses[idx] = nil } }

        do {
            let data = try await BilibiliService.shared.executeData(
                urlString: "https://api.bilibili.com/x/v2/dm/list/seg.so",
                queryItems: [
                    URLQueryItem(name: "type", value: "1"),
                    URLQueryItem(name: "oid", value: "\(cid)"),
                    URLQueryItem(name: "segment_index", value: "\(idx)")
                ]
            )
            let reply = try DmSegMobileReply(serializedBytes: data)

            let dms = reply.elems
                .filter { $0.mode <= 5 && $0.pool == 0 && $0.weight >= 4 }
                .map {
                    Danmu(
                        id: $0.id,
                        text: $0.content,
                        time: TimeInterval($0.progress) / 1000.0,
                        mode: $0.mode,
                        fontSize: $0.fontsize,
                        color: $0.color
                    )
                }
                .sorted { $0.time < $1.time }

            segmentDanmus[idx] = dms
            print("💬 [Danmaku] cid:\(cid) sidx:\(idx) danmu cnt: \(dms.count)")
        } catch {
            print("⚠️ [Danmaku] cid:\(cid) sidx:\(idx) fetch failed: \(error.localizedDescription)")
        }
    }

    /// 分段预取:当前段缺失立即拉取;临近段交界 30s 窗口内预取前后段
    private func fetchMoreInBackground(time: TimeInterval) async {
        let sidx = getSegmentIdx(time: time)

        if segmentStatuses[sidx] != true {
            await fetchSegment(sidx)
        }

        if sidx > 1,
           segmentStatuses[sidx - 1] != true,
           Int(time) % Self.segmentDuration < Self.advancedDuration {
            await fetchSegment(sidx - 1)
        }

        if segmentStatuses[sidx + 1] != true,
           Self.segmentDuration - Int(time) % Self.segmentDuration < Self.advancedDuration {
            await fetchSegment(sidx + 1)
        }
    }
}
