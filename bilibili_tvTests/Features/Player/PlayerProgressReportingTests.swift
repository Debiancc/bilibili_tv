//
//  PlayerProgressReportingTests.swift
//  bilibili_tvTests
//
//  阶段三 3b：PlayerViewModel 进度上报的「时序 + 并发」测试。
//  注入 MockHistoryStore + 短心跳间隔（0.05s），断言：
//  - 心跳：.ready 后 startProgressReporting 按间隔持续上报
//  - 幂等：重复 start 不产生双倍上报（同一窗口内调用次数有界）
//  - 启停：stop 后心跳不再上报；resume 后恢复
//  - 节流：非 force 且秒数差 < 间隔时跳过（30s 节流语义）
//  - 播完：AVPlayerItemDidPlayToEndTime 通知 → 以 item.duration 标记看完
//
// 元数据直通断言见 PlayerMetadataTests。
//

import AVFoundation
import Testing

@testable import bilibili_tv

@MainActor
struct PlayerProgressReportingTests {
    /// 断言在 timeout 内某条件成立（沿用 PlayerViewModelTests 轮询模式）
    private func waitUntil(
        timeoutNanoseconds: UInt64 = 2_000_000_000,
        intervalNanoseconds: UInt64 = 10_000_000,
        _ condition: () -> Bool
    ) async {
        var elapsed: UInt64 = 0
        while !condition(), elapsed < timeoutNanoseconds {
            try? await Task.sleep(nanoseconds: intervalNanoseconds)
            elapsed += intervalNanoseconds
        }
    }

    /// 构造已就绪 VM（state=.ready + player 非 nil,startProgressReporting 才生效）
    private func makeReadyViewModel(
        historyStore: MockHistoryStore,
        heartbeatInterval: TimeInterval = 0.05,
        playbackSeconds: Double = 120
    ) -> PlayerViewModel {
        let vm = PlayerViewModel(epId: 320_665, seasonId: 33_354, heartbeatInterval: heartbeatInterval, historyStore: historyStore)
        vm.state = .ready
        vm.player = AVPlayer()
        vm.playbackTimeProvider = { playbackSeconds }
        return vm
    }

    // MARK: - 心跳启停

    @Test func heartbeat_reportsRepeatedly() async {
        let store = MockHistoryStore()
        let vm = makeReadyViewModel(historyStore: store)

        vm.startProgressReporting()
        await waitUntil { store.records.count >= 2 }

        #expect(store.records.count >= 2)
        #expect(store.records.allSatisfy { $0.progress == 120 })
        vm.stopProgressReporting()
    }

    @Test func start_isIdempotent_noDoubleHeartbeat() async {
        let store = MockHistoryStore()
        let vm = makeReadyViewModel(historyStore: store)

        vm.startProgressReporting()
        vm.startProgressReporting()
        vm.startProgressReporting()
        await waitUntil { store.records.count >= 2 }
        // 排空等待期间可能积压的心跳（CI 慢机计时器延迟可达数百 ms）
        try? await Task.sleep(nanoseconds: 100_000_000)
        // 幂等验证：比较「固定窗口内的增量」而非累计计数——CI 启动阶段计时抖动
        // 会把累计计数推过任何合理上界。单定时器 0.05s 间隔在 0.3s 窗口 ≈ 6 条；
        // 双定时器 ≈ 12+ 条，窗口增量天然放大差异。
        let baseline = store.records.count
        try? await Task.sleep(nanoseconds: 300_000_000)
        let delta = store.records.count - baseline

        #expect(delta <= 9)
        vm.stopProgressReporting()
    }

    @Test func stop_stopsHeartbeat() async {
        let store = MockHistoryStore()
        let vm = makeReadyViewModel(historyStore: store)

        vm.startProgressReporting()
        await waitUntil { store.records.count >= 1 }
        vm.stopProgressReporting(reportFinal: false)
        // 先排空 stop 前已入队、尚未执行的心跳 Task（0.05s 间隔下可能积累 1-2 条）
        try? await Task.sleep(nanoseconds: 100_000_000)
        let settledCount = store.records.count
        // 定时器已失效：后续窗口计数必须保持平稳（若仍在跑,300ms 内会再涨 ~6 条）
        try? await Task.sleep(nanoseconds: 300_000_000)

        #expect(store.records.count == settledCount)
    }

    @Test func resume_restartsHeartbeat() async {
        let store = MockHistoryStore()
        let vm = makeReadyViewModel(historyStore: store)

        vm.startProgressReporting()
        await waitUntil { store.records.count >= 1 }
        vm.stopProgressReporting(reportFinal: false)
        vm.resumeProgressReportingIfReady()
        await waitUntil { store.records.count >= 3 }

        #expect(store.records.count >= 3)
        vm.stopProgressReporting()
    }

    // MARK: - 节流（直接驱动 reportProgress，不依赖 Timer 时序）

    @Test func heartbeat_throttlesWithinInterval() {
        let store = MockHistoryStore()
        // 默认 30s 心跳（Int(interval)=30），播放位置恒定为 120：
        let vm = makeReadyViewModel(historyStore: store, heartbeatInterval: 30)

        vm.reportProgress(force: false)  // 首报：差 120 >= 30,允许
        #expect(store.records.count == 1)

        vm.reportProgress(force: false)  // 同位置：差 0 < 30,节流跳过
        #expect(store.records.count == 1)

        vm.playbackTimeProvider = { 160 }
        vm.reportProgress(force: false)  // 差 40 >= 30,再次允许
        #expect(store.records.count == 2)

        vm.reportProgress(force: true)  // force 无视节流
        #expect(store.records.count == 3)
    }

    // MARK: - 播完上报（completed）

    @Test func playToEnd_reportsItemDuration() async throws {
        let store = MockHistoryStore()
        let vm = makeReadyViewModel(historyStore: store)
        let item = StubPlayerItem(duration: CMTime(seconds: 3_600, preferredTimescale: 600))
        vm.finalPlayerItem = item

        vm.startProgressReporting()
        // 真实播放器播完时会由 AVPlayerItem 发出此通知,单测直接转发
        NotificationCenter.default.post(name: .AVPlayerItemDidPlayToEndTime, object: item)
        // 只认「播完上报」签名（progress == duration == 3_600）：心跳记录同样携带
        // duration=3_600（finalPlayerItem 已设置），仅 completed 路径会把 progress 写到 3_600
        await waitUntil { store.records.contains { $0.progress == 3_600 && $0.duration == 3_600 } }

        let completed = try #require(store.records.last { $0.progress == 3_600 && $0.duration == 3_600 })
        #expect(completed.progress == 3_600)
        vm.stopProgressReporting()
    }

    @Test func playToEnd_ignoresOtherItems() async {
        let store = MockHistoryStore()
        let vm = makeReadyViewModel(historyStore: store)
        vm.finalPlayerItem = StubPlayerItem(duration: CMTime(seconds: 3_600, preferredTimescale: 600))

        vm.startProgressReporting()
        // 其它 item 的播完通知不应触发当前剧集的 completed 上报
        // （completed 路径会以 progress=3600 上报；心跳只报 progress=120）
        let otherItem = StubPlayerItem(duration: CMTime(seconds: 3_600, preferredTimescale: 600))
        NotificationCenter.default.post(name: .AVPlayerItemDidPlayToEndTime, object: otherItem)
        try? await Task.sleep(nanoseconds: 100_000_000)

        #expect(store.records.allSatisfy { $0.progress == 120 })
        vm.stopProgressReporting()
    }
}
