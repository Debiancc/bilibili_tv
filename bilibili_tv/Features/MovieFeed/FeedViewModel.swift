import Foundation
import Observation

/// Feed 主页所需的网络服务抽象，便于 ViewModel 注入 Mock 进行行为断言测试
@MainActor
protocol FeedServicing: Sendable {
    func fetchTVModPage(pageId: Int) async throws -> TVModPageResponse
    func fetchMovieRankList(day: Int, seasonType: Int) async throws -> [FeedItem]
}

extension BilibiliService: FeedServicing {}

/// 🌟 特性 1：使用 Swift 6 原生 @Observable 宏全量替换废弃的 ObservableObject + @Published
@Observable
@MainActor
class FeedViewModel {
    var rankMovies: [FeedItem] = []
    var exclusiveMovies: [FeedItem] = []
    var comingSoonMovies: [FeedItem] = []

    var bannerMovies: [FeedItem] = []

    /// 继续观看列表 (本地播放记录,为空时隐藏对应 shelf)
    var resumeItems: [LocalWatchHistoryEntry] = []

    /// 主页加载状态机（互斥 enum，杜绝 isLoading/errorMessage 布尔可选拼接的非法态）
    var state: FeedState = .idle

    private let service: any FeedServicing

    init(service: any FeedServicing = BilibiliService.shared) {
        self.service = service
    }

    func fetchInitialFeed() async {
        // 幂等守卫：仅从 idle/failed 发起加载，loading/loaded 直接返回
        switch state {
        case .idle, .failed:
            break
        case .loading, .loaded:
            return
        }
        state = .loading

        // ▶️ 本地续播数据独立于远程请求先加载:
        // 远程分类失败时仍保留下 shelf,离线启动也能直接续播
        self.resumeItems = LocalWatchHistoryStore.shared.fetchResumeItems()

        do {
            print("🚀 [FeedViewModel] Fetching movie categories from TV Modpage API...")

            async let modPageResponse = try service.fetchTVModPage(pageId: 459)
            async let rankListResponse = try service.fetchMovieRankList(day: 3, seasonType: 2)

            let (modPage, rankList) = try await (modPageResponse, rankListResponse)

            var banner: [FeedItem] = []

            if let modules = modPage.data {
                for module in modules {
                    if module.type == TVModuleType.banner.rawValue, let items = module.data {
                        banner = items
                    } else if module.type == TVModuleType.exclusive.rawValue, let items = module.data {
                        self.exclusiveMovies = items
                    } else if module.type == TVModuleType.comingSoon.rawValue, let items = module.data {
                        self.comingSoonMovies = items
                    }
                }
            }

            self.rankMovies = rankList
            self.bannerMovies = banner
            // ▶️ 续播数据源 = 本地播放记录;远程历史接口 (fetchWatchHistory) 为预留 API
            self.resumeItems = LocalWatchHistoryStore.shared.fetchResumeItems()

            // swiftlint:disable line_length
            print(
                "✅ [FeedViewModel] Fetched \(self.rankMovies.count) rank, \(self.exclusiveMovies.count) exclusive, \(self.comingSoonMovies.count) coming soon, \(self.bannerMovies.count) banners, \(self.resumeItems.count) resume."
            )
            // swiftlint:enable line_length
            self.state = .loaded
        } catch {
            print("❌ [FeedViewModel] Error fetching categories: \(error.localizedDescription)")
            self.state = .failed(message: error.localizedDescription)
        }
    }

    /// 刷新继续观看列表 (播放器退出/播完后回 feed 时刷新进度,数据源为本地记录)
    func fetchResumeWatching() async {
        let items = LocalWatchHistoryStore.shared.fetchResumeItems()
        if items != resumeItems {
            resumeItems = items
            print("🔄 [FeedViewModel] Resume shelf refreshed: \(items.count) items")
        }
    }
}

extension FeedViewModel {
    static var mock: FeedViewModel {
        let vm = FeedViewModel()

        let mockItems = [
            FeedItem(
                title: "秦牧化身月亮守，获得史诗级载具！",
                subtitle: "放牛少年，放牧诸神",
                cover: "https://i0.hdslb.com/bfs/tvcover/27260be861e6a8b8e5931f1e265fd771ec36c970.png",
                rating: "9.6", badge: "独播", link: "", episodeId: 4_983_242, seasonId: 45_969,
                stat: FeedStat(view: 1_990_000_000, danmaku: 0),
                rank: 1, indexShow: "更新至第93话", rankTag: nil, brief: nil,
                overlayImg: nil,
                logo: "https://i0.hdslb.com/bfs/tvcover/cc4cc486bfdfbb36b765f67b5a45d6e818d8a053.png",
                ogvFusionInfo: OgvFusionInfo(category: "国创", tag: "热血 神魔 奇幻"),
                newEp: nil, desc: nil
            ),
            FeedItem(
                title: "近战五行神兽？这是一场单方面的碾压！",
                subtitle: "仙魔双修，唯我独尊",
                cover: "https://i0.hdslb.com/bfs/tvcover/c695966b4899393fc051760594daf89ca2fb30a9.png",
                rating: "8.6", badge: "出品", link: "", episodeId: 774_373, seasonId: 35_213,
                stat: FeedStat(view: 850_000_000, danmaku: 0),
                rank: 2, indexShow: "全82话", rankTag: nil, brief: nil,
                overlayImg: nil, logo: nil,
                ogvFusionInfo: OgvFusionInfo(category: "国创", tag: "战斗 奇幻 玄幻"),
                newEp: nil, desc: nil
            ),
            FeedItem(
                title: "嫌疑人畏罪潜逃27年终落网",
                subtitle: "守护解放西",
                cover: "https://i0.hdslb.com/bfs/tvcover/1b83bce5d8b7a9c6ea6ce62fd8b52928ce2ec004.png",
                rating: "9.8", badge: "热门", link: "", episodeId: 4_791_294, seasonId: 124_647,
                stat: FeedStat(view: 140_000_000, danmaku: 0),
                rank: 3, indexShow: "更新至第9集", rankTag: nil, brief: nil,
                overlayImg: nil, logo: nil,
                ogvFusionInfo: OgvFusionInfo(category: "纪录片", tag: "罪案 社会"),
                newEp: nil, desc: nil
            )
        ]

        vm.rankMovies = Array(mockItems.prefix(3))
        vm.exclusiveMovies = Array(mockItems.prefix(2))
        vm.comingSoonMovies = Array(mockItems.prefix(2))
        vm.bannerMovies = Array(mockItems.prefix(3))
        vm.resumeItems = [
            LocalWatchHistoryEntry(
                seasonId: 29_310,
                epId: 307_457,
                cid: 164_789_275,
                title: "异度侵入 ID:INVADED",
                episodeTitle: "CHANNELED",
                coverURLString: "https://i0.hdslb.com/bfs/archive/dfc29be381565ee041a0ec9cfc7a32f8a63f76cd.jpg",
                progress: 925,
                duration: 1_481,
                viewAt: 1_588_831_600
            )
        ]
        vm.state = .loaded
        return vm
    }
}
