//
//  BannerVideoControllerTests.swift
//  bilibili_tvTests
//
//  轮播横幅背景视频控制器的生命周期测试（注入 Mock 取流服务，全程无网络）：
//  - 区间残缺/倒置/nil focus：守卫跳过，不发取流请求
//  - load 幂等：同 focus 且在加载中不重复取流；不同 focus 重新取流；.failed 同 focus 可重试
//  - teardown 真的取消在途取流 Task
//  - deinit 兜底真的取消在途取流 Task（未走 teardown 就释放 controller 的路径）
//
// 覆盖边界说明：createPlayer 的「成功到 .playing」路径依赖真实视频资产（loadTracks 会
// 发起 HTTP 请求），单测注入的假 URL 无法完成；本文件用不可解析 URL 让 createPlayer
// 快速走 fail() 分支，聚焦可离线断言的取流/生命周期行为。

import Foundation
import Testing

@testable import bilibili_tv

/// Mock 取流服务：支持挂起直到被取消（teardown/deinit 测试用）与失败脚本
@MainActor
final class MockBannerVideoService: BannerVideoServicing {
    /// 置 true 后 fetchBannerPreviewURL 挂起直到 Task 被取消
    var hangUntilCancelled = false
    /// 取流失败脚本：非 nil 时抛出
    var fetchError: Error?

    private(set) var callCount = 0
    /// 挂起循环观察到取消后置 true
    private(set) var observedCancellation = false
    private(set) var requestedKeys: [String] = []

    func fetchBannerPreviewURL(epId: Int?, cid: Int?, seasonId: Int?, qn: Int) async throws -> String {
        callCount += 1
        requestedKeys.append("\(epId ?? -1)-\(cid ?? -1)-\(seasonId ?? -1)")
        if hangUntilCancelled {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000)
            }
            observedCancellation = true
            throw CancellationError()
        }
        if let fetchError {
            throw fetchError
        }
        // 不可解析 URL：createPlayer 立即 fail()，避免真实网络请求
        return "not a valid url"
    }
}

@MainActor
struct BannerVideoControllerTests {
    private func makeFocus(epId: Int = 1, cid: Int = 2, seasonId: Int = 3) -> PlayFocus {
        PlayFocus(playStime: 0, playEtime: 30, cid: cid, epid: epId, seasonId: seasonId)
    }

    /// 轮询等待条件成立（默认 2s 超时），@autoclosure 每次求值
    private func waitUntil(
        _ condition: @autoclosure () -> Bool,
        timeoutNanoseconds: UInt64 = 2_000_000_000
    ) async {
        var polls = 0
        while !condition(), polls < Int(timeoutNanoseconds / 5_000_000) {
            try? await Task.sleep(nanoseconds: 5_000_000)
            polls += 1
        }
    }

    // MARK: - load 守卫

    @Test func load_withoutPlayableRange_staysIdle_noNetwork() {
        let service = MockBannerVideoService()
        let controller = BannerVideoController(service: service)

        // 区间残缺(仅一端)
        controller.load(PlayFocus(playStime: 0, playEtime: nil))
        #expect(controller.phase == .idle)

        // 区间倒置(end <= start)
        controller.load(PlayFocus(playStime: 30, playEtime: 30))
        #expect(controller.phase == .idle)

        // nil focus
        controller.load(nil)
        #expect(controller.phase == .idle)

        #expect(service.callCount == 0)
    }

    @Test func load_sameFocusWhileLoading_doesNotReissue() async {
        let service = MockBannerVideoService()
        service.hangUntilCancelled = true
        let controller = BannerVideoController(service: service)
        let focus = makeFocus()

        controller.load(focus)
        await waitUntil(service.callCount == 1)

        // 幂等守卫：同 focus 且仍在加载 → 不发第二次取流
        controller.load(focus)
        await waitUntil(service.callCount >= 2, timeoutNanoseconds: 300_000_000)
        #expect(service.callCount == 1)

        controller.teardown()
        await waitUntil(service.observedCancellation)
        #expect(service.observedCancellation)
    }

    @Test func load_differentFocus_reissues() async {
        let service = MockBannerVideoService()
        let controller = BannerVideoController(service: service)

        controller.load(makeFocus(epId: 1))
        await waitUntil(service.callCount == 1)
        controller.load(makeFocus(epId: 2))
        await waitUntil(service.callCount == 2)

        #expect(service.callCount == 2)
        #expect(service.requestedKeys == ["1-2-3", "2-2-3"])
    }

    @Test func load_sameFocusAfterFailure_retries() async {
        let service = MockBannerVideoService()
        service.fetchError = URLError(.badServerResponse)
        let controller = BannerVideoController(service: service)
        let focus = makeFocus()

        controller.load(focus)
        await waitUntil(controller.phase == .failed)
        #expect(service.callCount == 1)

        // .failed 态同 focus 允许重试（网络恢复路径）
        controller.load(focus)
        await waitUntil(service.callCount == 2)
        #expect(service.callCount == 2)
        #expect(controller.phase == .failed)
    }

    // MARK: - teardown / deinit 取消

    @Test func teardown_cancelsInFlightLoadTask() async {
        let service = MockBannerVideoService()
        service.hangUntilCancelled = true
        let controller = BannerVideoController(service: service)

        controller.load(makeFocus())
        await waitUntil(service.callCount == 1)

        controller.teardown()
        await waitUntil(service.observedCancellation)

        #expect(service.observedCancellation)
        #expect(service.callCount == 1)
        #expect(controller.phase == .idle)
    }

    @Test func deinit_cancelsInFlightLoadTask() async {
        let service = MockBannerVideoService()
        service.hangUntilCancelled = true
        var controller: BannerVideoController? = BannerVideoController(service: service)

        controller?.load(makeFocus())
        await waitUntil(service.callCount == 1)

        // 未走 teardown 直接释放：deinit 必须取消在途取流 Task
        controller = nil
        await waitUntil(service.observedCancellation)

        #expect(service.observedCancellation)
        #expect(service.callCount == 1)
    }
}
