import Foundation

extension BilibiliService {
    /// 请求 Bilibili 影视/OGV 播放流 (包含 OGV DRM 预检接口与 PGC 标准接口双通道降级)
    func fetchPlayURL(epId: Int? = nil, cid: Int? = nil, seasonId: Int? = nil, qn: Int = 120) async throws -> PlayURLResult {
        var finalEpId = epId
        var finalCid = cid

        // 仅当完全没有 ep_id 时才查 season detail 拿首集兜底
        // ⚠️ 不能用 `finalEpId == nil || finalCid == nil`:选集场景只有 epId 没有 cid,
        // 若 cid 缺失就兜底,会把用户选的具体集覆盖成首集 (bug: 选中文版 4690416 实际播放原版 4448452)
        // PGC 播放接口以 ep_id 为主键,有 epId 即可解析,cid 仅作补充
        if finalEpId == nil, let sId = seasonId {
            print("🔍 [Network] Missing ep_id, fetching season detail for season_id: \(sId)...")
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
        var result = try await fetchPGCPlayURL(epId: finalEpId, cid: finalCid, qn: qn)
        // 💬 playurl 响应不含 cid 字段,把已解析的 cid 补进去(弹幕 seg.so 的 oid 需要)
        if result.cid == nil {
            result.cid = finalCid
        }
        return result
        // }
    }

    /// 轮播预告片流 URL 短期内存缓存条目:URL 带签名与过期时间,TTL 内直接命中
    private final class BannerPreviewCacheEntry {
        let url: String
        let fetchedAt: Date

        init(url: String, fetchedAt: Date) {
            self.url = url
            self.fetchedAt = fetchedAt
        }
    }

    /// 轮播预告片流 URL 缓存(键: epId-cid-seasonId-qn):
    /// 频道切换/详情返回等场景会对同一素材反复取流,TTL 内命中可避免每次进出 feed
    /// 都发网络请求;TTL 上限须低于流 URL 的签名有效期(30s~数分钟级)
    private static let bannerPreviewURLCache = NSCache<NSString, BannerPreviewCacheEntry>()
    private static let bannerPreviewURLTTL: TimeInterval = 300

    /// 🔤 轮播横幅背景视频取流:轻量 MP4(fnval=1,单文件含音轨)供裸 AVPlayer 播放。
    /// 优先 durl[0](标准 MP4);durl 缺失时回退 DASH 视频轨 base_url
    /// (⚠️ DASH 音画分离,回退轨无音频——仅当全部 banner 配 sound_switch=false 时可接受)。
    /// - Returns: 可直接交给 AVPlayerItem 的 URL
    func fetchBannerPreviewURL(epId: Int?, cid: Int?, seasonId: Int?, qn: Int = 64) async throws -> String {
        let cacheKey =
            "\(String(describing: epId))-\(String(describing: cid))-\(String(describing: seasonId))-\(qn)"
            as NSString
        if let entry = Self.bannerPreviewURLCache.object(forKey: cacheKey),
            Date().timeIntervalSince(entry.fetchedAt) < Self.bannerPreviewURLTTL
        {
            return entry.url
        }
        let api = BilibiliAPI.bannerVideoURL(epId: epId, cid: cid, seasonId: seasonId, qn: qn)
        let response: PlayURLResponse = try await execute(
            urlString: api.urlString,
            method: "GET",
            queryItems: api.queryItems
        )
        guard response.code == 0, let result = response.activeResult else {
            throw NSError(
                domain: "BilibiliPlayError", code: response.code,
                userInfo: [
                    NSLocalizedDescriptionKey: response.message
                ])
        }
        let url: String
        if let mp4 = result.durl.first?.url {
            url = mp4
        } else if let dashVideo = result.dash?.video.first?.baseUrl {
            url = dashVideo
        } else {
            throw NSError(domain: "BilibiliPlayError", code: -2, userInfo: [NSLocalizedDescriptionKey: "Empty banner preview streams"])
        }
        Self.bannerPreviewURLCache.setObject(
            BannerPreviewCacheEntry(url: url, fetchedAt: Date()),
            forKey: cacheKey
        )
        return url
    }

    /// 按 ep_id 查询对应集的 cid (弹幕接口 seg.so 的 oid)
    /// playurl 响应不含 cid 字段,需从 season detail 匹配或 ep 详情兜底
    func fetchEpisodeCid(epId: Int, seasonId: Int?) async throws -> Int? {
        // 通道 1:season detail 中按 ep_id 匹配当前集
        if let seasonId = seasonId {
            let api = BilibiliAPI.seasonDetail(seasonId: seasonId, epId: nil)
            let response: SeasonDetailResponse = try await execute(
                urlString: api.urlString,
                method: "GET",
                queryItems: api.queryItems
            )
            if response.code == 0,
                let episodes = response.result?.episodes,
                let match = episodes.first(where: { $0.id == epId || $0.ep_id == epId }),
                let cid = match.cid
            {
                return cid
            }
        }

        // 通道 2:ep 详情接口兜底
        let api = BilibiliAPI.epDetail(epId: epId)
        let response: EpDetailResponse = try await execute(
            urlString: api.urlString,
            method: "GET",
            queryItems: api.queryItems
        )
        return response.code == 0 ? response.result?.cid : nil
    }

    /// 获取剧集详情，解析出第一集的 ep_id 和 cid
    private func fetchFirstEpisodeInfo(seasonId: Int) async throws -> (epId: Int, cid: Int) {
        let api = BilibiliAPI.seasonDetail(seasonId: seasonId, epId: nil)

        let response: SeasonDetailResponse = try await execute(
            urlString: api.urlString,
            method: "GET",
            queryItems: api.queryItems
        )

        if response.code != 0 {
            throw NSError(domain: "BilibiliSeasonError", code: response.code, userInfo: [NSLocalizedDescriptionKey: response.message ?? "Unknown Error"])
        }

        guard let firstEp = response.result?.episodes.first,
            let epId = firstEp.id ?? firstEp.ep_id,
            let cid = firstEp.cid
        else {
            throw NSError(domain: "BilibiliSeasonError", code: -1, userInfo: [NSLocalizedDescriptionKey: "No episodes found for this season."])
        }

        return (epId, cid)
    }

    /// 匹配官方网页端的 OGV DRM 探针接口
    private func fetchOGVCheckDRM(epId: Int?, cid: Int?, qn: Int) async throws -> PlayURLResult {
        let api = BilibiliAPI.drmCheck(epId: epId, cid: cid, qn: qn)
        return try await executePlayRequest(urlString: api.urlString, queryItems: api.queryItems)
    }

    /// 标准 PGC 高清/DASH/4K 播放流接口
    private func fetchPGCPlayURL(epId: Int?, cid: Int?, qn: Int) async throws -> PlayURLResult {
        let api = BilibiliAPI.playURL(epId: epId, cid: cid, qn: qn)
        return try await executePlayRequest(urlString: api.urlString, queryItems: api.queryItems)
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
            playResult.dash?.video.isEmpty == false || playResult.durl.isEmpty == false
        else {
            throw NSError(domain: "BilibiliPlayError", code: -2, userInfo: [NSLocalizedDescriptionKey: "Empty media streams in response"])
        }

        print(
            "📥 [Network Incoming] \(urlString) HTTP 200 OK! Dash videos: \(playResult.dash?.video.count ?? 0), Durl segments: \(playResult.durl.count)")
        return playResult
    }
}
