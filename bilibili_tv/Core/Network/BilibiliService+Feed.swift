import Foundation

extension BilibiliService {
    /// 电影频道 Feed 瀑布流列表请求
    func fetchFeed(cursor: Int = 0) async throws -> FeedData {
        let api = BilibiliAPI.feed(cursor: cursor)

        let feedResponse: FeedResponse = try await execute(
            urlString: api.urlString,
            method: "GET",
            queryItems: api.queryItems
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
        let api = BilibiliAPI.tvModPage(pageId: pageId)

        let response: TVModPageResponse = try await execute(
            urlString: api.urlString,
            method: "GET",
            queryItems: api.queryItems
        )

        if response.code != 0 {
            throw NSError(domain: "BilibiliTVModPageError", code: response.code, userInfo: [NSLocalizedDescriptionKey: response.message])
        }

        return response
    }

    /// 抓取电影频道的专属热播榜（解决 modpage 是横图导致样式被破坏的问题）
    func fetchRankList(day: Int = 3, seasonType: Int = 2) async throws -> [FeedItem] {
        let api = BilibiliAPI.rankList(day: day, seasonType: seasonType)

        let response: PGCListResponse = try await execute(
            urlString: api.urlString,
            method: "GET",
            queryItems: api.queryItems
        )

        if response.code != 0 {
            throw NSError(domain: "BilibiliRankError", code: response.code, userInfo: [NSLocalizedDescriptionKey: response.message ?? "Unknown error"])
        }

        return response.data?.list ?? []
    }
}
