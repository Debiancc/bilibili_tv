import SwiftUI

/// `-uitestMockDetail` 根容器：复刻 ContentView 的 coordinator 注入 + 单一 cover 呈现。
/// 阶段一后 DetailView 不再自带内联 cover，播放经环境 coordinator 直达根视图；
/// 此根容器保证详情页焦点导航测试走真实播放路径（注入 → 触发 → 根 cover 弹出）。
struct UITestMockDetailRoot: View {
    @State private var playbackCoordinator = PlaybackCoordinator()

    /// mock 选择:`-uitestMockDetailLongSynopsis` 注入长简介变体(展开后把选集行
    /// 推下首屏折线,供 ↓ 死区回归测试),其余详情页测试沿用默认短简介 mock。
    private var mockViewModel: DetailViewModel {
        if ProcessInfo.processInfo.arguments.contains("-uitestMockDetailLongSynopsis") {
            return .longSynopsisMock
        }
        return .mock
    }

    var body: some View {
        @Bindable var playbackCoordinator = playbackCoordinator
        let mockVM = mockViewModel
        DetailView(item: mockVM.feedItem, viewModel: mockVM)
            .fullScreenCover(item: $playbackCoordinator.activePlayback) { context in
                PlaybackCoverView(context: context)
            }
            .environment(\.playbackCoordinator, playbackCoordinator)
    }
}
