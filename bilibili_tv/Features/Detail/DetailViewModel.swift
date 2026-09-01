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

    /// 详情页播放请求解析（阶段一）：封装原内联 cover 的 fallback 链——
    /// epId = episode?.epId ?? episode?.id ?? feedItem.episodeId（详情未加载完成时
    /// 保留 feed 入口标识）；title = seasonTitle ?? title ?? feedItem.title；
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
}
extension DetailViewModel {
    /// 详情页 mock 数据：.loaded 态，含 3 集选集，供焦点导航 UI 测试与 snapshot 基准使用。
    static var mock: DetailViewModel {
        let vm = DetailViewModel(feedItem: mockFeedItem)
        vm.seasonDetail = makeSeasonDetail(evaluate: "昔日校花秋雅的婚礼正在隆重举行……", episodeCount: 3)
        vm.state = .loaded
        return vm
    }

    /// 长简介 + 多选集 mock：`-uitestMockDetailLongSynopsis` 专用。evaluate 足够长,
    /// 展开简介后会把「选集」横向行整体推下首屏折线;6 集让卡片超出左侧按钮列,
    /// 复现"选集卡越靠右,↑ 越找不到上方候选"的横向几何失配(卡1→播放、卡2→追剧、
    /// 卡3→简介、卡4+→↑ 被吞)。
    /// 与默认 mock 分离:默认 mock 的短简介/3 集同时是 snapshot 基准,不宜改动。
    static var longSynopsisMock: DetailViewModel {
        let vm = DetailViewModel(feedItem: mockFeedItem)
        vm.seasonDetail = makeSeasonDetail(evaluate: longSynopsis, episodeCount: 6)
        vm.state = .loaded
        return vm
    }

    /// mock 详情页 feedItem(默认/长简介变体共用)
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
                    longTitle: episodeLongTitles[index],
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

    /// 长简介文案:展开后(无 lineLimit)把选集行推下 1080pt 首屏折线
    private static var longSynopsis: String {
        [
            "夏洛特烦恼是一部让人笑中带泪的青春喜剧电影,由闫非、彭大魔执导,",
            "沈腾、马丽领衔主演,讲述了一个平凡中年男人的奇幻追梦之旅。",
            "影片以一场婚礼开场,夏洛在发小婚礼上借酒消愁,却在马桶上做了一场",
            "穿越回高中时代的梦:他重新追求心爱的女孩秋雅,凭借“记忆”里的",
            "流行歌曲一夜成名,成为众人追捧的乐坛巨星,也让母亲过上了好日子。",
            "然而功成名就的背后,他渐渐发现身边人都在利用自己:经纪人把他当",
            "摇钱树,昔日好友一个个疏远,就连曾经嫌弃他的校花也只是图他的",
            "名声与财富。夜深人静时,他愈发怀念那个陪他吃苦的傻姑娘马冬梅,",
            "怀念那个破旧却温暖的小家,怀念一碗简单的茴香打卤面。",
            "当梦醒时分,他终于明白:人生最珍贵的不是名利与光环,而是那些",
            "平淡日子里不离不弃的陪伴。影片用荒诞的梦境包裹真挚的情感,",
            "在密集的笑点与怀旧金曲背后,藏着对亲情、友情与爱情的深刻思考,",
            "让观众在爆笑之余也能感受到生活的温度与力量。",
            "该片上映后收获票房与口碑双丰收,成为国产喜剧电影的经典之作,",
            "片中多首经典老歌更是一度掀起全民怀旧热潮。",
            "三十多年后,夏洛依然会梦见那场婚礼,梦见那碗热气腾腾的打卤面,",
            "梦见马冬梅在巷口等他放学回家的身影。每一个平凡的日子都值得",
            "被认真对待,每一份细水长流的陪伴都值得被好好珍惜。影片用",
            "温暖明亮的镜头语言,把那些被生活磨平棱角的普通人,重新点亮。",
            "这正是喜剧的力量:让人笑着笑着,就流下了眼泪。"
        ]
        .joined(separator: "\n")
    }
}
