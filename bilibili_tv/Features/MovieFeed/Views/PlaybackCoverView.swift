import SwiftUI

/// 统一播放器 cover：由根视图单一 `fullScreenCover(item:)` 呈现。
/// ContentView 与 `-uitestMockDetail` 测试根容器共用，避免 cover 参数拼装重复。
struct PlaybackCoverView: View {
    let context: PlaybackContext

    var body: some View {
        BiliPlayerContainerView(
            epId: context.epId,
            seasonId: context.seasonId,
            title: context.title,
            subtitle: context.subtitle,
            coverURL: context.coverURL,
            resumeTime: context.resumeTime
        )
    }
}
