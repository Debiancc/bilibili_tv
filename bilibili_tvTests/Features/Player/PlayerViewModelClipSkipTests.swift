//
//  PlayerViewModelClipSkipTests.swift
//  bilibili_tvTests
//
//  ⏭️ 跳过片头/片尾（clip_info_list 消费）行为断言测试。
//  生产路径由 periodic time observer（每秒）+ Timer（每秒倒计时）驱动，
//  两者在 Swift Testing 进程均不可靠触发，故测试直接驱动
//  evaluateClipSkipPrompt(at:) / tickClipSkipCountdown() 做确定性断言：
//  - 播放进入剪辑区间（片头 0~26s / 片尾 1864~1936s）→ 弹提示 + 满额倒计时 5s
//  - 倒计时每秒递减；暂停中暂停倒计时（不自动跳转）；归零自动跳过
//  - 用户点击「跳过」立即 seek 到片段终点；跳过后同区间不再重复提示
//  - 播放离开片段区间（手动 seek）→ 撤销提示
//  - teardown 清空提示
//

import AVFoundation
import Foundation
import Testing

@testable import bilibili_tv

@MainActor
struct PlayerViewModelClipSkipTests {
    private static let opClip = ClipInfo(
        materialNo: 0, start: 0, end: 26, clipType: "CLIP_TYPE_OP", toastText: "即将跳过片头"
    )
    private static let edClip = ClipInfo(
        materialNo: 0, start: 1_864, end: 1_936, clipType: "CLIP_TYPE_ED", toastText: nil
    )

    /// 构造 ready 态 VM：监控/倒计时所需的 player 与状态就位
    private func makeReadyViewModel(
        clipInfoList: [ClipInfo] = [],
        playing: Bool = true
    ) -> PlayerViewModel {
        let vm = PlayerViewModel(epId: 320_665, seasonId: 33_354)
        vm.state = .ready
        vm.player = AVPlayer()
        vm.clipInfoList = clipInfoList
        vm.playerIsPlayingProvider = { playing }
        return vm
    }

    // MARK: - 数据透传

    @Test func load_playResultWithClipInfo_populatesClipInfoList() async {
        let service = MockPlayerService()
        service.playURLResult = .success(
            PlayURLResult(
                isPreview: nil, dash: nil, durl: [MP4URLItem(order: 1, url: "https://example.com/v.mp4")],
                clipInfoList: [Self.opClip]
            )
        )
        let vm = PlayerViewModel(epId: 320_665, seasonId: 33_354, service: service)
        await vm.loadVideo()
        await waitForTerminalState(vm)

        // 即使后续 playerItem 构造失败（假 URL），clipInfoList 也在 fetch 成功后立即设置
        #expect(vm.clipInfoList == [Self.opClip])
    }

    @Test func load_playResultWithoutClipInfo_keepsEmptyList() async {
        let service = MockPlayerService()
        service.playURLResult = .success(
            PlayURLResult(
                isPreview: nil, dash: nil, durl: [MP4URLItem(order: 1, url: "https://example.com/v.mp4")]
            )
        )
        let vm = PlayerViewModel(epId: 320_665, seasonId: 33_354, service: service)
        await vm.loadVideo()
        await waitForTerminalState(vm)

        #expect(vm.clipInfoList.isEmpty)
    }

    // MARK: - 提示出现/不出现

    @Test func evaluateClipSkip_insideOpRange_showsPromptWithFullCountdown() {
        let vm = makeReadyViewModel(clipInfoList: [Self.opClip])

        vm.evaluateClipSkipPrompt(at: 5)

        #expect(vm.clipSkipPrompt?.clip == Self.opClip)
        #expect(vm.clipSkipPrompt?.secondsRemaining == PlayerViewModel.clipSkipCountdownSeconds)
    }

    @Test func evaluateClipSkip_outsideAllClipRanges_noPrompt() {
        let vm = makeReadyViewModel(clipInfoList: [Self.opClip, Self.edClip])

        vm.evaluateClipSkipPrompt(at: 100)

        #expect(vm.clipSkipPrompt == nil)
    }

    @Test func evaluateClipSkip_withoutClipInfo_noPrompt() {
        let vm = makeReadyViewModel()

        vm.evaluateClipSkipPrompt(at: 5)

        #expect(vm.clipSkipPrompt == nil)
    }

    @Test func evaluateClipSkip_insideEdRange_showsPrompt() {
        let vm = makeReadyViewModel(clipInfoList: [Self.opClip, Self.edClip])

        vm.evaluateClipSkipPrompt(at: 1_900)

        #expect(vm.clipSkipPrompt?.clip == Self.edClip)
    }

    @Test func evaluateClipSkip_insideOpRange_notReadyState_noPrompt() {
        let vm = PlayerViewModel(epId: 320_665, seasonId: 33_354)
        vm.clipInfoList = [Self.opClip]

        vm.evaluateClipSkipPrompt(at: 5)

        #expect(vm.clipSkipPrompt == nil)
    }

    @Test func evaluateClipSkip_leavesClipRange_cancelsPrompt() {
        let vm = makeReadyViewModel(clipInfoList: [Self.opClip])

        vm.evaluateClipSkipPrompt(at: 5)
        #expect(vm.clipSkipPrompt != nil)

        // 播放离开片段区间（如手动 seek 到 30s）→ 撤销提示
        vm.evaluateClipSkipPrompt(at: 30)

        #expect(vm.clipSkipPrompt == nil)
    }

    // MARK: - 倒计时

    @Test func tickCountdown_decrementsEachSecond() {
        let vm = makeReadyViewModel(clipInfoList: [Self.opClip])
        vm.evaluateClipSkipPrompt(at: 5)

        vm.tickClipSkipCountdown()
        #expect(vm.clipSkipPrompt?.secondsRemaining == 4)

        vm.tickClipSkipCountdown()
        #expect(vm.clipSkipPrompt?.secondsRemaining == 3)
    }

    @Test func tickCountdown_paused_holdsCountdown() {
        let vm = makeReadyViewModel(clipInfoList: [Self.opClip], playing: false)
        vm.evaluateClipSkipPrompt(at: 5)

        vm.tickClipSkipCountdown()
        vm.tickClipSkipCountdown()

        // 暂停中不倒计时：避免暂停状态下自动跳转
        #expect(vm.clipSkipPrompt?.secondsRemaining == 5)
        #expect(vm.clipSkipPrompt != nil)
    }

    @Test func tickCountdown_reachesZero_autoSkips() {
        let vm = makeReadyViewModel(clipInfoList: [Self.opClip])
        var seekTargets: [Double] = []
        vm.clipSkipSeekHandler = { seekTargets.append($0) }
        vm.evaluateClipSkipPrompt(at: 5)

        // 5 次步进：5→4→3→2→1→(归零)自动跳过
        for _ in 0..<4 {
            vm.tickClipSkipCountdown()
        }
        #expect(vm.clipSkipPrompt?.secondsRemaining == 1)

        vm.tickClipSkipCountdown()

        // 自动跳过：seek 到片段终点 26s，提示消失
        #expect(vm.clipSkipPrompt == nil)
        #expect(seekTargets == [26])
    }

    // MARK: - 手动跳过 / 去重

    @Test func performClipSkip_userTap_seeksToClipEnd() {
        let vm = makeReadyViewModel(clipInfoList: [Self.opClip])
        var seekTargets: [Double] = []
        vm.clipSkipSeekHandler = { seekTargets.append($0) }
        vm.evaluateClipSkipPrompt(at: 5)

        vm.performClipSkip()

        #expect(vm.clipSkipPrompt == nil)
        #expect(seekTargets == [26])
    }

    @Test func performClipSkip_whenNoPrompt_isNoOp() {
        let vm = makeReadyViewModel(clipInfoList: [Self.opClip])
        var seekTargets: [Double] = []
        vm.clipSkipSeekHandler = { seekTargets.append($0) }

        vm.performClipSkip()

        #expect(seekTargets.isEmpty)
        #expect(vm.clipSkipPrompt == nil)
    }

    @Test func evaluateClipSkip_afterSkip_doesNotReprompt() {
        let vm = makeReadyViewModel(clipInfoList: [Self.opClip])
        var seekTargets: [Double] = []
        vm.clipSkipSeekHandler = { seekTargets.append($0) }
        vm.evaluateClipSkipPrompt(at: 5)
        vm.performClipSkip()
        #expect(seekTargets == [26])

        // 跳过后仍处于区间内（seek 完成前的过渡时刻）：不再重复提示
        vm.evaluateClipSkipPrompt(at: 10)

        #expect(vm.clipSkipPrompt == nil)
    }

    // MARK: - teardown

    @Test func tearDownPlayer_clearsClipSkipPrompt() {
        let vm = makeReadyViewModel(clipInfoList: [Self.opClip])
        vm.evaluateClipSkipPrompt(at: 5)
        #expect(vm.clipSkipPrompt != nil)

        vm.tearDownPlayer()

        #expect(vm.clipSkipPrompt == nil)
        #expect(vm.player == nil)
        // 配置保留：重试加载可直接消费，无需重新请求
        #expect(vm.clipInfoList == [Self.opClip])
    }

    // MARK: - 文案

    @Test func skipButtonTitle_toastText_stripsPrefix() {
        #expect(Self.opClip.skipButtonTitle == "跳过片头")
    }

    @Test func skipButtonTitle_fallsBackByClipType() {
        #expect(Self.edClip.skipButtonTitle == "跳过片尾")
        #expect(ClipInfo(start: 0, end: 10).skipButtonTitle == "跳过本段")
    }

    // MARK: - Helpers

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
}
