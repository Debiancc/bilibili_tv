import Foundation
import Testing

@testable import bilibili_tv

/// ClusterDanmakuEngine / ClusterFontScaler 行为契约测试。
/// 引擎为纯逻辑(无 UIKit),可直接构造 DanmakuProvider.Danmu 驱动 process。
@MainActor
struct ClusterDanmakuEngineTests {
    private func makeDanmu(_ text: String, at time: TimeInterval) -> DanmakuProvider.Danmu {
        DanmakuProvider.Danmu(
            id: Int64(time * 10),
            text: text,
            time: time,
            mode: 1,
            fontSize: 25,
            color: 0xFFFFFF
        )
    }

    private func describe(_ output: ClusterDanmakuEngine.ClusterOutput) -> String {
        switch output {
        case .shoot(let d):
            return "shoot(\(d.text))"
        case .showCluster(let cluster):
            return "show(\(cluster.text))x\(cluster.count)"
        case .updateCluster(let cluster):
            return "update(\(cluster.text))x\(cluster.count)"
        case .endCluster(let key):
            return "end(\(key))"
        }
    }

    // MARK: - 首条即时发射

    @Test func firstOccurrence_emitsImmediately() {
        var engine = ClusterDanmakuEngine()
        let outputs = engine.process(newDanmus: [makeDanmu("test", at: 0)], now: 0)
        #expect(outputs.map(describe) == ["shoot(test)"])
    }

    // MARK: - 第 2 条前置显示 cluster

    @Test func secondOccurrence_showsClusterWithCount2() {
        var engine = ClusterDanmakuEngine()
        var outputs = engine.process(newDanmus: [makeDanmu("test", at: 0)], now: 0)
        outputs += engine.process(newDanmus: [makeDanmu("test", at: 1)], now: 1)
        #expect(outputs.map(describe) == ["shoot(test)", "show(test)x2"])
    }

    // MARK: - 第 3+ 条实时更新计数

    @Test func furtherOccurrences_updateClusterCount() {
        var engine = ClusterDanmakuEngine()
        var outputs = engine.process(newDanmus: [makeDanmu("test", at: 0)], now: 0)
        outputs += engine.process(newDanmus: [makeDanmu("test", at: 1)], now: 1)
        outputs += engine.process(newDanmus: [makeDanmu("test", at: 2)], now: 2)
        outputs += engine.process(newDanmus: [makeDanmu("test", at: 3)], now: 3)
        #expect(outputs.map(describe) == ["shoot(test)", "show(test)x2", "update(test)x3", "update(test)x4"])
    }

    // MARK: - 滑动续期:窗口内新弹幕不封存,最后活跃后 10s 才封存

    @Test func slidingWindow_renewsOnEachOccurrence() {
        var engine = ClusterDanmakuEngine()
        var outputs = engine.process(newDanmus: [makeDanmu("test", at: 0)], now: 0)
        // 第 2 条在 t=9(距首条 9s,未超 10s 窗口)
        outputs += engine.process(newDanmus: [makeDanmu("test", at: 9)], now: 9)
        #expect(outputs.map(describe) == ["shoot(test)", "show(test)x2"])
        // t=19(距上次 10s 整,未超;引擎按 >= 判定,19 未达 9+10=19 边界 → 不封存)
        outputs += engine.process(newDanmus: [makeDanmu("test", at: 18)], now: 18)
        #expect(outputs.map(describe) == ["shoot(test)", "show(test)x2", "update(test)x3"])
        // 最后活跃 t=18,t=28 封存(18+10)
        outputs += engine.process(newDanmus: [], now: 28)
        #expect(outputs.map(describe) == ["shoot(test)", "show(test)x2", "update(test)x3", "end(test)"])
    }

    // MARK: - 无续期时窗口按最后活跃封存

    @Test func windowClosesAfterInactivity() {
        var engine = ClusterDanmakuEngine()
        var outputs = engine.process(newDanmus: [makeDanmu("test", at: 0)], now: 0)
        outputs += engine.process(newDanmus: [makeDanmu("test", at: 1)], now: 1)
        // t=11:距最后活跃 10s → 封存
        outputs += engine.process(newDanmus: [], now: 11)
        #expect(outputs.map(describe) == ["shoot(test)", "show(test)x2", "end(test)"])
    }

    // MARK: - 封存后同文本再来 → 新桶、首条立即发射

    @Test func afterWindowCloses_sameTextStartsNewBucket() {
        var engine = ClusterDanmakuEngine()
        var outputs = engine.process(newDanmus: [makeDanmu("test", at: 0)], now: 0)
        outputs += engine.process(newDanmus: [makeDanmu("test", at: 1)], now: 1)
        outputs += engine.process(newDanmus: [], now: 11)  // 封存
        outputs += engine.process(newDanmus: [makeDanmu("test", at: 12)], now: 12)  // 新桶首条
        #expect(outputs.map(describe) == ["shoot(test)", "show(test)x2", "end(test)", "shoot(test)"])
    }

    // MARK: - reset 清空窗口

    @Test func reset_clearsAllBuckets() {
        var engine = ClusterDanmakuEngine()
        _ = engine.process(newDanmus: [makeDanmu("test", at: 0)], now: 0)
        _ = engine.process(newDanmus: [makeDanmu("test", at: 1)], now: 1)
        engine.reset()
        let outputs = engine.process(newDanmus: [makeDanmu("test", at: 2)], now: 2)
        // reset 后同文本重新从首条开始
        #expect(outputs.map(describe) == ["shoot(test)"])
    }

    // MARK: - 归一化

    @Test func normalize_trimsAndCollapsesWhitespace() {
        #expect(ClusterDanmakuEngine.normalize("  a   b  ") == "a b")
        #expect(ClusterDanmakuEngine.normalize("a") == "a")
        #expect(ClusterDanmakuEngine.normalize("  ").isEmpty)
    }

    @Test func normalize_isCaseSensitive() {
        var engine = ClusterDanmakuEngine()
        var outputs = engine.process(newDanmus: [makeDanmu("GG", at: 0)], now: 0)
        // "gg" 与 "GG" 视为不同文本:各自独立首条
        outputs += engine.process(newDanmus: [makeDanmu("gg", at: 1)], now: 1)
        #expect(outputs.map(describe) == ["shoot(GG)", "shoot(gg)"])
    }

    @Test func normalize_mergesWhitespaceVariants() {
        var engine = ClusterDanmakuEngine()
        var outputs = engine.process(newDanmus: [makeDanmu("来了", at: 0)], now: 0)
        outputs += engine.process(newDanmus: [makeDanmu(" 来了 ", at: 1)], now: 1)
        #expect(outputs.map(describe) == ["shoot(来了)", "show(来了)x2"])
    }

    // MARK: - 同批多条

    @Test func sameBatch_multipleDanmuAreProcessedIndependently() {
        var engine = ClusterDanmakuEngine()
        let outputs = engine.process(
            newDanmus: [makeDanmu("a", at: 0), makeDanmu("b", at: 0), makeDanmu("a", at: 0)],
            now: 0
        )
        // a 首条 shoot、b 首条 shoot、a 第 2 条 show
        #expect(outputs.map(describe) == ["shoot(a)", "shoot(b)", "show(a)x2"])
    }
}

/// ClusterFontScaler 契约测试:单调、钳制、与基础字号关系
struct ClusterFontScalerTests {
    @Test func fontSize_increasesMonotonicallyWithCount() {
        var previous: CGFloat = 0
        for count in 1...200 {
            let size = ClusterFontScaler.fontSize(base: 33, count: count)
            #expect(size >= previous)
            previous = size
        }
    }

    @Test func fontSize_clampsBetweenBaseAndDoubleBase() {
        #expect(ClusterFontScaler.fontSize(base: 33, count: 1) >= 33)
        #expect(ClusterFontScaler.fontSize(base: 33, count: 10_000) <= 66)
        #expect(ClusterFontScaler.fontSize(base: 33, count: 10_000) == 66)
    }

    @Test func fontSize_count2IsLargerThanBase() {
        let baseSize = ClusterFontScaler.fontSize(base: 33, count: 1)
        let count2Size = ClusterFontScaler.fontSize(base: 33, count: 2)
        #expect(count2Size > baseSize)
    }

    @Test func fontSize_scalesLinearlyWithBase() {
        let size33 = ClusterFontScaler.fontSize(base: 33, count: 10)
        let size41 = ClusterFontScaler.fontSize(base: 41, count: 10)
        // 与基础字号等比例(rounded 后允许 ±1pt)
        #expect(abs(size41 / 41 - size33 / 33) < 0.1)
    }
}
