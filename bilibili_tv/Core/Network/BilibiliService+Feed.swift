import Foundation

extension BilibiliService {
    /// 电影频道 Feed 瀑布流列表请求
    func fetchMovieFeed(cursor: Int = 0) async throws -> FeedData {
        let urlString = "https://api.bilibili.com/pgc/page/web/feed"
        let queryItems = [
            URLQueryItem(name: "name", value: "movie"),
            URLQueryItem(name: "coursor", value: "\(cursor)"),
            URLQueryItem(name: "new_cursor_status", value: "true")
        ]
        
        let feedResponse: FeedResponse = try await execute(
            urlString: urlString,
            method: "GET",
            queryItems: queryItems
        )
        
        if feedResponse.code != 0 {
            throw NSError(domain: "BilibiliFeedError", code: feedResponse.code, userInfo: [NSLocalizedDescriptionKey: feedResponse.message])
        }
        
        guard let feedData = feedResponse.data else {
            throw NSError(domain: "BilibiliFeedError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Empty feed data"])
        }
        
        return feedData
    }
}
