import SwiftUI

/// 详情页远程加载态：详情数据未就绪时展示。
/// 与 FeedLoadingView 同构，从 MovieDetailView 的状态分支抽取，便于 snapshot 测试单独渲染。
struct MovieDetailLoadingView: View {
    var body: some View {
        ProgressView("加载中...")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
