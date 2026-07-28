import Foundation
import Observation

/// 🌟 特性 1：使用 Swift 6 原生 @Observable 宏全量替换废弃的 ObservableObject + @Published
@Observable
@MainActor
class FeedViewModel {
    var rankMovies: [FeedItem] = []
    var exclusiveMovies: [FeedItem] = []
    var comingSoonMovies: [FeedItem] = []
    
    var bannerMovies: [FeedItem] = []
    
    var isLoading: Bool = false
    var errorMessage: String? = nil
    
    func fetchInitialFeed() async {
        guard rankMovies.isEmpty, exclusiveMovies.isEmpty, comingSoonMovies.isEmpty, !isLoading else { return }
        isLoading = true
        errorMessage = nil
        
        do {
            print("🚀 [FeedViewModel] Fetching movie categories from Web InitialState...")
            
            let state = try await BilibiliService.shared.fetchMovieWebInitialState()
            
            var rank: [FeedItem] = []
            var exclusive: [FeedItem] = []
            var comingSoon: [FeedItem] = []
            
            // Extract from ext modules
            if let exts = state.modules?.ext {
                for ext in exts {
                    guard let title = ext.title else { continue }
                    if title == "电影热播榜", let items = ext.items {
                        rank = items
                    } else if title == "独家热播", let items = ext.items {
                        exclusive = items
                    } else if title == "即将上线", let items = ext.items {
                        comingSoon = items
                    }
                }
            }
            
            self.rankMovies = rank
            self.exclusiveMovies = exclusive
            self.comingSoonMovies = comingSoon
            
            // Extract banner items
            if let banners = state.modules?.banner?.items, !banners.isEmpty {
                self.bannerMovies = banners
            } else {
                self.bannerMovies = Array(rank.prefix(5))
            }
            
            print("✅ [FeedViewModel] Fetched \(rank.count) rank, \(exclusive.count) exclusive, \(comingSoon.count) coming soon, \(bannerMovies.count) banners.")
            self.isLoading = false
        } catch {
            print("❌ [FeedViewModel] Error fetching categories: \(error.localizedDescription)")
            self.errorMessage = error.localizedDescription
            self.isLoading = false
        }
    }
}

extension FeedViewModel {
    static var mock: FeedViewModel {
        let vm = FeedViewModel()
        let mockItem = FeedItem(title: "夏洛特烦恼", subtitle: "马冬梅的排列组合", cover: "https://i0.hdslb.com/bfs/bangumi/image/136d1616456e60732d3c84e40e0f925e5e119003.jpg", rating: "9.5", badge: "DRM", link: "", episodeId: 320665, seasonId: 33354, stat: FeedStat(view: 34320099, danmaku: 0), rank: 1, indexShow: nil, rankTag: nil, brief: nil)
        
        vm.rankMovies = [mockItem, mockItem, mockItem]
        vm.exclusiveMovies = [mockItem, mockItem]
        vm.comingSoonMovies = [mockItem, mockItem, mockItem]
        vm.bannerMovies = [mockItem, mockItem, mockItem]
        vm.isLoading = false
        return vm
    }
}
