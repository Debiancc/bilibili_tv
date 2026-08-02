import Foundation
import Observation

@Observable
@MainActor
class MovieDetailViewModel {
    var seasonDetail: PGCSeasonDetail?
    var isLoading: Bool = false
    var errorMessage: String? = nil
    
    // Fallback data from FeedItem before full detail is loaded
    var feedItem: FeedItem
    
    init(feedItem: FeedItem) {
        self.feedItem = feedItem
    }
    
    func fetchDetail() async {
        guard seasonDetail == nil && !isLoading else { return }
        
        // We use either seasonId or episodeId
        let sId = feedItem.seasonId
        let eId = feedItem.episodeId
        
        guard sId != nil || eId != nil else {
            print("⚠️ [MovieDetailViewModel] Missing both seasonId and episodeId, cannot fetch details.")
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        do {
            print("🚀 [MovieDetailViewModel] Fetching season detail for seasonId: \(sId ?? -1) or epId: \(eId ?? -1)...")
            self.seasonDetail = try await BilibiliService.shared.fetchSeasonDetail(seasonId: sId, epId: eId)
            print("✅ [MovieDetailViewModel] Fetched detail for: \(self.seasonDetail?.title ?? "Unknown")")
            self.isLoading = false
        } catch {
            print("❌ [MovieDetailViewModel] Error fetching details: \(error.localizedDescription)")
            self.errorMessage = error.localizedDescription
            self.isLoading = false
        }
    }
    
    // Helper computed properties that prefer full detail, fallback to feedItem
    var title: String {
        seasonDetail?.title ?? feedItem.title ?? "Unknown Title"
    }
    
    var coverURL: URL? {
        if let fullCover = seasonDetail?.cover {
            var s = fullCover
            if s.hasPrefix("//") { s = "https:" + s }
            if s.hasPrefix("http://") { s = s.replacingOccurrences(of: "http://", with: "https://") }
            if !s.contains("@") { s += "@3840w_2160h_1e.webp" }
            if let url = URL(string: s) { return url }
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
