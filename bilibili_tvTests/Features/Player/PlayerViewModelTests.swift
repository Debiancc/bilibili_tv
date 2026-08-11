//
//  PlayerViewModelTests.swift
//  bilibili_tvTests
//
//  阶段三 3a：PlayerViewModel 加载状态机（PlayerLoadState）冒烟 + 行为断言 + 并发生命周期测试。
//  注入 MockPlayerService（Result 脚本 + qn 请求序列记录），断言：
//  - idle 初始不发起请求；loading/ready 幂等（不重复请求）；failed 重试真的重新请求
//  - qn 降级精确路径：qn=120 失败时精确降到 qn=80，不跳级
//  - 无 ep/season 时 .failed 携带预期文案「缺少剧集或季度 ID，无法播放」
//  - 试看态 isPreviewOnly/purchaseHintText 的具体取值（大会员 vs 单片购买文案区分）
//  - deinit 真的触发加载 Task 取消（挂起循环 mock 断言取消后调用计数不再增长）
//
// 覆盖边界说明：DASH/MP4 的「成功到 .ready」路径依赖真实网络（sidx 预取 / loadTracks
// 均会发起 HTTP 请求），单测注入的假 URL 无法完成，故成功态由手工构造 .ready + AVPlayer()
// 在 snapshot 测试中覆盖；本文件聚焦加载失败/降级/标志位/生命周期等可离线断言的行为。
//

import AVFoundation
import Foundation
import Testing

@testable import bilibili_tv

/// Mock 播放服务：按脚本返回预置结果，记录 qn 请求序列，支持挂起直到被取消（deinit 测试用）
@MainActor
final class MockPlayerService: PlayerServicing {
    /// 兜底结果（未命中 resultsByQn 的 qn 使用）
    var playURLResult: Result<PlayURLResult, Error> = .failure(URLError(.badServerResponse))
    /// 按 qn 的脚本化结果（降级路径测试用：120 失败 / 80 空流）
    var resultsByQn: [Int: Result<PlayURLResult, Error>] = [:]
    var episodeCidResult: Result<Int?, Error> = .success(nil)
    /// 置 true 后 fetchPlayURL 挂起直到 Task 被取消（用于验证 deinit 取消）
    var hangUntilCancelled = false

    private(set) var fetchPlayURLCallCount = 0
    private(set) var requestedQns: [Int] = []
    private(set) var fetchEpisodeCidCallCount = 0
    /// 挂起循环观察到取消后置 true
    private(set) var observedCancellation = false

    func fetchPlayURL(epId: Int?, cid: Int?, seasonId: Int?, qn: Int) async throws -> PlayURLResult {
        fetchPlayURLCallCount += 1
        requestedQns.append(qn)
        if hangUntilCancelled {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000)
            }
            observedCancellation = true
            throw CancellationError()
        }
        if let scripted = resultsByQn[qn] {
            return try scripted.get()
        }
        return try playURLResult.get()
    }

    func fetchEpisodeCid(epId: Int, seasonId: Int?) async throws -> Int? {
        fetchEpisodeCidCallCount += 1
        return try episodeCidResult.get()
    }
}

@MainActor
struct PlayerViewModelTests {
    // MARK: - Fixtures

    /// loadVideo 启动后台任务后立即返回，测试需轮询等待状态机到达终态
    private func waitForTerminalState(_ vm: PlayerViewModel, timeoutSeconds: Double = 5) async {
        var polls = 0
        while polls < Int(timeoutSeconds / 0.05) {
            switch vm.state {
            case .ready, .failed:
                return
            case .idle, .loading:
                try? await Task.sleep(nanoseconds: 50_000_000)
                polls += 1
            }
        }
        Issue.record("timed out waiting for terminal state, current: \(vm.state)")
    }

    private func makeViewModel(
        epId: Int? = 320_665,
        seasonId: Int? = 33_354,
        service: MockPlayerService = MockPlayerService()
    ) -> PlayerViewModel {
        PlayerViewModel(epId: epId, seasonId: seasonId, service: service)
    }

    private func makePlayURLResult(
        isPreview: Int? = nil,
        vipStatus: Int? = nil,
        errorCode: Int? = nil,
        durl: [MP4URLItem] = []
    ) -> PlayURLResult {
        PlayURLResult(
            quality: nil, format: nil, timelength: nil, acceptFormat: nil,
            acceptDescription: nil, acceptQuality: nil,
            isDrm: nil, drmTechType: nil,
            isPreview: isPreview, hasPaid: nil, errorCode: errorCode, vipStatus: vipStatus, vipType: nil,
            dash: nil, durl: durl, cid: nil
        )
    }

    private func makeDurlSegment() -> MP4URLItem {
        MP4URLItem(order: 1, length: 360_000, size: 1_000, url: "https://example.com/v.mp4", backupUrl: nil)
    }

    // MARK: - 冒烟：idle 初始态

    @Test func idleState_doesNotIssueRequest() async {
        let service = MockPlayerService()
        let vm = makeViewModel(service: service)

        #expect(vm.state == .idle)
        #expect(vm.player == nil)
        #expect(vm.finalPlayerItem == nil)
        #expect(vm.isPreviewOnly == false)
        #expect(vm.purchaseHintText == nil)
        #expect(service.fetchPlayURLCallCount == 0)
    }

    // MARK: - 空流：加载到构造 playerItem 环节失败

    @Test func load_emptyStreams_failsWithExpectedMessage() async {
        let service = MockPlayerService()
        service.playURLResult = .success(makePlayURLResult())
        let vm = makeViewModel(service: service)

        await vm.loadVideo()
        await waitForTerminalState(vm)

        #expect(vm.state == .failed(message: "无法解析播放流（可能需要大会员或 CDN 鉴权失败）"))
        // 空流时仅发起一次 qn=120 请求（无降级）
        #expect(service.requestedQns == [120])
        #expect(service.fetchPlayURLCallCount == 1)
        // playerItem 构造失败，不进入 cid 兜底解析
        #expect(service.fetchEpisodeCidCallCount == 0)
    }

    // MARK: - qn 降级精确路径（120 失败 → 精确降到 80，不跳级）

    @Test func load_qn120Failure_fallsBackExactlyToQn80() async {
        let service = MockPlayerService()
        // 脚本：qn=120 抛错 → 触发降级；qn=80 返回空流 → 在 playerItem 构造处失败
        service.resultsByQn = [
            120: .failure(URLError(.timedOut)),
            80: .success(makePlayURLResult())
        ]
        let vm = makeViewModel(service: service)

        await vm.loadVideo()
        await waitForTerminalState(vm)

        // 请求序列必须精确是 [120, 80]：先试最高档，失败后精确降一档
        #expect(service.requestedQns == [120, 80])
        #expect(vm.state == .failed(message: "无法解析播放流（可能需要大会员或 CDN 鉴权失败）"))
    }

    @Test func load_qn80AlsoFails_secondErrorWins() async {
        let service = MockPlayerService()
        // qn=120 与 qn=80 都失败：最终以 qn=80 的错误进入 failed（与旧实现一致：降级错误直接上抛）
        service.playURLResult = .failure(URLError(.notConnectedToInternet))
        let vm = makeViewModel(service: service)

        await vm.loadVideo()
        await waitForTerminalState(vm)

        #expect(service.requestedQns == [120, 80])
        #expect(vm.state == .failed(message: URLError(.notConnectedToInternet).localizedDescription))
    }

    // MARK: - 缺 id 不请求

    @Test func load_whenMissingBothIds_failsWithExpectedMessage() async {
        let service = MockPlayerService()
        let vm = makeViewModel(epId: nil, seasonId: nil, service: service)

        await vm.loadVideo()
        await waitForTerminalState(vm)

        #expect(vm.state == .failed(message: "缺少剧集或季度 ID，无法播放"))
        #expect(service.fetchPlayURLCallCount == 0)
    }

    // MARK: - 试看态标志位与文案

    @Test func load_previewOnly_nonVipUser_hintIsPurchaseOrVip() async {
        let service = MockPlayerService()
        service.playURLResult = .success(makePlayURLResult(isPreview: 1, durl: [makeDurlSegment()]))
        let vm = makeViewModel(service: service)

        await vm.loadVideo()
        await waitForTerminalState(vm)

        // 流在播放器构造处失败（假 URL 无法加载），但标志位已在 fetch 后立即设置
        #expect(vm.isPreviewOnly == true)
        #expect(vm.purchaseHintText == "观看全片需购买或开通大会员")
        guard case .failed = vm.state else {
            Issue.record("expected failed state, got \(vm.state)")
            return
        }
    }

    @Test func load_previewOnly_vipUser_hintIsPurchaseOnly() async {
        let service = MockPlayerService()
        service.playURLResult = .success(makePlayURLResult(isPreview: 1, vipStatus: 1, durl: [makeDurlSegment()]))
        let vm = makeViewModel(service: service)

        await vm.loadVideo()
        await waitForTerminalState(vm)

        #expect(vm.isPreviewOnly == true)
        #expect(vm.purchaseHintText == "观看全片需购买本片")
    }

    // MARK: - 失败后重试真的重新发起请求

    @Test func load_afterFailure_retryReissuesRequests() async {
        let service = MockPlayerService()
        service.playURLResult = .failure(URLError(.timedOut))
        let vm = makeViewModel(service: service)

        await vm.loadVideo()
        await waitForTerminalState(vm)
        #expect(vm.state == .failed(message: URLError(.timedOut).localizedDescription))
        #expect(service.fetchPlayURLCallCount == 2)

        // 第二次重试：qn=120 / qn=80 全部重新请求
        service.playURLResult = .failure(URLError(.timedOut))
        await vm.loadVideo()
        await waitForTerminalState(vm)

        #expect(vm.state == .failed(message: URLError(.timedOut).localizedDescription))
        #expect(service.fetchPlayURLCallCount == 4)
        #expect(service.requestedQns == [120, 80, 120, 80])
    }

    // MARK: - 幂等守卫

    @Test func load_whenLoading_doesNotReissueRequest() async {
        let service = MockPlayerService()
        let vm = makeViewModel(service: service)
        vm.state = .loading

        await vm.loadVideo()

        #expect(vm.state == .loading)
        #expect(service.fetchPlayURLCallCount == 0)
    }

    @Test func load_whenReady_doesNotReissueRequest() async {
        let service = MockPlayerService()
        let vm = makeViewModel(service: service)
        vm.state = .ready
        vm.player = AVPlayer()

        await vm.loadVideo()

        #expect(vm.state == .ready)
        #expect(service.fetchPlayURLCallCount == 0)
    }

    // MARK: - tearDownPlayer 释放播放器资源

    @Test func tearDownPlayer_releasesPlayerAndItem() {
        let vm = makeViewModel()
        vm.state = .ready
        vm.player = AVPlayer()

        vm.tearDownPlayer()

        #expect(vm.player == nil)
        #expect(vm.finalPlayerItem == nil)
    }

    // MARK: - 并发/生命周期：deinit 真的触发加载 Task 取消

    @Test func deinit_cancelsInFlightLoadTask() async {
        let service = MockPlayerService()
        service.hangUntilCancelled = true
        var vm: PlayerViewModel? = makeViewModel(service: service)
        weak var weakVM = vm
        let task = Task { await weakVM?.loadVideo() }

        // 等待请求真正发出（挂起在 mock 的取消感知循环中）
        var polls = 0
        while service.fetchPlayURLCallCount == 0, polls < 200 {
            try? await Task.sleep(nanoseconds: 5_000_000)
            polls += 1
        }
        #expect(service.fetchPlayURLCallCount == 1)

        // 释放 VM：deinit 必须取消正在进行的加载 Task
        vm = nil
        try? await Task.sleep(nanoseconds: 100_000_000)

        // 取消生效：挂起循环退出并观察到取消
        #expect(service.observedCancellation == true)
        // 取消后不再有后续调用
        #expect(service.fetchPlayURLCallCount == 1)
        #expect(service.requestedQns == [120])

        await task.value
    }
}
