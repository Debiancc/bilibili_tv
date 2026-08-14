import AVFoundation
import Foundation

// MARK: - ⏭️ 跳过片头/片尾（clip_info_list 消费）
//
// 从 PlayerViewModel 主文件迁出（type_body_length 收敛），与 PlayerViewModel+ItemLoading.swift
// 同一模式：主文件保留存储属性与 apply/teardown 调用点，逻辑实现放扩展。
// 测试直接驱动 evaluateClipSkipPrompt(at:) / tickClipSkipCountdown()（periodic time
// observer 与 Timer 在 Swift Testing 进程不可靠触发，见 PlayerViewModelClipSkipTests）。

extension PlayerViewModel {
    /// 跳过提示倒计时时长（秒）：倒计时结束无操作自动跳过
    static let clipSkipCountdownSeconds = 5

    /// 播放进入剪辑区间后启动监控（apply 置 .ready 时调用）：periodic time observer 每秒评估一次
    func startClipSkipMonitoring() {
        guard state == .ready, let player, clipSkipTimeObserver == nil else { return }
        clipSkipTimeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 1, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor [weak self] in
                self?.evaluateClipSkipPrompt(at: time.seconds)
            }
        }
    }

    /// 🛑 停止跳过提示监控（teardown 调用）：移除观察者、停倒计时、清空提示
    func stopClipSkipMonitoring() {
        if let clipSkipTimeObserver, let player {
            player.removeTimeObserver(clipSkipTimeObserver)
        }
        clipSkipTimeObserver = nil
        clipSkipCountdownTimer?.invalidate()
        clipSkipCountdownTimer = nil
        clipSkipPrompt = nil
    }

    /// 播放进度评估（internal 供测试直接驱动；生产路径由 periodic time observer 每秒调用）：
    /// - 无提示且播放进入某剪辑区间 → 弹出提示并启动 5 秒倒计时
    /// - 已有提示但播放离开该区间（如手动 seek）→ 撤销提示
    func evaluateClipSkipPrompt(at time: Double) {
        guard state == .ready else { return }
        guard time.isFinite else { return }

        if let prompt = clipSkipPrompt {
            if !isInsideClip(time: time, clip: prompt.clip) {
                cancelClipSkipPrompt()
            }
            return
        }
        guard let clip = activeClip(at: time) else { return }
        guard !skippedClipKeys.contains(clip.key) else { return }
        clipSkipPrompt = ClipSkipPresentation(
            clip: clip,
            secondsRemaining: Self.clipSkipCountdownSeconds
        )
        startClipSkipCountdown()
    }

    /// 命中当前播放时间所在的剪辑区间（仅取首个；start/end 缺省或非法区间不命中）
    func activeClip(at time: Double) -> ClipInfo? {
        clipInfoList.first { clip in
            isInsideClip(time: time, clip: clip)
        }
    }

    func isInsideClip(time: Double, clip: ClipInfo) -> Bool {
        guard let start = clip.start, let end = clip.end, end > start else { return false }
        return time >= Double(start) && time < Double(end)
    }

    /// 启动倒计时 Timer（1 秒步进）：归零自动跳过
    func startClipSkipCountdown() {
        clipSkipCountdownTimer?.invalidate()
        clipSkipCountdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tickClipSkipCountdown()
            }
        }
    }

    /// 倒计时步进（internal 供测试直接驱动；生产路径由 Timer 每秒调用）：
    /// 暂停中不倒计时（避免暂停状态下自动跳转）；归零执行自动跳过
    func tickClipSkipCountdown() {
        guard var prompt = clipSkipPrompt else { return }
        guard playerIsPlayingProvider() else { return }
        guard prompt.secondsRemaining > 1 else {
            performClipSkip()
            return
        }
        prompt.secondsRemaining -= 1
        clipSkipPrompt = prompt
    }

    /// ⏭️ 执行跳过：seek 到片段终点并撤销提示（用户点击按钮或倒计时归零均走此路径）
    func performClipSkip() {
        guard let prompt = clipSkipPrompt else { return }
        clipSkipPrompt = nil
        clipSkipCountdownTimer?.invalidate()
        clipSkipCountdownTimer = nil
        skippedClipKeys.insert(prompt.clip.key)
        let targetSeconds = Double(prompt.clip.end ?? 0)
        clipSkipSeekHandler(targetSeconds)
        print("⏭️ [Player] Skipped \(prompt.clip.clipType ?? "clip") to \(targetSeconds)s")
    }

    /// 撤销提示（播放离开片段区间）：仅清状态，不标记已跳过
    func cancelClipSkipPrompt() {
        clipSkipPrompt = nil
        clipSkipCountdownTimer?.invalidate()
        clipSkipCountdownTimer = nil
    }
}
