import SwiftUI

/// 全屏加载态：远程 rank/banner 均未就绪时展示。
/// 从 ContentView 的状态分支抽取，便于 snapshot 测试单独渲染。
struct FeedLoadingView: View {
    var body: some View {
        ProgressView("加载中...")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
