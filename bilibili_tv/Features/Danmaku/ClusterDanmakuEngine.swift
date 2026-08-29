import Foundation
import os

/// 弹幕合并链路日志(统一日志渠道,便于 simctl log / Console 抓取)
private let clusterLog = Logger(subsystem: "bilibili_tv", category: "DanmakuCluster")

/// 弹幕 Cluster 合并引擎(纯逻辑,不依赖 UIKit/SwiftUI,可单元测试):
/// 以"归一化文本"为桶,在 `clusterWindowSeconds`(10s)窗口内聚合相同内容弹幕。
/// **滑动续期语义**:按弹幕自身时间(而非 tick 到达时间)续期——每条新弹幕
/// 把窗口延长到最后一条的弹幕时间 + 窗口;批次处理完才按当前播放时间做
/// 最终过期检查(避免 tick 延迟返回导致的误封存)。
/// **实时前置语义**:首条立即以普通滚动弹幕发射(零延迟);第 2 条起立即
/// 前置显示静态 cluster 并随窗口内计数实时增长(showCluster → updateCluster);
/// 窗口封存后停止更新(endCluster),cluster 由渲染层按 displayTime 淡出。
/// **有界内存**:桶仅保留首条(文本/颜色)与计数,不缓存每条弹幕。
struct ClusterDanmakuEngine {
    /// 单文本聚合窗口(滑动续期,有界)
    private struct Bucket {
        /// 首条弹幕(文本/颜色来源,首条已即时滚动发射)
        let first: DanmakuProvider.Danmu
        /// 窗口内弹幕总数(含首条)
        var count: Int
        /// 最后一条弹幕时间(每次 ingest 按其时间续期,封存判定依据)
        var lastActive: TimeInterval
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

    /// 处理一批新弹幕,返回本批应执行的指令。
    /// 按弹幕时间升序聚合(续期用 danmu.time 而非 tick 时间);
    /// 批次全部处理后,再按当前播放时间封存到期窗口。
    mutating func process(newDanmus: [DanmakuProvider.Danmu], now: TimeInterval) -> [ClusterOutput] {
        var outputs: [ClusterOutput] = []
        for danmu in newDanmus.sorted(by: { $0.time < $1.time }) {
            let key = Self.normalize(danmu.text)
            if var bucket = buckets[key] {
                // 滑动续期:窗口延长到最后一条弹幕时间
                bucket.count += 1
                bucket.lastActive = max(bucket.lastActive, danmu.time)
                buckets[key] = bucket
                let cluster = ClusterDanmaku(
                    key: key,
                    text: bucket.first.text,
                    count: bucket.count,
                    color: bucket.first.color
                )
                if bucket.count == 2 {
                    clusterLog.info("cluster shown: text=\(key) count=\(bucket.count) at t=\(danmu.time)")
                    outputs.append(.showCluster(cluster))
                } else {
                    clusterLog.info("cluster updated: text=\(key) count=\(bucket.count) at t=\(danmu.time)")
                    outputs.append(.updateCluster(cluster))
                }
            } else {
                buckets[key] = Bucket(first: danmu, count: 1, lastActive: danmu.time)
                // 首条即时发射:弹幕不因合并而延迟(计数已计入该桶)
                outputs.append(.shoot(danmu))
            }
        }
        settleExpired(at: now, into: &outputs)
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

    /// 批次处理完成后,按当前播放时间封存"最后活跃后超过窗口"的桶
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
