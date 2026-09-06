import Kingfisher
import SwiftUI

enum DetailAccessibilityIdentifier {
    static func episode(_ episodeID: Int) -> String {
        "detail.episode.\(episodeID)"
    }

    static let quickJump = "detail.action.quick-jump"
    static let pickerPreview = "detail.picker.preview"

    static func pickerRange(_ range: EpisodeRange) -> String {
        "detail.picker.range.\(range.lowerBound + 1)-\(range.upperBound)"
    }

    static func pickerEpisode(_ episodeID: Int) -> String {
        "detail.picker.episode.\(episodeID)"
    }
}

struct EpisodeCardView: View {
    let episode: PGCEpisode
    let action: () -> Void
    @FocusState.Binding var focusedEpisodeID: Int?

    /// 封面 URL：http/`//` 规范化 + CDN 切片参数（@400w_225h_1c.webp）
    private var coverURL: URL? {
        ImageURL.secure(episode.cover)
            .map { ImageURL.cdn($0, suffix: "@400w_225h_1c.webp") }
            .flatMap(URL.init(string:))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            episodeButton
            MarqueeText(text: episode.formattedTitle, isFocused: focusedEpisodeID == episode.id)
                .frame(width: DetailDesign.UpNext.cardWidth, alignment: .leading)
        }
    }

    private var episodeButton: some View {
        Button(action: action) {
            ZStack(alignment: .bottomTrailing) {
                artwork
                durationLabel
                badgeLabel
            }
            .clipShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.card)
        .focused($focusedEpisodeID, equals: episode.id)
        .accessibilityLabel(episode.formattedTitle)
        .accessibilityIdentifier(DetailAccessibilityIdentifier.episode(episode.id))
    }

    @ViewBuilder
    private var artwork: some View {
        if let coverURL {
            KFImage(coverURL)
                .placeholder { Rectangle().fill(Color.gray.opacity(0.3)) }
                .fade(duration: 0.2)
                .resizable()
                .scaledToFill()
                .frame(width: DetailDesign.UpNext.cardWidth, height: DetailDesign.UpNext.artworkHeight)
                .clipped()
        } else {
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: DetailDesign.UpNext.cardWidth, height: DetailDesign.UpNext.artworkHeight)
        }
    }

    @ViewBuilder
    private var durationLabel: some View {
        if let durationText = episode.formattedDuration {
            Text(durationText)
                .font(.system(size: DetailDesign.Typography.episodeNumber, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.7))
                .clipShape(.rect(cornerRadius: 4))
                .padding(8)
        }
    }

    @ViewBuilder
    private var badgeLabel: some View {
        if let badge = episode.badge, !badge.isEmpty {
            Text(badge)
                .font(.system(size: DetailDesign.Typography.episodeNumber, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.pink)
                .clipShape(.rect(cornerRadius: 4))
                .padding(8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
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
                    .font(.system(size: DetailDesign.Typography.body, weight: .medium))
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
        .frame(height: 36)  // Give fixed height for geometry reader
    }
}
