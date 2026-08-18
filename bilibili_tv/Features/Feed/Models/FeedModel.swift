import Foundation

struct FeedResponse: Codable {
    let code: Int
    let message: String
    let data: FeedData?
}

struct TVModPageResponse: Codable {
    let code: Int
    let message: String
    let data: [TVModPageModule]

    /// 模块列表缺省为空数组:字段缺失时等价位 nil,不破坏解码契约
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = try container.decode(Int.self, forKey: .code)
        message = try container.decode(String.self, forKey: .message)
        data = try container.decodeIfPresent([TVModPageModule].self, forKey: .data) ?? []
    }

    enum CodingKeys: String, CodingKey {
        case code
        case message
        case data
    }
}

extension TVModPageResponse {
    /// 显式成员初始化器:自定义 init(from:) 会吞掉合成的 memberwise init,供测试直接构造
    init(code: Int, message: String, data: [TVModPageModule]) {
        self.code = code
        self.message = message
        self.data = data
    }
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
    let data: [FeedItem]

    /// 模块内容缺省为空数组:字段缺失时等价位 nil,不破坏解码契约
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        type = try container.decode(Int.self, forKey: .type)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        data = try container.decodeIfPresent([FeedItem].self, forKey: .data) ?? []
    }

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case title
        case data
    }
}

extension TVModPageModule {
    /// 显式成员初始化器:自定义 init(from:) 会吞掉合成的 memberwise init,供测试直接构造
    init(id: Int, type: Int, title: String?, data: [FeedItem]) {
        self.id = id
        self.type = type
        self.title = title
        self.data = data
    }
}

struct FeedData: Codable {
    let coursor: Int?
    let hasNext: Bool
    let items: [FeedItem]

    /// items 缺省为空数组、hasNext 缺省为 false:字段缺失时等价位 nil,不破坏解码契约
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        coursor = try container.decodeIfPresent(Int.self, forKey: .coursor)
        hasNext = try container.decodeIfPresent(Bool.self, forKey: .hasNext) ?? false
        items = try container.decodeIfPresent([FeedItem].self, forKey: .items) ?? []
    }

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
    let list: [FeedItem]

    /// list 缺省为空数组:字段缺失时等价位 nil,不破坏解码契约
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hasNext = try container.decodeIfPresent(Int.self, forKey: .hasNext)
        list = try container.decodeIfPresent([FeedItem].self, forKey: .list) ?? []
    }

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
    let ext: [WebExtModule]

    /// ext 缺省为空数组:字段缺失时等价位 nil,不破坏解码契约
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        banner = try container.decodeIfPresent(WebBannerModule.self, forKey: .banner)
        ext = try container.decodeIfPresent([WebExtModule].self, forKey: .ext) ?? []
    }

    enum CodingKeys: String, CodingKey {
        case banner
        case ext
    }
}

struct WebBannerModule: Codable {
    let items: [FeedItem]

    /// items 缺省为空数组:字段缺失时等价位 nil,不破坏解码契约
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = try container.decodeIfPresent([FeedItem].self, forKey: .items) ?? []
    }

    enum CodingKeys: String, CodingKey {
        case items
    }
}

struct WebExtModule: Codable {
    let title: String?
    let items: [FeedItem]
    let hot: FeedItem?

    /// items 缺省为空数组:字段缺失时等价位 nil,不破坏解码契约
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        items = try container.decodeIfPresent([FeedItem].self, forKey: .items) ?? []
        hot = try container.decodeIfPresent(FeedItem.self, forKey: .hot)
    }

    enum CodingKeys: String, CodingKey {
        case title
        case items
        case hot
    }
}

struct FeedItem: Codable, Identifiable, Hashable {
    static func == (lhs: FeedItem, rhs: FeedItem) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    var id: String {
        if let ep = episodeId { return "ep-\(ep)" }
        if let ss = seasonId { return "ss-\(ss)" }
        // 回退分支追加 cover 区分:title+link 双 nil/空时,仅凭 title 可能碰撞(见 #34 review)
        return "title-\(title ?? "")-\(link ?? "")-\(cover ?? "")"
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
    let desc: String?

    private func cdnURL(from raw: String?, suffix: String) -> URL? {
        ImageURL.secure(raw).map { ImageURL.cdn($0, suffix: suffix) }.flatMap(URL.init(string:))
    }

    /// 列表流专用的极速轻量 CDN 缩略图 URL (@300w_450h_1c.webp 仅 15KB，极速加载防滑动卡顿)
    var secureCoverURL: URL? {
        // 追加 Bilibili 官方 CDN WebP 轻量切片参数，降低 99% 的内存与图片解码开销
        cdnURL(from: cover, suffix: "@300w_450h_1c.webp")
    }

    /// 详情页使用的原图高清晰度 URL
    var highResCoverURL: URL? {
        // 4K 级别（3840x2160 限制），等比例缩放不裁剪（1e），并强制转为 WebP
        cdnURL(from: cover, suffix: "@3840w_2160h_1e.webp")
    }

    var secureOverlayURL: URL? {
        cdnURL(from: overlayImg, suffix: "@3840w_2160h_1e.webp")
    }

    var secureLogoURL: URL? {
        cdnURL(from: logo, suffix: "@800w_300h_1e.webp")
    }

    var formattedViewCount: String? {
        guard let view = stat?.view, view > 0 else { return nil }
        if view >= 10_000 {
            let wan = Double(view) / 10_000.0
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
        if let badge = badge, badge.localizedCaseInsensitiveContains("DRM") {
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
        case desc
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
