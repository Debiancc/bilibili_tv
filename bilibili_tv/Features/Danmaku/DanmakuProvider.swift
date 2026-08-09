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
    /// 视频会话代际:initVideo 时递增,用于丢弃旧视频挂起请求的过期响应
    private var sessionGeneration = 0
    private var segmentDanmus: [Int: [Danmu]] = [:]
    private var segmentStatuses: [Int: Bool] = [:]
    private var segmentCursors: [Int: Int] = [:]
    /// 分段最近一次拉取失败的时间戳,用于失败后的冷却重试
    private var segmentFailedAt: [Int: TimeInterval] = [:]
    /// 分段拉取失败后的重试冷却时间(秒)
    private static let retryCooldown: TimeInterval = 5

    private var lastTime: TimeInterval = 0
    private var lastSegmentIdx: Int = 0

    private func getSegmentIdx(time: TimeInterval) -> Int {
        Int(time) / Self.segmentDuration + 1
    }

    /// 初始化/切换视频:重置全部状态并预取起始分段
    func initVideo(cid id: Int, startPos: TimeInterval) async {
        cid = id
        sessionGeneration += 1
        segmentDanmus.removeAll(keepingCapacity: true)
        segmentStatuses.removeAll(keepingCapacity: true)
        segmentCursors.removeAll(keepingCapacity: true)
        segmentFailedAt.removeAll(keepingCapacity: true)
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
        // 注意:分段内弹幕时间为相对时间(0~segmentDuration),须换算成视频绝对时间比较
        let diff = time - lastTime
        if diff > 5 || diff < 0 {
            let segmentStart = Double(sidx - 1) * Double(Self.segmentDuration)
            segmentCursors[sidx] = dms.firstIndex(where: { $0.time > time - segmentStart }) ?? dms.count
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

    /// 拉取指定分段并缓存 (失败时清状态以便冷却后重试)
    private func fetchSegment(_ idx: Int) async {
        guard let cid else { return }

        // 失败冷却:避免网络持续故障时每 tick 轮询 API
        if let failedAt = segmentFailedAt[idx],
            Date().timeIntervalSince1970 - failedAt < Self.retryCooldown
        {
            return
        }

        // 记录发起请求时的会话代际,响应返回后与当前代际比对,丢弃过期请求结果
        let requestGeneration = sessionGeneration
        let requestCid = cid
        let isCurrentSession = { [self] in requestGeneration == sessionGeneration && requestCid == self.cid }
        segmentStatuses[idx] = true
        defer {
            // 仅当会话仍有效且该分段确未缓存时清理状态,防止过期请求清掉新会话的状态
            if isCurrentSession(), segmentDanmus[idx] == nil {
                segmentStatuses[idx] = nil
            }
        }

        do {
            let data = try await BilibiliService.shared.executeData(
                urlString: "https://api.bilibili.com/x/v2/dm/list/seg.so",
                queryItems: [
                    URLQueryItem(name: "type", value: "1"),
                    URLQueryItem(name: "oid", value: "\(cid)"),
                    URLQueryItem(name: "segment_index", value: "\(idx)")
                ]
            )
            guard isCurrentSession() else {
                // 期间已切换到新视频,丢弃旧请求的结果
                return
            }
            let reply = try DmSegMobileReply(serializedBytes: data)

            let dms = reply.elems
                .filter { $0.mode <= 5 && $0.pool == 0 && $0.weight >= 4 }
                .map {
                    Danmu(
                        id: $0.id,
                        text: $0.content,
                        time: TimeInterval($0.progress) / 1_000.0,
                        mode: $0.mode,
                        fontSize: $0.fontsize,
                        color: $0.color
                    )
                }
                .sorted { $0.time < $1.time }

            segmentDanmus[idx] = dms
            segmentFailedAt[idx] = nil
            print("💬 [Danmaku] cid:\(cid) sidx:\(idx) danmu cnt: \(dms.count)")
        } catch {
            // 仅当会话仍有效时才记录失败冷却,避免过期请求抑制新会话的重试
            if isCurrentSession() {
                segmentFailedAt[idx] = Date().timeIntervalSince1970
            }
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
            Int(time) % Self.segmentDuration < Self.advancedDuration
        {
            await fetchSegment(sidx - 1)
        }

        if segmentStatuses[sidx + 1] != true,
            Self.segmentDuration - Int(time) % Self.segmentDuration < Self.advancedDuration
        {
            await fetchSegment(sidx + 1)
        }
    }
}
