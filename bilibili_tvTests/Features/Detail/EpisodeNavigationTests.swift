import Testing

@testable import bilibili_tv

@Suite(.serialized)
@MainActor
struct EpisodeNavigationTests {
    @Test func rangesIncludeFinalPartialRange() {
        let ranges = EpisodeNavigation.ranges(forEpisodeCount: 1_120)

        #expect(ranges.count == 12)
        #expect(ranges.first?.displayLabel == "1-100")
        #expect(ranges.last?.displayLabel == "1101-1120")
    }

    @Test func quickJumpRequiresMoreThanOneHundredEpisodes() {
        #expect(!EpisodeNavigation.supportsQuickJump(episodeCount: 100))
        #expect(EpisodeNavigation.supportsQuickJump(episodeCount: 101))
    }

    @Test func boundedWindowCentersAndClampsAtEdges() {
        let episodes = Array(1...1_120)

        let firstWindow = EpisodeNavigation.boundedWindow(in: episodes, preferredIndex: 0)
        let middleWindow = EpisodeNavigation.boundedWindow(in: episodes, preferredIndex: 799)
        let finalWindow = EpisodeNavigation.boundedWindow(in: episodes, preferredIndex: 1_119)

        #expect(firstWindow == Array(1...20))
        #expect(middleWindow == Array(790...809))
        #expect(finalWindow == Array(1_101...1_120))
    }

    @Test func pickerMovesFocusedEpisodeIntoSelectedRange() throws {
        let picker = EpisodePickerViewModel()
        let episodes = makeEpisodes(count: 1_120)
        picker.configure(episodes: episodes, preferredEpisodeID: 800)
        picker.present()

        #expect(picker.selectedRange?.displayLabel == "701-800")
        #expect(picker.focusedEpisode?.id == 800)

        let targetRange = try #require(picker.ranges.first(where: { $0.displayLabel == "1001-1100" }))
        picker.select(range: targetRange)

        #expect(picker.selectedRange == targetRange)
        #expect(picker.focusedEpisode?.id == 1_001)
    }

    private func makeEpisodes(count: Int) -> [PGCEpisode] {
        (1...count).map { index in
            PGCEpisode(
                parsedId: index,
                epId: index,
                aid: nil,
                cid: nil,
                bvid: nil,
                title: "\(index)",
                longTitle: "测试剧集 \(index)",
                cover: nil,
                badge: nil,
                duration: nil,
                link: nil,
                showTitle: nil
            )
        }
    }
}
