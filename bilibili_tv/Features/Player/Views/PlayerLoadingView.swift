import SwiftUI

/// ⏳ 播放器加载态视图（阶段三 3a 从 BiliPlayerContainerView body 拆出，
/// 独立文件便于 snapshot 测试直接渲染，避免容器 `.task` 覆盖预置状态）
struct PlayerLoadingView: View {
    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
            Text("正在自适应加载高清视频流...")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.8))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    PlayerLoadingView()
}
