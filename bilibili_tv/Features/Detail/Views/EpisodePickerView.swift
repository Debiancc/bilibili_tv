import Kingfisher
import SwiftUI

struct EpisodePickerView: View {
    let viewModel: EpisodePickerViewModel
    let seasonDescription: String?
    let onPlay: (PGCEpisode) -> Void
    let onDismiss: () -> Void

    @FocusState private var focusedEpisodeID: Int?
    @FocusState private var focusedRangeID: Int?

    var body: some View {
        HStack(alignment: .top, spacing: 64) {
            pickerContent
            EpisodePickerPreviewView(
                episode: viewModel.focusedEpisode,
                seasonDescription: seasonDescription
            )
        }
        .padding(.horizontal, DetailDesign.Picker.horizontalInset)
        .padding(.vertical, 80)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.black.ignoresSafeArea())
        .onAppear { restoreFocusedEpisode() }
        .onChange(of: focusedEpisodeID) { _, episodeID in
            guard let episode = viewModel.episodes.first(where: { $0.id == episodeID }) else { return }
            viewModel.focus(episode: episode)
        }
        .onExitCommand(perform: onDismiss)
    }

    private var pickerContent: some View {
        VStack(alignment: .leading, spacing: 36) {
            pickerHeader
            EpisodePickerRangeSelector(
                ranges: viewModel.ranges,
                focusedRangeID: $focusedRangeID,
                selectRange: viewModel.select
            )
            EpisodePickerGrid(
                episodes: viewModel.selectedEpisodes,
                defaultFocusedEpisodeID: viewModel.focusedEpisode?.id,
                focusedEpisodeID: $focusedEpisodeID,
                onPlay: onPlay
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var pickerHeader: some View {
        Text("选集")
            .font(.title2)
            .foregroundStyle(.white)
    }

    private func restoreFocusedEpisode() {
        focusedEpisodeID = viewModel.focusedEpisode?.id
    }
}

private struct EpisodePickerRangeSelector: View {
    let ranges: [EpisodeRange]
    @FocusState.Binding var focusedRangeID: Int?
    let selectRange: (EpisodeRange) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DetailDesign.Picker.gridSpacing) {
                ForEach(ranges) { range in
                    EpisodePickerRangeButton(
                        range: range,
                        isFocused: focusedRangeID == range.id,
                        action: { selectRange(range) }
                    )
                    .focused($focusedRangeID, equals: range.id)
                }
            }
        }
        .scrollClipDisabled()
        .onChange(of: focusedRangeID) { _, rangeID in
            guard let rangeID, let range = ranges.first(where: { $0.id == rangeID }) else { return }
            selectRange(range)
        }
    }
}

private struct EpisodePickerRangeButton: View {
    let range: EpisodeRange
    let isFocused: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(range.displayLabel)
                .font(.system(size: DetailDesign.Typography.body, weight: .semibold))
                .foregroundStyle(
                    isFocused ? DetailDesign.Picker.focusedText : DetailDesign.Picker.unfocusedText
                )
                .frame(
                    width: DetailDesign.Picker.rangeWidth,
                    height: DetailDesign.Picker.rangeHeight
                )
                .background(background)
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .animation(.easeOut(duration: 0.16), value: isFocused)
        .accessibilityIdentifier(DetailAccessibilityIdentifier.pickerRange(range))
        .accessibilityValue("第\(range.displayLabel)话")
    }

    private var background: some View {
        Capsule()
            .fill(isFocused ? DetailDesign.Picker.focusedFill : DetailDesign.Picker.unfocusedFill)
    }
}

private struct EpisodePickerGrid: View {
    let episodes: [PGCEpisode]
    let defaultFocusedEpisodeID: Int?
    @FocusState.Binding var focusedEpisodeID: Int?
    let onPlay: (PGCEpisode) -> Void

    private let columns = Array(
        repeating: GridItem(.flexible(minimum: DetailDesign.Picker.gridMinimumWidth), spacing: DetailDesign.Picker.gridSpacing),
        count: 5
    )

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(columns: columns, spacing: DetailDesign.Picker.gridSpacing) {
                ForEach(episodes) { episode in
                    episodeTile(episode)
                }
            }
        }
        .scrollClipDisabled()
        .defaultFocus($focusedEpisodeID, defaultFocusedEpisodeID)
    }

    private func episodeTile(_ episode: PGCEpisode) -> some View {
        EpisodePickerTileButton(
            episode: episode,
            isFocused: focusedEpisodeID == episode.id,
            action: { onPlay(episode) }
        )
        .focused($focusedEpisodeID, equals: episode.id)
    }
}

private struct EpisodePickerTileButton: View {
    let episode: PGCEpisode
    let isFocused: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(episode.title ?? "—")
                .font(.system(size: DetailDesign.Typography.body, weight: .medium))
                .foregroundStyle(
                    isFocused ? DetailDesign.Picker.focusedText : DetailDesign.Picker.unfocusedText
                )
                .frame(maxWidth: .infinity, minHeight: DetailDesign.Picker.gridTileHeight)
                .background(background)
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .animation(.easeOut(duration: 0.16), value: isFocused)
        .accessibilityLabel(episode.formattedTitle)
        .accessibilityIdentifier(DetailAccessibilityIdentifier.pickerEpisode(episode.id))
    }

    private var background: some View {
        RoundedRectangle(cornerRadius: DetailDesign.Picker.tileCornerRadius, style: .continuous)
            .fill(isFocused ? DetailDesign.Picker.focusedFill : DetailDesign.Picker.unfocusedFill)
    }
}

private struct EpisodePickerPreviewView: View {
    let episode: PGCEpisode?
    let seasonDescription: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            previewArtwork
            Text(episodeNumber)
                .font(.system(size: DetailDesign.Typography.body, weight: .medium))
                .foregroundStyle(.secondary)
            Text(episode?.formattedTitle ?? "选择一集")
                .font(.system(size: DetailDesign.Typography.previewTitle, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(2)
            Text(seasonDescription ?? "使用遥控器选择剧集，按确认键立即播放。")
                .font(.system(size: DetailDesign.Typography.body))
                .foregroundStyle(.secondary)
                .lineLimit(4)
        }
        .frame(width: DetailDesign.Picker.previewWidth, alignment: .leading)
        .accessibilityIdentifier(DetailAccessibilityIdentifier.pickerPreview)
        .accessibilityValue(episode?.formattedTitle ?? "未选择剧集")
    }

    @ViewBuilder
    private var previewArtwork: some View {
        if let previewURL {
            KFImage(previewURL)
                .placeholder { Color.gray.opacity(0.3) }
                .resizable()
                .scaledToFill()
                .frame(height: DetailDesign.Picker.previewArtworkHeight)
                .clipShape(.rect(cornerRadius: 24))
        } else {
            Color.gray.opacity(0.3)
                .frame(height: DetailDesign.Picker.previewArtworkHeight)
                .clipShape(.rect(cornerRadius: 24))
        }
    }

    private var episodeNumber: String {
        guard let title = episode?.title, !title.isEmpty else { return "当前焦点剧集" }
        return "第\(title)话"
    }

    private var previewURL: URL? {
        ImageURL.secure(episode?.cover)
            .map { ImageURL.cdn($0, suffix: "@1600w_900h_1c.webp") }
            .flatMap(URL.init(string:))
    }
}
