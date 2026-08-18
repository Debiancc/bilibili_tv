import SwiftUI

/// `-uitestMockDetail` 根容器：复刻 ContentView 的 coordinator 注入 + 单一 cover 呈现。
/// 阶段一后 DetailView 不再自带内联 cover，播放经环境 coordinator 直达根视图；
/// 此根容器保证详情页焦点导航测试走真实播放路径（注入 → 触发 → 根 cover 弹出）。
struct UITestMockDetailRoot: View {
    @State private var playbackCoordinator = PlaybackCoordinator()

    var body: some View {
        @Bindable var playbackCoordinator = playbackCoordinator
        let mockVM = DetailViewModel.mock
        DetailView(item: mockVM.feedItem, viewModel: mockVM)
            .fullScreenCover(item: $playbackCoordinator.activePlayback) { context in
                PlaybackCoverView(context: context)
            }
            .environment(\.playbackCoordinator, playbackCoordinator)
    }
}
