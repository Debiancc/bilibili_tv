//
//  PlayerViewModelDanmakuTests.swift
//  bilibili_tvTests
//
//  阶段三 3c：PlayerViewModel 弹幕会话协调 + 应用生命周期收敛测试。
//  注入 StubDanmakuProvider（无网络）断言：
//  - 弹幕开关：默认开（UserDefaults 未设置）；setDanmakuEnabled 关闭→会话停止+持久化；再开→重启会话
//  - 启动条件：.ready + player + cid + 开关 四条件缺一不可（不满足时静默跳过）
//  - startPostLoadServices 收敛：进度上报 + 弹幕会话一并启动（cid/起播时间直通 provider）
//  - tearDownPlayer 收敛：进度心跳 / 统计监控 / 弹幕会话全部停止
//  - handleScenePhaseChange：切后台上报最终进度并停心跳；回前台恢复
//
// 注意：danmakuSessionActive 是同步计算属性（直接读 danmakuVM.sessionState），
// 无 Combine hop；但 provider.initVideo 仍经 Task 异步执行，
// 断言 initCalls 前需用 waitForInitVideo 显式等待。
//

import AVFoundation
import Foundation
import Testing

@testable import bilibili_tv

/// Stub 弹幕数据层：记录 initVideo 调用参数，不发起任何网络请求
@MainActor
final class StubDanmakuProvider: DanmakuProviding {
    struct InitCall {
        let cid: Int
        let startPos: TimeInterval
    }

    private(set) var initCalls: [InitCall] = []

    func initVideo(cid: Int, startPos: TimeInterval) async {
        initCalls.append(InitCall(cid: cid, startPos: startPos))
    }

    func playerTimeChange(time: TimeInterval) async -> [DanmakuProvider.Danmu] {
        []
    }
}

@MainActor
struct PlayerViewModelDanmakuTests {
    /// 构造 VM + Stub provider（danmakuEnabled 受 UserDefaults 影响，测试先显式置位）
    private func makeViewModel(
        epId: Int? = 320_665,
        seasonId: Int? = 33_354,
        enabled: Bool = true
    ) -> (PlayerViewModel, StubDanmakuProvider) {
        UserDefaults.standard.set(enabled, forKey: DanmakuSettingsKeys.isEnabled)
        let provider = StubDanmakuProvider()
        let vm = PlayerViewModel(
            epId: epId,
            seasonId: seasonId,
            service: MockPlayerService(),
            danmakuVM: DanmakuViewModel(provider: provider)
        )
        return (vm, provider)
    }

    /// 轮询等待 danmakuSessionActive 收敛（同步计算属性，首轮即返回）
    private func waitForDanmakuState(_ vm: PlayerViewModel, active: Bool, timeoutNanoseconds: UInt64 = 1_000_000_000) async -> Bool {
        var elapsed: UInt64 = 0
        while vm.danmakuSessionActive != active, elapsed < timeoutNanoseconds {
            try? await Task.sleep(nanoseconds: 10_000_000)
            elapsed += 10_000_000
        }
        return vm.danmakuSessionActive == active
    }

    /// 轮询等待 provider 收到 initVideo 调用（initVideo 经 Task 异步执行；
    /// 会话状态同步收敛后不再有 Combine hop 让出调度器，断言前需显式等待）
    private func waitForInitVideo(
        _ provider: StubDanmakuProvider,
        minimumCount: Int = 1,
        timeoutNanoseconds: UInt64 = 1_000_000_000
    ) async -> Bool {
        var elapsed: UInt64 = 0
        while provider.initCalls.count < minimumCount, elapsed < timeoutNanoseconds {
            try? await Task.sleep(nanoseconds: 10_000_000)
            elapsed += 10_000_000
        }
        return provider.initCalls.count >= minimumCount
    }

    /// 构造就绪态 VM（.ready + player + cid，供会话启动测试复用）
    private func makeReadyVM(
        cid: Int = 777,
        enabled: Bool = true
    ) -> (PlayerViewModel, StubDanmakuProvider) {
        let (vm, provider) = makeViewModel(enabled: enabled)
        vm.state = .ready
        vm.player = AVPlayer()
        vm.currentCid = cid
        return (vm, provider)
    }

    // MARK: - 开关状态切换（冒烟）

    @Test func danmakuEnabled_defaultsToTrue_whenKeyUnset() {
        UserDefaults.standard.removeObject(forKey: DanmakuSettingsKeys.isEnabled)
        let provider = StubDanmakuProvider()
        let vm = PlayerViewModel(
            epId: 320_665,
            seasonId: 33_354,
            service: MockPlayerService(),
            danmakuVM: DanmakuViewModel(provider: provider)
        )

        #expect(vm.danmakuEnabled == true)
    }

    @Test func setDanmakuEnabled_false_stopsSessionAndPersists() async {
        let (vm, _) = makeReadyVM()
        vm.startPostLoadServices()
        #expect(await waitForDanmakuState(vm, active: true))

        vm.setDanmakuEnabled(false)

        #expect(vm.danmakuEnabled == false)
        #expect(UserDefaults.standard.bool(forKey: DanmakuSettingsKeys.isEnabled) == false)
        #expect(await waitForDanmakuState(vm, active: false))
        #expect(vm.danmakuVM.sessionState == .idle)
    }

    @Test func setDanmakuEnabled_true_restartsSessionWhenReady() async {
        let (vm, provider) = makeReadyVM()
        vm.startPostLoadServices()
        #expect(await waitForDanmakuState(vm, active: true))

        vm.setDanmakuEnabled(false)
        #expect(await waitForDanmakuState(vm, active: false))
        let callsAfterStop = provider.initCalls.count

        // 重新开启：.ready 仍成立 → 会话重启并记录新的 initVideo 调用
        vm.setDanmakuEnabled(true)
        #expect(await waitForDanmakuState(vm, active: true))
        #expect(await waitForInitVideo(provider, minimumCount: callsAfterStop + 1))
        #expect(provider.initCalls.last?.cid == 777)
    }

    // MARK: - 启动条件（四条件缺一不可）

    @Test func setDanmakuEnabled_true_doesNotStart_whenNotReady() async {
        let (vm, provider) = makeViewModel()
        // idle 态：开关打开但未就绪 → 不启动会话
        vm.setDanmakuEnabled(true)
        try? await Task.sleep(nanoseconds: 100_000_000)

        #expect(vm.danmakuSessionActive == false)
        #expect(provider.initCalls.isEmpty)
        #expect(vm.danmakuVM.sessionState == .idle)
    }

    @Test func startPostLoadServices_skipsDanmaku_whenNoCid() async {
        let (vm, provider) = makeViewModel()
        vm.state = .ready
        vm.player = AVPlayer()
        vm.currentCid = nil

        vm.startPostLoadServices()

        #expect(vm.danmakuSessionActive == false)
        #expect(provider.initCalls.isEmpty)
    }

    @Test func startPostLoadServices_skipsDanmaku_whenDisabled() async {
        let (vm, provider) = makeReadyVM(enabled: false)

        vm.startPostLoadServices()

        #expect(vm.danmakuSessionActive == false)
        #expect(provider.initCalls.isEmpty)
    }

    // MARK: - 会话启动（startPostLoadServices 收敛）

    @Test func startPostLoadServices_startsDanmakuSession_withCidAndResumeTime() async {
        let (vm, provider) = makeReadyVM(cid: 888)
        vm.startPostLoadServices()

        #expect(await waitForDanmakuState(vm, active: true))
        // cid 与起播时间直通 provider（resumeTime 默认 0）
        #expect(await waitForInitVideo(provider))
        #expect(provider.initCalls.last?.cid == 888)
        #expect(provider.initCalls.last?.startPos == 0)
        #expect(vm.danmakuVM.sessionState == .active)
    }

    // MARK: - tearDownPlayer 收敛（3c：单点停止全部后台服务）

    @Test func tearDownPlayer_stopsDanmakuSessionAndProgress() async {
        let (vm, provider) = makeReadyVM()
        vm.startPostLoadServices()
        #expect(await waitForDanmakuState(vm, active: true))
        #expect(await waitForInitVideo(provider, minimumCount: 1))

        vm.tearDownPlayer()

        #expect(await waitForDanmakuState(vm, active: false))
        #expect(vm.danmakuVM.sessionState == .idle)
        #expect(vm.player == nil)
        #expect(vm.finalPlayerItem == nil)
    }

    // MARK: - 应用生命周期（handleScenePhaseChange 收敛）

    @Test func handleScenePhaseChange_background_reportsFinalProgress() async {
        let store = MockHistoryStore()
        let vm = PlayerViewModel(
            epId: 320_665,
            seasonId: 33_354,
            historyStore: store,
            danmakuVM: DanmakuViewModel(provider: StubDanmakuProvider())
        )
        vm.state = .ready
        vm.player = AVPlayer()
        vm.playbackTimeProvider = { 60 }

        vm.startProgressReporting()
        vm.handleScenePhaseChange(.background)

        // 切后台：上报最终进度（force）→ 立即记录一条
        #expect(store.records.last?.progress == 60)
        #expect(store.records.count == 1)
    }

    /// 心跳恢复的挂起语义：切后台 → Timer 停止；回前台（.ready）→ Timer 重新挂起。
    /// （真实 Timer 在 Swift Testing 进程不触发，此处验证挂起/恢复状态而非等待真实时序）
    @Test func handleScenePhaseChange_active_resumesHeartbeat() {
        let store = MockHistoryStore()
        let vm = PlayerViewModel(
            epId: 320_665,
            seasonId: 33_354,
            heartbeatInterval: 0.05,
            historyStore: store,
            danmakuVM: DanmakuViewModel(provider: StubDanmakuProvider())
        )
        vm.state = .ready
        vm.player = AVPlayer()
        vm.playbackTimeProvider = { 60 }

        vm.startProgressReporting()
        #expect(vm.progressReporterTimer != nil)

        vm.handleScenePhaseChange(.background)
        #expect(vm.progressReporterTimer == nil, "切后台应停心跳")

        vm.handleScenePhaseChange(.active)
        #expect(vm.progressReporterTimer != nil, "回前台应恢复心跳")

        vm.stopProgressReporting(reportFinal: false)
        #expect(vm.progressReporterTimer == nil)
    }
}
