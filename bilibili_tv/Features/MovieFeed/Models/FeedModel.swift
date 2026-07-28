import Foundation

struct FeedResponse: Codable {
    let code: Int
    let message: String
    let data: FeedData?
}

struct FeedData: Codable {
    let coursor: Int?
    let hasNext: Bool?
    let items: [FeedItem]?

    enum CodingKeys: String, CodingKey {
        case coursor
        case hasNext = "has_next"
        case items
    }
}

struct PGCListResponse: Codable {
    let code: Int
    let message: String?
    let data: PGCListData?
}

struct PGCListData: Codable {
    let hasNext: Int?
    let list: [FeedItem]?
    
    enum CodingKeys: String, CodingKey {
        case hasNext = "has_next"
        case list
    }
}

struct WebInitialState: Codable {
    let modules: WebModules?
}

struct WebModules: Codable {
    let banner: WebBannerModule?
    let ext: [WebExtModule]?
}

struct WebBannerModule: Codable {
    let items: [FeedItem]?
}

struct WebExtModule: Codable {
    let title: String?
    let items: [FeedItem]?
    let hot: FeedItem?
}

struct FeedItem: Codable, Identifiable, Hashable {
    static func == (lhs: FeedItem, rhs: FeedItem) -> Bool {
        return lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    var id: String { "\(episodeId ?? seasonId ?? Int.random(in: 10000...99999))-\(title ?? "")" }
    let title: String?
    let subtitle: String?
    let cover: String?
    let rating: String?
    let badge: String?
    let link: String?
    let episodeId: Int?
    let seasonId: Int?
    let stat: FeedStat?
    let rank: Int?
    let indexShow: String?
    let rankTag: String?
    let brief: String?

    /// 列表流专用的极速轻量 CDN 缩略图 URL (@300w_450h_1c.webp 仅 15KB，极速加载防滑动卡顿)
    var secureCoverURL: URL? {
        guard var coverString = cover else { return nil }
        if coverString.hasPrefix("//") {
            coverString = "https:" + coverString
        } else if coverString.hasPrefix("http://") {
            coverString = coverString.replacingOccurrences(of: "http://", with: "https://")
        }
        // 追加 Bilibili 官方 CDN WebP 轻量切片参数，降低 99% 的内存与图片解码开销
        if !coverString.contains("@") {
            coverString += "@300w_450h_1c.webp"
        }
        return URL(string: coverString)
    }
    
    /// 详情页使用的原图高清晰度 URL
    var highResCoverURL: URL? {
        guard var coverString = cover else { return nil }
        if coverString.hasPrefix("//") {
            coverString = "https:" + coverString
        } else if coverString.hasPrefix("http://") {
            coverString = coverString.replacingOccurrences(of: "http://", with: "https://")
        }
        return URL(string: coverString)
    }

    var formattedViewCount: String? {
        guard let view = stat?.view, view > 0 else { return nil }
        if view >= 10000 {
            let wan = Double(view) / 10000.0
            return String(format: "%.1f万", wan)
        }
        return "\(view)"
    }
    
    /// 获取友好的展示副标题（如果有 rank 或 indexShow，优先展示）
    var displaySubtitle: String? {
        if let rankTag = rankTag, !rankTag.isEmpty {
            return rankTag
        }
        if let rank = rank {
            return "Top \(rank)"
        }
        if let indexShow = indexShow, !indexShow.isEmpty {
            return indexShow
        }
        return subtitle
    }
    
    /// 💡 是否包含 DRM 加密保护标志
    var isDRMProtected: Bool {
        if let badge = badge, (badge.localizedCaseInsensitiveContains("DRM") || badge.contains("独播")) {
            return true
        }
        if let title = title, title.localizedCaseInsensitiveContains("DRM") {
            return true
        }
        return false
    }

    enum CodingKeys: String, CodingKey {
        case title
        case subtitle = "sub_title"
        case cover
        case rating
        case badge
        case link
        case episodeId = "episode_id"
        case seasonId = "season_id"
        case stat
        case rank
        case indexShow = "index_show"
        case rankTag = "rank_tag"
        case brief
    }
}

struct FeedStat: Codable, Hashable {
    let view: Int
    let danmaku: Int
}
