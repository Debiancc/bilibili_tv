import Foundation

/// 观看历史接口响应 (GET https://api.bilibili.com/x/v2/history)
/// 旧版接口的 data 是数组(非新版 cursor 的 {cursor, list} 结构),PGC 条目自带 bangumi 剧集对象
struct WatchHistoryResponse: Codable {
    let code: Int
    let message: String?
    let data: [WatchHistoryEntry]

    /// data 缺省为空数组:字段缺失时等价位 nil,不破坏解码契约
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = try container.decode(Int.self, forKey: .code)
        message = try container.decodeIfPresent(String.self, forKey: .message)
        data = try container.decodeIfPresent([WatchHistoryEntry].self, forKey: .data) ?? []
    }

    enum CodingKeys: String, CodingKey {
        case code
        case message
        case data
    }
}

/// 剧集对象 (PGC 条目的 bangumi.season)
struct WatchHistorySeason: Codable, Hashable {
    let seasonId: Int?
    let title: String?
    let totalCount: Int?
    let isFinish: Int?

    enum CodingKeys: String, CodingKey {
        case seasonId = "season_id"
        case title
        case totalCount = "total_count"
        case isFinish = "is_finish"
    }
}

/// PGC 条目嵌套的 bangumi 剧集对象
struct WatchHistoryBangumi: Codable, Hashable {
    let epId: Int?
    let cover: String?
    let title: String?
    let season: WatchHistorySeason?

    enum CodingKeys: String, CodingKey {
        case epId = "ep_id"
        case cover
        case title
        case season
    }
}

/// 观看历史条目 (仅建模 PGC 需要的字段)
struct WatchHistoryEntry: Codable, Identifiable, Hashable {
    let title: String?
    let bangumi: WatchHistoryBangumi?
    let progress: Int
    let duration: Int
    let viewAt: Int
    let kid: Int?
    let business: String?
    let subType: Int?
    let cid: Int?

    enum CodingKeys: String, CodingKey {
        case title
        case bangumi
        case progress
        case duration
        case viewAt = "view_at"
        case kid
        case business
        case subType = "sub_type"
        case cid
    }

    var id: String {
        if let seasonId = bangumi?.season?.seasonId { return "ss-\(seasonId)" }
        return "ep-\(bangumi?.epId ?? 0)-\(viewAt)"
    }

    /// 剧集名称 (如 "异度侵入 ID:INVADED")
    var seasonTitle: String? {
        bangumi?.season?.title
    }

    /// 单集标题 (如 "12"/"第8话 庆忌(下)")
    var episodeTitle: String? {
        bangumi?.title
    }

    /// 封面 URL 字符串
    var coverURLString: String? {
        bangumi?.cover
    }

    /// 是否 PGC (番剧/影视) 条目
    var isPGC: Bool {
        business == "pgc" || bangumi != nil
    }

    /// 观看进度比例 (0...1),用于进度条
    var progressRatio: Double {
        guard duration > 0 else { return 0 }
        return min(max(Double(progress) / Double(duration), 0), 1)
    }

    /// 安全的 https 封面 URL (历史接口可能返回 http 直链)
    var secureCoverURL: URL? {
        ImageURL.secure(coverURLString).flatMap(URL.init(string:))
    }

    /// 用于续播的 FeedItem (复用详情页导航/卡片封面逻辑)
    var feedItem: FeedItem {
        FeedItem(
            title: seasonTitle ?? title,
            subtitle: episodeTitle,
            cover: coverURLString,
            rating: nil,
            badge: nil,
            link: nil,
            episodeId: bangumi?.epId,
            seasonId: bangumi?.season?.seasonId,
            stat: nil,
            rank: nil,
            indexShow: episodeTitle,
            rankTag: nil,
            brief: nil,
            overlayImg: nil,
            logo: nil,
            ogvFusionInfo: nil,
            newEp: nil,
            desc: nil
        )
    }
}
