import Foundation
import Observation

/// 详情页所需的网络服务抽象，便于 ViewModel 注入 Mock 进行行为断言测试（参照 FeedServicing）
@MainActor
protocol DetailServicing: Sendable {
    func fetchSeasonDetail(seasonId: Int?, epId: Int?) async throws -> PGCSeasonDetail
}

extension BilibiliService: DetailServicing {}

@Observable
@MainActor
class DetailViewModel {
    var seasonDetail: PGCSeasonDetail?

    /// 详情页加载状态机（互斥 enum，杜绝 isLoading/errorMessage 布尔可选拼接的非法态）
    var state: DetailState = .idle

    // Fallback data from FeedItem before full detail is loaded
    var feedItem: FeedItem
    let episodePicker = EpisodePickerViewModel()

    private let service: any DetailServicing

    init(feedItem: FeedItem, service: any DetailServicing = BilibiliService.shared) {
        self.feedItem = feedItem
        self.service = service
    }

    func fetchDetail() async {
        // 幂等守卫：仅从 idle/failed 发起加载，loading/loaded 直接返回
        switch state {
        case .idle, .failed:
            break
        case .loading, .loaded:
            return
        }

        // We use either seasonId or episodeId
        let sId = feedItem.seasonId
        let eId = feedItem.episodeId

        guard sId != nil || eId != nil else {
            print("⚠️ [DetailViewModel] Missing both seasonId and episodeId, cannot fetch details.")
            return
        }

        state = .loading

        do {
            print("🚀 [DetailViewModel] Fetching season detail for seasonId: \(sId ?? -1) or epId: \(eId ?? -1)...")
            self.seasonDetail = try await service.fetchSeasonDetail(seasonId: sId, epId: eId)
            configureEpisodePicker()
            print("✅ [DetailViewModel] Fetched detail for: \(self.seasonDetail?.title ?? "Unknown")")
            self.state = .loaded
        } catch {
            print("❌ [DetailViewModel] Error fetching details: \(error.localizedDescription)")
            self.state = .failed(message: error.localizedDescription)
        }
    }

    // Helper computed properties that prefer full detail, fallback to feedItem
    var title: String {
        seasonDetail?.title ?? feedItem.title ?? "Unknown Title"
    }

    var coverURL: URL? {
        if let fullCover = seasonDetail?.cover {
            let url = ImageURL.secure(fullCover)
                .map { ImageURL.cdn($0, suffix: "@3840w_2160h_1e.webp") }
                .flatMap(URL.init(string:))
            if let url { return url }
        }
        return feedItem.secureOverlayURL ?? feedItem.highResCoverURL ?? feedItem.secureCoverURL
    }

    var typeNameText: String? {
        seasonDetail?.typeName ?? feedItem.ogvFusionInfo?.category
    }

    var pubYear: String? {
        // pubTime usually looks like "2012-07-24 10:00:00"
        if let time = seasonDetail?.publish?.pubTime, time.count >= 4 {
            let yearPrefix = String(time.prefix(4))
            if Int(yearPrefix) != nil {
                return yearPrefix + "年"
            }
        }

        // Fallback
        if let timeShow = seasonDetail?.publish?.pubTimeShow, timeShow.count >= 4 {
            let yearPrefix = String(timeShow.prefix(4))
            if Int(yearPrefix) != nil {
                return yearPrefix + "年"
            }
            return timeShow
        }

        return seasonDetail?.publish?.pubTimeShow ?? seasonDetail?.publish?.pubTime
    }

    var description: String? {
        seasonDetail?.evaluate ?? feedItem.brief
    }

    var stylesText: String? {
        guard let styles = seasonDetail?.styles, !styles.isEmpty else { return nil }
        return styles.joined(separator: " · ")
    }

    var ratingText: String? {
        if let score = seasonDetail?.rating?.score {
            return String(format: "%.1f", score)
        }
        return feedItem.rating
    }

    var episodes: [PGCEpisode] {
        seasonDetail?.episodes ?? []
    }

    /// The detail page only renders a small playback-neighbourhood; long-distance choice lives in the picker.
    var upNextEpisodes: [PGCEpisode] {
        let preferredIndex = episodes.firstIndex(where: { $0.id == resumedEpisodeID })
        return EpisodeNavigation.boundedWindow(in: episodes, preferredIndex: preferredIndex)
    }

    var supportsQuickJump: Bool {
        EpisodeNavigation.supportsQuickJump(episodeCount: episodes.count)
    }

    func presentEpisodePicker() {
        episodePicker.present()
    }

    func dismissEpisodePicker() {
        episodePicker.dismiss()
    }

    func configureEpisodePicker() {
        episodePicker.configure(episodes: episodes, preferredEpisodeID: resumedEpisodeID)
    }

    /// 详情页播放请求解析（阶段一）：封装原内联 cover 的 fallback 链——
    /// epId 链路见 PlaybackContext.episode（epId/parsedId 双 nil 时才回落 feed 入口标识，
    /// ⚠️ 严禁经 episode?.id 回落，原因见其注释）；title = seasonTitle ?? title ?? feedItem.title；
    /// subtitle = episode.formattedTitle ?? feedItem.subtitle；
    /// cover = episode.cover ?? seasonDetail.cover ?? feedItem.cover → secure + webp→jpg。
    func playbackContext(for episode: PGCEpisode?) -> PlaybackContext {
        PlaybackContext.episode(
            episode,
            seasonId: seasonDetail?.seasonId ?? feedItem.seasonId,
            title: seasonDetail?.seasonTitle ?? seasonDetail?.title ?? feedItem.title,
            subtitle: episode?.formattedTitle ?? feedItem.subtitle,
            coverURL: playbackCoverURL(for: episode?.cover ?? seasonDetail?.cover ?? feedItem.cover),
            fallbackEpId: feedItem.episodeId
        )
    }

    private func playbackCoverURL(for raw: String?) -> URL? {
        ImageURL.secure(raw).map(ImageURL.webpToJpg).flatMap(URL.init(string:))
    }

    private var resumedEpisodeID: Int? {
        LocalWatchHistoryStore.shared
            .resumeItem(forSeasonID: seasonDetail?.seasonId ?? feedItem.seasonId)?
            .epId
    }
}
extension DetailViewModel {
    /// 详情页 mock 数据：.loaded 态，含 3 集选集，供焦点导航 UI 测试与 snapshot 基准使用。
    static var mock: DetailViewModel {
        mock(episodeCount: 3)
    }

    /// 可配置集数的详情页 mock；长剧 UI / 性能回归使用 1,120 集治具。
    static func mock(episodeCount: Int) -> DetailViewModel {
        let vm = DetailViewModel(feedItem: mockFeedItem)
        vm.seasonDetail = makeSeasonDetail(evaluate: "昔日校花秋雅的婚礼正在隆重举行……", episodeCount: episodeCount)
        vm.configureEpisodePicker()
        vm.state = .loaded
        return vm
    }

    /// mock 详情页 feedItem
    private static var mockFeedItem: FeedItem {
        FeedItem(
            title: "夏洛特烦恼",
            subtitle: "马冬梅的排列组合",
            cover: "https://i0.hdslb.com/bfs/bangumi/image/4276bcae64678156b596c4bba2e98876ed74e65d.png@3840w_2160h_1e.webp",
            rating: "9.5", badge: "DRM", link: "", episodeId: 320_665, seasonId: 33_354,
            stat: FeedStat(view: 34_320_099, danmaku: 0), rank: 1, indexShow: nil, rankTag: nil,
            brief: "昔日校花秋雅的婚礼正在隆重举行……", overlayImg: nil, logo: nil,
            ogvFusionInfo: OgvFusionInfo(category: "喜剧", tag: nil), newEp: nil, desc: nil
        )
    }

    /// 默认 mock 的 .loaded 态 seasonDetail,仅 evaluate 文案与选集数量可变
    private static func makeSeasonDetail(evaluate: String, episodeCount: Int) -> PGCSeasonDetail {
        PGCSeasonDetail(
            seasonId: 33_354,
            seasonTitle: "夏洛特烦恼",
            title: "夏洛特烦恼",
            typeName: "电影",
            cover: "https://i0.hdslb.com/bfs/bangumi/image/4276bcae64678156b596c4bba2e98876ed74e65d.png@3840w_2160h_1e.webp",
            squareCover: nil,
            evaluate: evaluate,
            alias: nil,
            rating: PGCRating(score: 9.5, count: 1_234),
            areas: [],
            styles: ["喜剧", "青春"],
            publish: PGCPublishInfo(pubTime: "2015-09-27 00:00:00", pubTimeShow: "2015年", isFinish: 1, isStarted: 1),
            stat: nil,
            actors: nil,
            staff: nil,
            episodes: (0..<episodeCount).map { index in
                PGCEpisode(
                    parsedId: index + 1,
                    epId: 320_665 + index,
                    aid: nil, cid: nil, bvid: nil,
                    title: "\(index + 1)",
                    longTitle: episodeLongTitles[index % episodeLongTitles.count],
                    cover: "https://i0.hdslb.com/bfs/archive/cover\(index + 1).jpg",
                    badge: nil, duration: 6_000_000, link: nil, showTitle: nil
                )
            },
            section: [],
            seasons: [],
            payment: nil,
            rights: nil,
            userStatus: nil
        )
    }

    /// 选集长标题(mock 选集 a11y label = 「第N集 长标题」)
    private static let episodeLongTitles = [
        "梦回青春", "婚礼风波", "梦想成真",
        "天王巨星", "时光倒流", "梦醒时分",
        "第七集", "第八集", "第九集"
    ]
}
