import SwiftUI

struct StatsOverlayView: View {
    var statsViewModel: PlayerStatsViewModel
    
    var body: some View {
        if statsViewModel.isVisible {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "chart.bar.xaxis")
                        .foregroundStyle(.green)
                    Text("视频统计信息 (Stats for nerds)")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                    Spacer()
                    Button(action: {
                        statsViewModel.isVisible.toggle()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.gray)
                    }
                    .buttonStyle(.plain)
                }
                
                Divider()
                    .background(Color.white.opacity(0.3))
                
                Group {
                    StatRow(label: "分辨率", value: statsViewModel.resolution, color: .cyan)
                    StatRow(label: "帧率", value: statsViewModel.frameRate, color: .green)
                    StatRow(label: "视频编码 / 比特率", value: "\(statsViewModel.videoCodec) (\(statsViewModel.videoBitrate))", color: .yellow)
                    StatRow(label: "音频编码 / 比特率", value: "\(statsViewModel.audioCodec) (\(statsViewModel.audioBitrate))", color: .purple)
                    StatRow(label: "已缓冲时长", value: statsViewModel.bufferedDuration, color: .orange)
                    StatRow(label: "播放状态", value: statsViewModel.playerState, color: .white)
                    StatRow(label: "连接速度", value: statsViewModel.connectionSpeed, color: .green)
                    StatRow(label: "丢帧数", value: statsViewModel.droppedFrames, color: .red)
                    StatRow(label: "音量", value: statsViewModel.volume, color: .cyan)
                    StatRow(label: "容器格式", value: statsViewModel.containerFormat, color: .gray)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("当前视频流 URL")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.7))
                        Text(statsViewModel.streamURL)
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .foregroundStyle(.green.opacity(0.9))
                            .lineLimit(2)
                            .truncationMode(.middle)
                    }
                    .padding(.top, 4)
                }
            }
            .padding(20)
            .frame(width: 540)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(.thickMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                    )
            )
            .shadow(radius: 12)
            .padding(40)
        }
    }
}

struct StatRow: View {
    let label: String
    let value: String
    let color: Color
    
    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
        }
    }
}
