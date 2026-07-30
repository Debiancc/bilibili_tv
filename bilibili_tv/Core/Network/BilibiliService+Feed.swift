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
    /// 爬取 B 站 TV 端的页面模块数据
    func fetchTVModPage(pageId: Int = 459) async throws -> TVModPageResponse {
        let urlString = "https://api.bilibili.com/x/tv/modpage_v2"
        let queryItems = [
            URLQueryItem(name: "page_id", value: "\(pageId)"),
            URLQueryItem(name: "fourk", value: "1"),
            URLQueryItem(name: "build", value: "108700"),
            URLQueryItem(name: "mobi_app", value: "android_tv_yst"),
            URLQueryItem(name: "platform", value: "android")
        ]
        
        let response: TVModPageResponse = try await execute(
            urlString: urlString,
            method: "GET",
            queryItems: queryItems
        )
        
        if response.code != 0 {
            throw NSError(domain: "BilibiliTVModPageError", code: response.code, userInfo: [NSLocalizedDescriptionKey: response.message])
        }
        
        return response
    }
}
