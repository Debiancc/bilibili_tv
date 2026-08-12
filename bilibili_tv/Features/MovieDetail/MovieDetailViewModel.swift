import Foundation
import Observation

/// 详情页所需的网络服务抽象，便于 ViewModel 注入 Mock 进行行为断言测试（参照 FeedServicing）
@MainActor
protocol MovieDetailServicing: Sendable {
    func fetchSeasonDetail(seasonId: Int?, epId: Int?) async throws -> PGCSeasonDetail
}

extension BilibiliService: MovieDetailServicing {}

@Observable
@MainActor
class MovieDetailViewModel {
    var seasonDetail: PGCSeasonDetail?

    /// 详情页加载状态机（互斥 enum，杜绝 isLoading/errorMessage 布尔可选拼接的非法态）
    var state: MovieDetailState = .idle

    // Fallback data from FeedItem before full detail is loaded
    var feedItem: FeedItem

    private let service: any MovieDetailServicing

    init(feedItem: FeedItem, service: any MovieDetailServicing = BilibiliService.shared) {
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
            print("⚠️ [MovieDetailViewModel] Missing both seasonId and episodeId, cannot fetch details.")
            return
        }

        state = .loading

        do {
            print("🚀 [MovieDetailViewModel] Fetching season detail for seasonId: \(sId ?? -1) or epId: \(eId ?? -1)...")
            self.seasonDetail = try await service.fetchSeasonDetail(seasonId: sId, epId: eId)
            print("✅ [MovieDetailViewModel] Fetched detail for: \(self.seasonDetail?.title ?? "Unknown")")
            self.state = .loaded
        } catch {
            print("❌ [MovieDetailViewModel] Error fetching details: \(error.localizedDescription)")
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
}
extension MovieDetailViewModel {
    /// 详情页 mock 数据：.loaded 态，含 3 集选集，供焦点导航 UI 测试与 snapshot 基准使用。
    static var mock: MovieDetailViewModel {
        let feedItem = FeedItem(
            title: "夏洛特烦恼",
            subtitle: "马冬梅的排列组合",
            cover: "https://i0.hdslb.com/bfs/bangumi/image/4276bcae64678156b596c4bba2e98876ed74e65d.png@3840w_2160h_1e.webp",
            rating: "9.5", badge: "DRM", link: "", episodeId: 320_665, seasonId: 33_354,
            stat: FeedStat(view: 34_320_099, danmaku: 0), rank: 1, indexShow: nil, rankTag: nil,
            brief: "昔日校花秋雅的婚礼正在隆重举行……", overlayImg: nil, logo: nil,
            ogvFusionInfo: OgvFusionInfo(category: "喜剧", tag: nil), newEp: nil, desc: nil
        )

        let detail = PGCSeasonDetail(
            seasonId: 33_354,
            seasonTitle: "夏洛特烦恼",
            title: "夏洛特烦恼",
            typeName: "电影",
            cover: "https://i0.hdslb.com/bfs/bangumi/image/4276bcae64678156b596c4bba2e98876ed74e65d.png@3840w_2160h_1e.webp",
            squareCover: nil,
            evaluate: "昔日校花秋雅的婚礼正在隆重举行……",
            alias: nil,
            rating: PGCRating(score: 9.5, count: 1_234),
            areas: [],
            styles: ["喜剧", "青春"],
            publish: PGCPublishInfo(pubTime: "2015-09-27 00:00:00", pubTimeShow: "2015年", isFinish: 1, isStarted: 1),
            stat: nil,
            actors: nil,
            staff: nil,
            episodes: [
                PGCEpisode(
                    parsedId: 1, epId: 320_665, aid: nil, cid: nil, bvid: nil,
                    title: "1", longTitle: "梦回青春", cover: "https://i0.hdslb.com/bfs/archive/cover1.jpg",
                    badge: nil, duration: 6_281_000, link: nil, showTitle: nil
                ),
                PGCEpisode(
                    parsedId: 2, epId: 320_666, aid: nil, cid: nil, bvid: nil,
                    title: "2", longTitle: "婚礼风波", cover: "https://i0.hdslb.com/bfs/archive/cover2.jpg",
                    badge: nil, duration: 6_122_000, link: nil, showTitle: nil
                ),
                PGCEpisode(
                    parsedId: 3, epId: 320_667, aid: nil, cid: nil, bvid: nil,
                    title: "3", longTitle: "梦想成真", cover: "https://i0.hdslb.com/bfs/archive/cover3.jpg",
                    badge: nil, duration: 5_980_000, link: nil, showTitle: nil
                )
            ],
            section: [],
            seasons: [],
            payment: nil,
            rights: nil,
            userStatus: nil
        )

        let vm = MovieDetailViewModel(feedItem: feedItem)
        vm.seasonDetail = detail
        vm.state = .loaded
        return vm
    }
}
