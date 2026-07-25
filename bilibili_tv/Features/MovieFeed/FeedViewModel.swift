import Foundation
import Observation

/// 🌟 特性 1：使用 Swift 6 原生 @Observable 宏全量替换废弃的 ObservableObject + @Published
@Observable
@MainActor
class FeedViewModel {
    var items: [FeedItem] = []
    var isLoading: Bool = false
    var errorMessage: String? = nil
    
    private var currentCursor: Int = 0
    private var hasNextPage: Bool = true
    private var isFetchingPage: Bool = false
    
    /// 抓取初始第一页 Feed 流 (仅在列表为空时拉取，防止切换页面重复触发)
    func fetchInitialFeed() async {
        guard items.isEmpty, !isLoading else { return }
        isLoading = true
        errorMessage = nil
        currentCursor = 0
        hasNextPage = true
        
        do {
            print("🚀 [FeedViewModel] Fetching initial movie feed...")
            let feedData = try await BilibiliService.shared.fetchMovieFeed(cursor: 0)
            
            if let newItems = feedData.items {
                self.items = newItems
                print("✅ [FeedViewModel] Successfully fetched \(newItems.count) items, next cursor: \(feedData.coursor ?? 0)")
            }
            self.currentCursor = feedData.coursor ?? 0
            self.hasNextPage = feedData.hasNext ?? false
            self.isLoading = false
        } catch {
            print("❌ [FeedViewModel] Error fetching initial feed: \(error.localizedDescription)")
            self.errorMessage = error.localizedDescription
            self.isLoading = false
        }
    }
    
    /// 滚动触底分页拉取下一页
    func fetchNextPage() async {
        guard hasNextPage, !isFetchingPage, !isLoading else { return }
        isFetchingPage = true
        
        do {
            print("🔄 [FeedViewModel] Fetching next page, cursor: \(currentCursor)...")
            let feedData = try await BilibiliService.shared.fetchMovieFeed(cursor: currentCursor)
            
            if let newItems = feedData.items, !newItems.isEmpty {
                // 去重拼接
                let existingIds = Set(self.items.map { $0.id })
                let filteredNewItems = newItems.filter { !existingIds.contains($0.id) }
                self.items.append(contentsOf: filteredNewItems)
                print("✅ [FeedViewModel] Appended \(filteredNewItems.count) new items. Total: \(self.items.count)")
            }
            self.currentCursor = feedData.coursor ?? currentCursor
            self.hasNextPage = feedData.hasNext ?? false
            self.isFetchingPage = false
        } catch {
            print("⚠️ [FeedViewModel] Error fetching next page: \(error.localizedDescription)")
            self.isFetchingPage = false
        }
    }
}

extension FeedViewModel {
    static var mock: FeedViewModel {
        let vm = FeedViewModel()
        vm.items = [
            FeedItem(title: "夏洛特烦恼", subtitle: "马冬梅的排列组合", cover: "https://i0.hdslb.com/bfs/bangumi/image/136d1616456e60732d3c84e40e0f925e5e119003.jpg", rating: "9.5", badge: "DRM", link: "", episodeId: 320665, seasonId: 33354, stat: FeedStat(view: 34320099, danmaku: 0)),
            FeedItem(title: "九龙城寨之围城", subtitle: "拳拳到肉 以血还血", cover: "https://i0.hdslb.com/bfs/bangumi/image/72174fcb047bde585bbe2b711365d03125b4b3eb.png", rating: "9.4", badge: "独播", link: "", episodeId: 827164, seasonId: 47655, stat: FeedStat(view: 31927628, danmaku: 0)),
            FeedItem(title: "头号玩家", subtitle: "斯皮尔伯格科幻大片", cover: "http://i0.hdslb.com/bfs/bangumi/image/d1baef273cc7862431978b2e63fc04ccdd353556.png", rating: "9.7", badge: nil, link: "", episodeId: 682241, seasonId: 42384, stat: FeedStat(view: 32107874, danmaku: 0)),
            FeedItem(title: "阿甘正传", subtitle: "影史励志电影之最", cover: "http://i0.hdslb.com/bfs/bangumi/e67f90d0a248d94f7fc0b995ee786765193decd8.jpg", rating: "9.8", badge: nil, link: "", episodeId: 248180, seasonId: 25568, stat: FeedStat(view: 31175849, danmaku: 0))
        ]
        vm.isLoading = false
        return vm
    }
}
