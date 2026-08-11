import SwiftUI

/// ❌ 播放器加载失败视图（阶段三 3a 从 BiliPlayerContainerView body 拆出，
/// 独立文件便于 snapshot 测试直接渲染；重试按钮重新触发 ViewModel.loadVideo）
struct PlayerErrorView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 50))
                .foregroundStyle(.yellow)
            Text("视频加载失败")
                .font(.title2)
                .foregroundStyle(.white)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("重新加载", action: onRetry)
                .buttonStyle(.glass)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    PlayerErrorView(message: "无法连接网络", onRetry: {})
}
