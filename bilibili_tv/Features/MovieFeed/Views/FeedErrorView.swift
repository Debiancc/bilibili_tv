import SwiftUI

/// 远程加载失败态：rank 为空时全屏展示错误与重试入口。
/// 远程失败时仍保留本地续播 shelf,离线可续播。
/// 从 ContentView 的状态分支抽取,便于 snapshot 测试单独渲染。
struct FeedErrorView: View {
    let errorMessage: String
    let resumeItems: [LocalWatchHistoryEntry]
    let onRetry: () -> Void

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 60) {
                VStack(spacing: 20) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 80))
                        .foregroundStyle(.orange)
                    Text("出错了")
                        .font(.headline)
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("重试", action: onRetry)
                        .buttonStyle(.glass)
                }
                .padding(.top, 120)

                // ▶️ 远程失败时仍保留本地续播 shelf,离线可续播
                if !resumeItems.isEmpty {
                    ResumeShelfView(items: resumeItems)
                }
            }
        }
    }
}
