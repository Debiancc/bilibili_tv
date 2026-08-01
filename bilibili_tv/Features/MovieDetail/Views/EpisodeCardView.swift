import SwiftUI
import Kingfisher

struct EpisodeCardView: View {
    let episode: PGCEpisode
    @Binding var selectedEpisode: PGCEpisode?
    @FocusState private var isFocused: Bool
    
    var body: some View {
        Button(action: {
            selectedEpisode = episode
        }) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .bottomTrailing) {
                    // Cover
                    if let cover = episode.cover, let url = URL(string: cover.replacingOccurrences(of: "http://", with: "https://") + "@400w_225h_1c.webp") {
                        KFImage(url)
                            .placeholder {
                                Rectangle().fill(Color.gray.opacity(0.3))
                            }
                            .fade(duration: 0.2)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 320, height: 180)
                            .clipped()
                    } else {
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 320, height: 180)
                    }
                    
                    // Duration
                    if let durationMS = episode.duration {
                        Text(formatDuration(ms: durationMS))
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.7))
                            .cornerRadius(4)
                            .padding(8)
                    }
                    
                    // Badge (e.g. VIP)
                    if let badge = episode.badge, !badge.isEmpty {
                        Text(badge)
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(Color.pink)
                            .cornerRadius(4)
                            .padding(8)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    }
                }
                .cornerRadius(12)
                
                // Title
                Text(episode.longTitle ?? episode.title ?? "")
                    .font(.subheadline)
                    .foregroundColor(isFocused ? .primary : .secondary)
                    .lineLimit(1)
                    .frame(width: 320, alignment: .leading)
            }
        }
        .buttonStyle(.card)
        .focused($isFocused)
    }
    
    private func formatDuration(ms: Int) -> String {
        let totalSeconds = ms / 1000
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
