import Foundation

extension BilibiliService {
    /// 综合搜索（PGC-only）：只返回 media_bangumi / media_ft 分组的结果
    func fetchSearch(keyword: String, page: Int = 1) async throws -> [SearchResultSection] {
        let api = BilibiliAPI.search(keyword: keyword, page: page)
        let response: SearchResponse = try await execute(
            urlString: api.urlString,
            method: "GET",
            queryItems: api.queryItems
        )
        if response.code != 0 {
            throw NSError(
                domain: "BilibiliSearchError",
                code: response.code,
                userInfo: [NSLocalizedDescriptionKey: response.message ?? "搜索失败"]
            )
        }
        guard let data = response.data else {
            throw NSError(
                domain: "BilibiliSearchError",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Empty search data"]
            )
        }
        return data.sections.filter(\.isPGC)
    }
}
