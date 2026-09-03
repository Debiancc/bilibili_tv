import Kingfisher
import SwiftUI

struct EpisodeCardView: View {
    let episode: PGCEpisode
    let action: () -> Void
    @FocusState private var isFocused: Bool

    /// 封面 URL：http/`//` 规范化 + CDN 切片参数（@400w_225h_1c.webp）
    private var coverURL: URL? {
        ImageURL.secure(episode.cover)
            .map { ImageURL.cdn($0, suffix: "@400w_225h_1c.webp") }
            .flatMap(URL.init(string:))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: action) {
                ZStack(alignment: .bottomTrailing) {
                    // Cover
                    if let url = coverURL {
                        KFImage(url)
                            .placeholder {
                                Rectangle().fill(Color.gray.opacity(0.3))
                            }
                            .fade(duration: 0.2)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 320, height: 180)
                            .clipped()
                    } else {
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 320, height: 180)
                    }

                    // Duration
                    if let durationText = episode.formattedDuration {
                        Text(durationText)
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.7))
                            .clipShape(.rect(cornerRadius: 4))
                            .padding(8)
                    }

                    // Badge (e.g. VIP)
                    if let badge = episode.badge, !badge.isEmpty {
                        Text(badge)
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(Color.pink)
                            .clipShape(.rect(cornerRadius: 4))
                            .padding(8)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    }
                }
                .clipShape(.rect(cornerRadius: 12))
            }
            .buttonStyle(.card)
            .focused($isFocused)
            .accessibilityLabel(episode.formattedTitle)

            // Separated Title
            MarqueeText(text: episode.formattedTitle, isFocused: isFocused)
                .frame(width: 320, alignment: .leading)
        }
    }
}

struct MarqueeText: View {
    let text: String
    let isFocused: Bool

    @State private var textWidth: CGFloat = 0
    @State private var offset: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            ScrollView(.horizontal, showsIndicators: false) {
                Text(text)
                    .font(.caption)
                    .foregroundStyle(isFocused ? .white : .gray)
                    .lineLimit(1)
                    .background(
                        GeometryReader { textGeo in
                            Color.clear.onAppear {
                                textWidth = textGeo.size.width
                            }
                        }
                    )
                    .offset(x: offset)
            }
            .disabled(true)  // Disable manual scrolling
            .onChange(of: isFocused) { _, focused in
                if focused && textWidth > geo.size.width {
                    let diff = textWidth - geo.size.width
                    // Simple marquee animation
                    withAnimation(.linear(duration: Double(diff) / 30.0).delay(0.5).repeatForever(autoreverses: true)) {
                        offset = -diff - 10
                    }
                } else {
                    withAnimation {
                        offset = 0
                    }
                }
            }
        }
        .frame(height: 20)  // Give fixed height for geometry reader
    }
}
