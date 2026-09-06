import Foundation
import Observation

/// A stable, index-based slice of an episode collection for long-running PGC series.
struct EpisodeRange: Identifiable, Equatable, Hashable {
    let lowerBound: Int
    let upperBound: Int

    var id: Int { lowerBound }

    var displayLabel: String {
        "\(lowerBound + 1)-\(upperBound)"
    }

    func contains(index: Int) -> Bool {
        (lowerBound..<upperBound).contains(index)
    }
}

enum EpisodeNavigation {
    static let episodesPerRange = 100
    static let maximumUpNextEpisodes = 20

    static func supportsQuickJump(episodeCount: Int) -> Bool {
        episodeCount > episodesPerRange
    }

    static func ranges(forEpisodeCount episodeCount: Int) -> [EpisodeRange] {
        guard episodeCount > 0 else { return [] }

        return stride(from: 0, to: episodeCount, by: episodesPerRange).map { lowerBound in
            EpisodeRange(
                lowerBound: lowerBound,
                upperBound: min(lowerBound + episodesPerRange, episodeCount)
            )
        }
    }

    static func boundedWindow<Element>(
        in elements: [Element],
        preferredIndex: Int?,
        maximumCount: Int = maximumUpNextEpisodes
    ) -> [Element] {
        guard !elements.isEmpty, maximumCount > 0 else { return [] }

        let windowCount = min(maximumCount, elements.count)
        let centeredIndex = min(max(preferredIndex ?? 0, 0), elements.count - 1)
        let leadingCount = windowCount / 2
        let startIndex = min(max(centeredIndex - leadingCount, 0), elements.count - windowCount)
        let endIndex = startIndex + windowCount
        return Array(elements[startIndex..<endIndex])
    }
}

/// The picker has exactly one presentation state; range and focus are valid only while shown.
enum EpisodePickerPresentation: Equatable {
    case hidden
    case presented(range: EpisodeRange, focusedEpisodeID: Int)
}

struct EpisodePickerDestination: Identifiable, Equatable {
    let id = "detail.episode-picker"
}

@MainActor
@Observable
final class EpisodePickerViewModel {
    private(set) var episodes: [PGCEpisode] = []
    private(set) var ranges: [EpisodeRange] = []
    private(set) var presentation: EpisodePickerPresentation = .hidden
    private var lastFocusedEpisodeID: Int?

    var presentedDestination: EpisodePickerDestination? {
        guard case .presented = presentation else { return nil }
        return EpisodePickerDestination()
    }

    var selectedRange: EpisodeRange? {
        guard case .presented(let range, _) = presentation else { return nil }
        return range
    }

    var focusedEpisode: PGCEpisode? {
        guard case .presented(_, let episodeID) = presentation else { return nil }
        return episodes.first(where: { $0.id == episodeID })
    }

    var selectedEpisodes: [PGCEpisode] {
        guard let selectedRange else { return [] }
        return Array(episodes[selectedRange.lowerBound..<selectedRange.upperBound])
    }

    func configure(episodes: [PGCEpisode], preferredEpisodeID: Int?) {
        self.episodes = episodes
        ranges = EpisodeNavigation.ranges(forEpisodeCount: episodes.count)
        presentation = .hidden

        guard !episodes.isEmpty else { return }
        lastFocusedEpisodeID = episode(for: preferredEpisodeID)?.id ?? episodes[0].id
    }

    func present() {
        guard !episodes.isEmpty else { return }

        switch presentation {
        case .hidden:
            let initialEpisode = episode(for: lastFocusedEpisodeID) ?? episodes[0]
            let initialRange = range(containing: initialEpisode) ?? ranges[0]
            presentation = .presented(range: initialRange, focusedEpisodeID: initialEpisode.id)
        case .presented:
            break
        }
    }

    func dismiss() {
        presentation = .hidden
    }

    func select(range selectedRange: EpisodeRange) {
        guard ranges.contains(selectedRange) else { return }
        let focusedID =
            focusedEpisode.flatMap { episode in
                range(containing: episode) == selectedRange ? episode.id : nil
            } ?? episodes[selectedRange.lowerBound].id
        lastFocusedEpisodeID = focusedID
        presentation = .presented(range: selectedRange, focusedEpisodeID: focusedID)
    }

    func focus(episode: PGCEpisode) {
        guard let selectedRange, range(containing: episode) == selectedRange else { return }
        lastFocusedEpisodeID = episode.id
        presentation = .presented(range: selectedRange, focusedEpisodeID: episode.id)
    }

    private func episode(for episodeID: Int?) -> PGCEpisode? {
        guard let episodeID else { return nil }
        return episodes.first(where: { $0.id == episodeID })
    }

    private func range(containing episode: PGCEpisode) -> EpisodeRange? {
        guard let index = episodes.firstIndex(where: { $0.id == episode.id }) else { return nil }
        return ranges.first(where: { $0.contains(index: index) })
    }
}
