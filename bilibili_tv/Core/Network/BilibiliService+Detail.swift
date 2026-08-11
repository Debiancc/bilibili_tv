import Foundation

extension BilibiliService {
    /// 请求 Bilibili 影视/番剧/纪录片 PGC Season 详细信息
    func fetchSeasonDetail(seasonId: Int? = nil, epId: Int? = nil) async throws -> PGCSeasonDetail {
        if seasonId == nil && epId == nil {
            throw NSError(domain: "BilibiliDetailError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Must provide either seasonId or epId"])
        }

        let api = BilibiliAPI.seasonDetail(seasonId: seasonId, epId: epId)

        let response: PGCSeasonDetailResponse = try await execute(
            urlString: api.urlString,
            method: "GET",
            queryItems: api.queryItems
        )

        if response.code != 0 {
            throw NSError(domain: "BilibiliDetailError", code: response.code, userInfo: [NSLocalizedDescriptionKey: response.message ?? "Unknown Error"])
        }

        guard let detail = response.result else {
            throw NSError(domain: "BilibiliDetailError", code: -2, userInfo: [NSLocalizedDescriptionKey: "Empty result data"])
        }

        return detail
    }
}
