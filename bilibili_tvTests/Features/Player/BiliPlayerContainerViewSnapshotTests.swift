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
//  阶段三 3c 新增组合快照：
//  - 试看/正式播放：isPreviewOnly + purchaseHintText 注入 → 横幅可见 vs 无横幅
//  - 弹幕开/关：danmakuSessionActive 注入（Stub provider 无网络）→ 容器 overlay 层；
//    弹幕本体渲染由 DanmakuView 单视图快照覆盖（顶部弹幕 mode=5 立即可见）
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

    private func makeViewModel(
        state: PlayerLoadState,
        danmakuVM: DanmakuViewModel
    ) -> PlayerViewModel {
        let vm = PlayerViewModel(
            epId: 320_665,
            seasonId: 33_354,
            title: "夏洛特烦恼",
            subtitle: "马冬梅的排列组合",
            coverURL: nil,
            service: MockPlayerService(),
            danmakuVM: danmakuVM
        )
        vm.state = state
        return vm
    }

    /// 轮询等待 danmakuSessionActive 镜像收敛（Combine + MainActor hop 有少量延迟）
    private func waitForDanmakuState(_ vm: PlayerViewModel, active: Bool, timeoutNanoseconds: UInt64 = 1_000_000_000) async -> Bool {
        var elapsed: UInt64 = 0
        while vm.danmakuSessionActive != active, elapsed < timeoutNanoseconds {
            try? await Task.sleep(nanoseconds: 10_000_000)
            elapsed += 10_000_000
        }
        return vm.danmakuSessionActive == active
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

    // MARK: - 3c 组合：试看 / 正式播放 overlay

    /// 试看态：isPreviewOnly + 购买文案 → 左上角横幅可见
    @Test func ready_previewOnly_showsPurchaseBanner() async {
        let vm = makeViewModel(state: .ready)
        vm.player = AVPlayer()
        vm.isPreviewOnly = true
        vm.purchaseHintText = "观看全片需购买或开通大会员"
        let view = BiliPlayerContainerView(
            epId: 320_665,
            seasonId: 33_354,
            title: "夏洛特烦恼",
            subtitle: "马冬梅的排列组合",
            viewModel: vm
        )
        assertSnapshot(of: view, as: .image(precision: 0.95, layout: .fixed(width: 640, height: 360)))
    }

    /// 正式播放：无试看标志 → 无横幅（ready_state 已覆盖，此组合补试看文案为 nil 的分支）
    @Test func ready_previewOnly_noHintText_showsNoBanner() async {
        let vm = makeViewModel(state: .ready)
        vm.player = AVPlayer()
        vm.isPreviewOnly = true
        vm.purchaseHintText = nil
        let view = BiliPlayerContainerView(
            epId: 320_665,
            seasonId: 33_354,
            title: "夏洛特烦恼",
            subtitle: "马冬梅的排列组合",
            viewModel: vm
        )
        assertSnapshot(of: view, as: .image(precision: 0.95, layout: .fixed(width: 640, height: 360)))
    }

    // MARK: - 3c 组合：弹幕开 / 关 overlay

    /// 弹幕开：会话激活（Stub provider 无网络）→ 容器渲染弹幕渲染层
    @Test func ready_danmakuSessionActive_rendersDanmakuLayer() async {
        let danmakuVM = DanmakuViewModel(provider: StubDanmakuProvider())
        let vm = makeViewModel(state: .ready, danmakuVM: danmakuVM)
        vm.player = AVPlayer()
        vm.currentCid = 777
        vm.startPostLoadServices()
        #expect(await waitForDanmakuState(vm, active: true))

        let view = BiliPlayerContainerView(
            epId: 320_665,
            seasonId: 33_354,
            title: "夏洛特烦恼",
            subtitle: "马冬梅的排列组合",
            viewModel: vm
        )
        assertSnapshot(of: view, as: .image(precision: 0.95, layout: .fixed(width: 640, height: 360)))
    }

    /// 弹幕渲染本体：顶部弹幕（mode=5）入轨后立即全可见（不依赖滚动动画）。
    /// DanmakuCell 用 DanmakuAsyncLayer 绘制：异步路径的 display() 仅在有窗口的渲染周期内
    /// 触发，离屏测试环境永远不执行（contents 恒为 nil）。因此切换为同步绘制并手动触发
    /// display()，生成内容与生产异步路径一致的文本位图（仅时序不同）。
    @Test func danmakuLayer_topDanmaku_isVisible() {
        let view = DanmakuView(frame: CGRect(x: 0, y: 0, width: 640, height: 360))
        view.trackHeight = 40
        view.displayArea = 0.75
        view.recalculateTracks()
        view.play()
        view.shoot(
            danmaku: DanmakuTextCellModel(
                text: "前方高能预警",
                mode: 5,
                color: 0xFFFFFF,
                fontSize: 32,
                displayTime: 8,
                opacity: 1.0
            )
        )
        if let cell = view.subviews.first as? DanmakuCell {
            cell.displayAsync = false
            cell.layer.display()
        }
        #expect(view.subviews.first?.layer.contents != nil, "同步绘制后 contents 应立即可用")
        assertSnapshot(of: view, as: .image(precision: 0.95, size: CGSize(width: 640, height: 360)))
    }

    /// 弹幕关：未发射弹幕的渲染层为空（快照基准：无内容时渲染层不产生噪点/残影）
    @Test func danmakuLayer_empty_isBlank() {
        let view = DanmakuView(frame: CGRect(x: 0, y: 0, width: 640, height: 360))
        view.trackHeight = 40
        view.displayArea = 0.75
        view.recalculateTracks()
        view.play()
        assertSnapshot(of: view, as: .image(precision: 0.95, size: CGSize(width: 640, height: 360)))
    }
}
