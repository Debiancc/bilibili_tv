import Foundation

struct FeedResponse: Codable {
    let code: Int
    let message: String
    let data: FeedData?
}

struct TVModPageResponse: Codable {
    let code: Int
    let message: String
    let data: [TVModPageModule]?
}

enum TVModuleType: Int, Codable {
    case banner = 61
    case rank = 39
    case exclusive = 63
    case comingSoon = 64
}

struct TVModPageModule: Codable {
    let id: Int
    let type: Int
    let title: String?
    let data: [FeedItem]?
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

    var id: String { 
        if let ep = episodeId { return "ep-\(ep)" }
        if let ss = seasonId { return "ss-\(ss)" }
        return "title-\(title ?? "")-\(link ?? "")" 
    }
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
    let overlayImg: String?
    let logo: String?
    let ogvFusionInfo: OgvFusionInfo?
    let newEp: NewEpInfo?

    private func cdnURL(from raw: String?, suffix: String) -> URL? {
        guard var s = raw, !s.isEmpty else { return nil }
        if s.hasPrefix("//") {
            s = "https:" + s
        } else if s.hasPrefix("http://") {
            s = s.replacingOccurrences(of: "http://", with: "https://")
        }
        if !s.contains("@") {
            s += suffix
        }
        return URL(string: s)
    }

    /// 列表流专用的极速轻量 CDN 缩略图 URL (@300w_450h_1c.webp 仅 15KB，极速加载防滑动卡顿)
    var secureCoverURL: URL? {
        // 追加 Bilibili 官方 CDN WebP 轻量切片参数，降低 99% 的内存与图片解码开销
        return cdnURL(from: cover, suffix: "@300w_450h_1c.webp")
    }
    
    /// 详情页使用的原图高清晰度 URL
    var highResCoverURL: URL? {
        // 4K 级别（3840x2160 限制），等比例缩放不裁剪（1e），并强制转为 WebP
        return cdnURL(from: cover, suffix: "@3840w_2160h_1e.webp")
    }
    
    var secureOverlayURL: URL? {
        return cdnURL(from: overlayImg, suffix: "@3840w_2160h_1e.webp")
    }
    
    var secureLogoURL: URL? {
        return cdnURL(from: logo, suffix: "@800w_300h_1e.webp")
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

        if let indexShow = indexShow, !indexShow.isEmpty {
            return indexShow
        }
        
        if let newEpShow = newEp?.indexShow, !newEpShow.isEmpty {
            return newEpShow
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
        case overlayImg = "overlay_img"
        case logo
        case ogvFusionInfo = "ogv_fusion_info"
        case newEp = "new_ep"
    }
}

struct NewEpInfo: Codable, Hashable {
    let indexShow: String?
    
    enum CodingKeys: String, CodingKey {
        case indexShow = "index_show"
    }
}

struct OgvFusionInfo: Codable, Hashable {
    let category: String?
    let tag: String?
}

struct FeedStat: Codable, Hashable {
    let view: Int
    let danmaku: Int
}
