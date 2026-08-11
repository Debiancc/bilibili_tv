//
//  BiliPlayerContainerViewSnapshotTests.swift
//  bilibili_tvTests
//
//  阶段三 3a：BiliPlayerContainerView 三态渲染快照基准。
//
//  三态映射（重构后）:
//  - .idle/.loading → PlayerLoadingView：全屏 ProgressView("正在自适应加载高清视频流...")
//  - .failed(message:) → PlayerErrorView：错误图标 + "视频加载失败" + 文案 + 重试按钮
//  - .ready → BiliPlayerContainerView(注入 .ready ViewModel + AVPlayer())：
//    黑底 + AVPlayerViewController + StatsOverlayView 小窗（isVisible 默认开）
//
//  ⚠️ 成功态不能用真实加载流程驱动（依赖网络），由手工构造 .ready 状态注入；
//     容器 `.task` 对 .ready 幂等返回，不会覆盖预置状态。
//  ⚠️ 重构完成后重新生成基准并 diff，必须为空或在 PR 描述中逐条解释差异原因；
//     禁止无理由用 record 模式覆盖。
//

import AVFoundation
import SnapshotTesting
import SwiftUI
import Testing

@testable import bilibili_tv

@Suite(.snapshots)
@MainActor
struct BiliPlayerContainerViewSnapshotTests {
    private func makeViewModel(state: PlayerLoadState) -> PlayerViewModel {
        let vm = PlayerViewModel(
            epId: 320_665,
            seasonId: 33_354,
            title: "夏洛特烦恼",
            subtitle: "马冬梅的排列组合",
            coverURL: nil,
            service: MockPlayerService()
        )
        vm.state = state
        return vm
    }

    // MARK: - 加载态

    @Test func loading_state() async {
        let view = PlayerLoadingView()
        assertSnapshot(of: view, as: .image(precision: 0.95, layout: .fixed(width: 640, height: 360)))
    }

    // MARK: - 失败态

    @Test func failed_state() async {
        let view = PlayerErrorView(message: "无法解析播放流（可能需要大会员或 CDN 鉴权失败）", onRetry: {})
        assertSnapshot(of: view, as: .image(precision: 0.95, layout: .fixed(width: 640, height: 360)))
    }

    // MARK: - 成功态（注入 .ready ViewModel）

    @Test func ready_state() async {
        let vm = makeViewModel(state: .ready)
        vm.player = AVPlayer()
        let view = BiliPlayerContainerView(
            epId: 320_665,
            seasonId: 33_354,
            title: "夏洛特烦恼",
            subtitle: "马冬梅的排列组合",
            viewModel: vm
        )
        assertSnapshot(of: view, as: .image(precision: 0.95, layout: .fixed(width: 640, height: 360)))
    }
}
