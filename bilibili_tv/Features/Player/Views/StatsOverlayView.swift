import SwiftUI

struct StatsOverlayView: View {
    var statsViewModel: PlayerStatsViewModel
    
    var body: some View {
        if statsViewModel.isStatsVisible {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "chart.bar.xaxis")
                        .foregroundColor(.green)
                    Text("视频统计信息 (Stats for nerds)")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()
                    Button(action: {
                        statsViewModel.toggleStatsVisibility()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                    }
                    .buttonStyle(.plain)
                }
                
                Divider()
                    .background(Color.white.opacity(0.3))
                
                Group {
                    StatRow(label: "分辨率 / 画质", value: statsViewModel.resolution, color: .cyan)
                    StatRow(label: "目标码率 (Bitrate)", value: statsViewModel.bitrate, color: .yellow)
                    StatRow(label: "实测下载网速", value: statsViewModel.observedBitrate, color: .green)
                    StatRow(label: "缓冲区健康度", value: statsViewModel.bufferDuration, color: .orange)
                    StatRow(label: "丢帧统计", value: statsViewModel.droppedFrames, color: statsViewModel.droppedFrames == "0" ? .white : .red)
                    StatRow(label: "编码格式", value: statsViewModel.codecInfo, color: .purple)
                    StatRow(label: "CDN 节点", value: statsViewModel.cdnHost, color: .gray)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("当前视频流 URL")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                        Text(statsViewModel.streamURL)
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .foregroundColor(.green.opacity(0.9))
                            .lineLimit(2)
                            .truncationMode(.middle)
                    }
                    .padding(.top, 4)
                }
            }
            .padding(20)
            .frame(width: 520)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.black.opacity(0.82))
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
                .foregroundColor(.white.opacity(0.7))
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundColor(color)
        }
    }
}
