import Foundation

extension BilibiliService {
    /// 请求 Bilibili 影视/OGV 播放流 (包含 OGV DRM 预检接口与 PGC 标准接口双通道降级)
    func fetchPlayURL(epId: Int? = nil, cid: Int? = nil, seasonId: Int? = nil, qn: Int = 120) async throws -> PlayURLResult {
        var finalEpId = epId
        var finalCid = cid
        
        // 如果缺失 ep_id 或 cid，但传入了 seasonId，则先查询 season detail 拿到首集 ep_id 和 cid
        if (finalEpId == nil || finalCid == nil), let sId = seasonId {
            print("🔍 [Network] Missing ep_id/cid, fetching season detail for season_id: \(sId)...")
            let (fetchedEpId, fetchedCid) = try await fetchFirstEpisodeInfo(seasonId: sId)
            finalEpId = fetchedEpId
            finalCid = fetchedCid
            print("✅ [Network] Resolved season_id: \(sId) -> ep_id: \(fetchedEpId), cid: \(fetchedCid)")
        }
        
        // 🌟 1. 优先通道：匹配官方网页端的 /ogv/player/pre/check/drm 预检探针 (已注释: 会导致-400错)
        // do {
        //     print("🌐 [Network Channel 1] Attempting OGV DRM Check API...")
        //     return try await fetchOGVCheckDRM(epId: finalEpId, cid: finalCid, qn: qn)
        // } catch {
        //     print("⚠️ [Network Warning] OGV DRM Check failed (\(error.localizedDescription)), falling back to PGC Web PlayURL API...")
            // 🌟 2. 备用通道：请求带全量清晰度控制的 PGC 标准接口 /pgc/player/web/playurl
            return try await fetchPGCPlayURL(epId: finalEpId, cid: finalCid, qn: qn)
        // }
    }
    
    /// 获取剧集详情，解析出第一集的 ep_id 和 cid
    private func fetchFirstEpisodeInfo(seasonId: Int) async throws -> (epId: Int, cid: Int) {
        let urlString = "https://api.bilibili.com/pgc/view/web/season"
        let queryItems = [
            URLQueryItem(name: "season_id", value: "\(seasonId)")
        ]
        
        let response: SeasonDetailResponse = try await execute(
            urlString: urlString,
            method: "GET",
            queryItems: queryItems
        )
        
        if response.code != 0 {
            throw NSError(domain: "BilibiliSeasonError", code: response.code, userInfo: [NSLocalizedDescriptionKey: response.message ?? "Unknown Error"])
        }
        
        guard let firstEp = response.result?.episodes?.first,
              let epId = firstEp.id ?? firstEp.ep_id,
              let cid = firstEp.cid else {
            throw NSError(domain: "BilibiliSeasonError", code: -1, userInfo: [NSLocalizedDescriptionKey: "No episodes found for this season."])
        }
        
        return (epId, cid)
    }
    
    /// 匹配官方网页端的 OGV DRM 探针接口
    private func fetchOGVCheckDRM(epId: Int?, cid: Int?, qn: Int) async throws -> PlayURLResult {
        let urlString = "https://api.bilibili.com/ogv/player/pre/check/drm"
        var queryItems = [
            URLQueryItem(name: "drm_tech_type", value: "2"),
            URLQueryItem(name: "qn", value: "\(qn)"),
            URLQueryItem(name: "fnval", value: "4048"),
            URLQueryItem(name: "fnver", value: "0"),
            URLQueryItem(name: "fourk", value: "1")
        ]
        if let epId = epId {
            queryItems.append(URLQueryItem(name: "ep_id", value: "\(epId)"))
        }
        if let cid = cid {
            queryItems.append(URLQueryItem(name: "cid", value: "\(cid)"))
        }
        
        return try await executePlayRequest(urlString: urlString, queryItems: queryItems)
    }
    
    /// 标准 PGC 高清/DASH/4K 播放流接口
    private func fetchPGCPlayURL(epId: Int?, cid: Int?, qn: Int) async throws -> PlayURLResult {
        let urlString = "https://api.bilibili.com/pgc/player/web/playurl"
        var queryItems = [
            URLQueryItem(name: "qn", value: "\(qn)"),
            URLQueryItem(name: "fnval", value: "4048"),
            URLQueryItem(name: "fnver", value: "0"),
            URLQueryItem(name: "fourk", value: "1")
        ]
        if let epId = epId {
            queryItems.append(URLQueryItem(name: "ep_id", value: "\(epId)"))
        }
        if let cid = cid {
            queryItems.append(URLQueryItem(name: "cid", value: "\(cid)"))
        }
        
        return try await executePlayRequest(urlString: urlString, queryItems: queryItems)
    }
    
    /// 执行播放流统一 API 解析
    private func executePlayRequest(urlString: String, queryItems: [URLQueryItem]) async throws -> PlayURLResult {
        let playResponse: PlayURLResponse = try await execute(
            urlString: urlString,
            method: "GET",
            queryItems: queryItems
        )
        
        if playResponse.code != 0 {
            throw NSError(domain: "BilibiliPlayError", code: playResponse.code, userInfo: [NSLocalizedDescriptionKey: playResponse.message])
        }
        
        guard let playResult = playResponse.activeResult,
              (playResult.dash?.video?.isEmpty == false || playResult.durl?.isEmpty == false) else {
            throw NSError(domain: "BilibiliPlayError", code: -2, userInfo: [NSLocalizedDescriptionKey: "Empty media streams in response"])
        }
        
        print("📥 [Network Incoming] \(urlString) HTTP 200 OK! Dash videos: \(playResult.dash?.video?.count ?? 0), Durl segments: \(playResult.durl?.count ?? 0)")
        return playResult
    }
}
