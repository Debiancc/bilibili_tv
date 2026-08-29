import Foundation
import os

/// 弹幕合并链路日志(统一日志渠道,便于 simctl log / Console 抓取)
private let clusterLog = Logger(subsystem: "bilibili_tv", category: "DanmakuCluster")

/// 弹幕 Cluster 合并引擎(纯逻辑,不依赖 UIKit/SwiftUI,可单元测试):
/// 以"归一化文本"为桶,在 `clusterWindowSeconds`(10s)窗口内聚合相同内容弹幕。
/// **滑动续期语义**:每次新弹幕到达续期窗口(最后活跃后 10s 无新弹幕才封存),
/// 刷屏期间 cluster 持续增长不断裂。
/// **实时前置语义**:首条立即以普通滚动弹幕发射(零延迟);第 2 条起立即
/// 前置显示静态 cluster 并随窗口内计数实时增长(showCluster → updateCluster);
/// 窗口封存后停止更新(endCluster),cluster 由渲染层按 displayTime 淡出。
struct ClusterDanmakuEngine {
    /// 单文本聚合窗口(滑动续期)
    private struct Bucket {
        /// 窗口起始时间(首条出现时间)
        let start: TimeInterval
        /// 最后一条弹幕到达时间(每次 ingest 续期,封存判定依据)
        var lastActive: TimeInterval
        /// 窗口内全部弹幕(到达顺序天然有序,追加即可)
        var occurrences: [ClusterOccurrence]
    }

    /// 窗口内单条弹幕
    struct ClusterOccurrence {
        let time: TimeInterval
        let danmu: DanmakuProvider.Danmu
    }

    /// 引擎产出的指令(互斥,消费方 switch 分发)
    enum ClusterOutput {
        /// 首条:普通滚动弹幕(零延迟)
        case shoot(DanmakuProvider.Danmu)
        /// 第 2 条:前置创建静态 cluster(计数从 2 起实时增长)
        case showCluster(ClusterDanmaku)
        /// 第 3+ 条:更新已在轨 cluster 的计数
        case updateCluster(ClusterDanmaku)
        /// 窗口封存:停止增长,渲染层按 displayTime 淡出
        case endCluster(key: String)
    }

    /// cluster 展示数据(实时语义:count 为当前窗口内累计)
    struct ClusterDanmaku {
        /// 匹配键(归一化文本)
        let key: String
        /// 展示文本:窗口内首条原始文本(未归一化)
        let text: String
        /// 窗口内当前总条数(含首条)
        let count: Int
        /// 展示颜色:首条颜色
        let color: UInt32
    }

    /// 活跃桶:存在即窗口开启(互斥性由字典存在性表达,无布尔拼凑)
    private var buckets: [String: Bucket] = [:]

    /// 处理一批新弹幕(按播放时间升序),返回本批应执行的指令。
    /// 先封存到期窗口,再逐条聚合:
    /// 首条 → shoot(滚动);第 2 条 → showCluster;第 3+ 条 → updateCluster。
    mutating func process(newDanmus: [DanmakuProvider.Danmu], now: TimeInterval) -> [ClusterOutput] {
        var outputs: [ClusterOutput] = []
        settleExpired(at: now, into: &outputs)
        for danmu in newDanmus {
            let key = Self.normalize(danmu.text)
            if var bucket = buckets[key] {
                bucket.occurrences.append(ClusterOccurrence(time: danmu.time, danmu: danmu))
                // 滑动续期:最后活跃时间更新为当前,窗口从最后一条起算
                bucket.lastActive = now
                buckets[key] = bucket
                let count = bucket.occurrences.count
                let cluster = ClusterDanmaku(
                    key: key,
                    text: bucket.occurrences[0].danmu.text,
                    count: count,
                    color: bucket.occurrences[0].danmu.color
                )
                if count == 2 {
                    clusterLog.info("cluster shown: text=\(key) count=\(count) at t=\(danmu.time)")
                    outputs.append(.showCluster(cluster))
                } else {
                    clusterLog.info("cluster updated: text=\(key) count=\(count) at t=\(danmu.time)")
                    outputs.append(.updateCluster(cluster))
                }
            } else {
                buckets[key] = Bucket(
                    start: now,
                    lastActive: now,
                    occurrences: [ClusterOccurrence(time: danmu.time, danmu: danmu)]
                )
                // 首条即时发射:弹幕不因合并而延迟(计数已计入该桶)
                outputs.append(.shoot(danmu))
            }
        }
        return outputs
    }

    /// 清空全部窗口(seek 清屏/会话结束时调用,与 DanmakuView.clean 语义一致)
    mutating func reset() {
        buckets.removeAll()
    }

    /// 文本归一化:trim 首尾空白 + 内部连续空白折叠为单空格;区分大小写
    static func normalize(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    // MARK: - 私有

    /// 封存所有 `最后活跃后超过窗口` 的桶:停止该文本的计数更新(滑动续期语义)
    private mutating func settleExpired(at now: TimeInterval, into outputs: inout [ClusterOutput]) {
        let expiredKeys =
            buckets
            .filter { now >= $0.value.lastActive + DanmakuDefaults.clusterWindowSeconds }
            .map(\.key)
        for key in expiredKeys {
            buckets.removeValue(forKey: key)
            clusterLog.info("cluster window closed: text=\(key)")
            outputs.append(.endCluster(key: key))
        }
    }
}

/// cluster 主文本字号缩放(对数式,连续单调,上下限钳制):
/// scale = clamp(0.9 + 0.12 × log₂(count), 1.0, clusterMaxScale)
enum ClusterFontScaler {
    static func fontSize(base: CGFloat, count: Int) -> CGFloat {
        let countValue = max(CGFloat(count), 1)
        let scale = min(
            DanmakuDefaults.clusterMaxScale,
            max(1.0, 0.9 + 0.12 * log2(countValue))
        )
        return (base * scale).rounded()
    }
}
