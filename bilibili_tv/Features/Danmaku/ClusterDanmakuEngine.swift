import Foundation

/// 弹幕 Cluster 合并引擎(纯逻辑,不依赖 UIKit/SwiftUI,可单元测试):
/// 以"归一化文本"为桶,在 `clusterWindowSeconds`(30s)窗口内聚合相同内容弹幕。
/// 首条出现**立即**以普通滚动弹幕发射(零延迟,同时计入窗口计数);
/// 窗口内重复弹幕缓冲;窗口到期封存时:计数 ≥ `clusterMinCount` → 发射静态 cluster,
/// 低于阈值 → 缓冲条(首条除外,已即时发射)按到达顺序回放为普通滚动弹幕。
struct ClusterDanmakuEngine {
    /// 单文本 30s 聚合窗口
    private struct Bucket {
        /// 窗口起始时间(首条出现时间)
        let start: TimeInterval
        /// 窗口内全部弹幕(到达顺序天然有序,追加即可)
        var occurrences: [ClusterOccurrence]
    }

    /// 窗口内单条弹幕
    struct ClusterOccurrence {
        let time: TimeInterval
        let danmu: DanmakuProvider.Danmu
    }

    /// 引擎产出的发射指令(互斥,消费方 switch 分发)
    enum ClusterOutput {
        /// 低于阈值的窗口回放:按到达顺序补发为普通滚动弹幕
        case shoot(DanmakuProvider.Danmu)
        /// 窗口封存:发射静态 cluster
        case shootCluster(ClusterDanmaku)
    }

    /// 静态 cluster 展示数据(计数已封存)
    struct ClusterDanmaku {
        /// 展示文本:窗口内首条原始文本(未归一化)
        let text: String
        /// 窗口内总条数(含首条)
        let count: Int
        /// 展示颜色:首条颜色
        let color: UInt32
    }

    /// 活跃桶:存在即窗口开启(互斥性由字典存在性表达,无布尔拼凑)
    private var buckets: [String: Bucket] = [:]

    /// 处理一批新弹幕(按播放时间升序),返回本批应发射的指令。
    /// 先封存到期窗口,再逐条聚合:首条立即发射(零延迟),重复条缓冲。
    mutating func process(newDanmus: [DanmakuProvider.Danmu], now: TimeInterval) -> [ClusterOutput] {
        var outputs: [ClusterOutput] = []
        settleExpired(at: now, into: &outputs)
        for danmu in newDanmus {
            let key = Self.normalize(danmu.text)
            if var bucket = buckets[key] {
                bucket.occurrences.append(ClusterOccurrence(time: danmu.time, danmu: danmu))
                buckets[key] = bucket
            } else {
                buckets[key] = Bucket(start: now, occurrences: [ClusterOccurrence(time: danmu.time, danmu: danmu)])
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

    /// 封存所有 `now - start ≥ 窗口` 的桶:按阈值发射 cluster 或回放滚动弹幕
    private mutating func settleExpired(at now: TimeInterval, into outputs: inout [ClusterOutput]) {
        let expiredKeys =
            buckets
            .filter { now >= $0.value.start + DanmakuDefaults.clusterWindowSeconds }
            .map(\.key)
        for key in expiredKeys {
            guard let bucket = buckets.removeValue(forKey: key), let first = bucket.occurrences.first else {
                continue
            }
            let count = bucket.occurrences.count
            if count >= DanmakuDefaults.clusterMinCount {
                outputs.append(
                    .shootCluster(
                        ClusterDanmaku(text: first.danmu.text, count: count, color: first.danmu.color)
                    ))
            } else {
                // 低于阈值:首条已即时发射,只回放首条之后的缓冲条
                for occurrence in bucket.occurrences.dropFirst() {
                    outputs.append(.shoot(occurrence.danmu))
                }
            }
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
