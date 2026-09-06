import SwiftUI

struct UpNextShelfView: View {
    let episodes: [PGCEpisode]
    let action: (PGCEpisode) -> Void
    let onReturnToActions: () -> Void

    @FocusState private var focusedEpisodeID: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("接着看")
                .font(.title3)
                .foregroundStyle(.white)
                .padding(.leading, DetailDesign.UpNext.horizontalInset)

            ScrollView(.horizontal, showsIndicators: false) {
                VStack(spacing: 0) {
                    HStack {
                        Spacer(minLength: 0)
                        UpNextReturnAnchor(
                            isFocusEnabled: focusedEpisodeID == episodes.last?.id,
                            onGainedFocus: onReturnToActions
                        )
                    }
                    .frame(width: shelfContentWidth, height: 40)

                    HStack(spacing: DetailDesign.UpNext.cardSpacing) {
                        ForEach(episodes) { episode in
                            EpisodeCardView(
                                episode: episode,
                                action: { action(episode) },
                                focusedEpisodeID: $focusedEpisodeID
                            )
                        }
                    }
                }
                .padding(.horizontal, DetailDesign.UpNext.horizontalInset)
            }
        }
        .focusSection()
    }

    private var shelfContentWidth: CGFloat {
        let cardCount = CGFloat(episodes.count)
        let spacingCount = max(cardCount - 1, 0)
        return cardCount * DetailDesign.UpNext.cardWidth + spacingCount * DetailDesign.UpNext.cardSpacing
    }
}

/// 行末卡片正上方的原生焦点承接点。只在末项聚焦时启用，按 ↑ 后将焦点交给 Hero 操作组。
private struct UpNextReturnAnchor: View {
    let isFocusEnabled: Bool
    let onGainedFocus: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        Color.clear
            .frame(width: DetailDesign.UpNext.cardWidth, height: 40)
            .focusable(isFocusEnabled || isFocused)
            .focused($isFocused)
            .onChange(of: isFocused) { _, focused in
                guard focused else { return }
                onGainedFocus()
            }
            .accessibilityHidden(true)
    }
}
