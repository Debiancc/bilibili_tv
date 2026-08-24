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

    /// 🎬 轮播横幅背景视频来源(banner 模块返回的 play_focus):
    /// aid/cid/epid/season_id 定位"宣传片段",play_stime..play_etime 为取流后播放区间。
    /// 缺省 nil 表示该条目无背景视频(轮播保持纯图片+固定倒计时)。
    /// ⚠️ 刻意用 var 而非 let:合成 Decodable 对"带显式初始值且不可覆盖"的
    /// let 属性会跳过解码(编译警告),var 才能被 decodeIfPresent 覆盖。
    var playFocus: PlayFocus?

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
        case playFocus = "play_focus"
    }
}

/// 轮播横幅宣传视频来源(modpage banner 条目 play_focus 字段)。
/// 字段语义来自云视听小电视抓包(docs/captures/bilitv_workflow_20260807.har):
/// - aid/epid/season_id/cid:定位资源,取流时保持与抓包相同的 ep_id+cid+season_id 组合
/// - play_stime/play_etime:取流后播放区间(秒)。
///   times==0 → 区间播完触发翻页;times>0(实测 99999) → 循环播放该区间,翻页由计时器驱动
/// - sound_switch:声音开关(缺省视为 false=静音)
/// 仅保留播放链路必需字段;jump/backup/hidemark 等纯 UI 元数据省略。
struct PlayFocus: Codable, Hashable {
    let cover: String?
    let jumpType: Int?
    let jumpEp: Int?
    let playStime: Int?
    let playEtime: Int?
    let aid: Int?
    let cid: Int?
    let from: String?
    let epid: Int?
    let seasonId: Int?
    /// 声音开关:false(缺省)=静音,true=开声
    let soundSwitch: Bool
    let times: Int?
    let autoplayUri: String?

    enum CodingKeys: String, CodingKey {
        case cover
        case jumpType = "jump_type"
        case jumpEp = "jump_ep"
        case playStime = "play_stime"
        case playEtime = "play_etime"
        case aid
        case cid
        case from
        case epid
        case seasonId = "season_id"
        case soundSwitch = "sound_switch"
        case times
        case autoplayUri = "autoplay_uri"
    }

    /// 可缺省字段按 nil 解码;sound_switch 缺省按 false(静音)处理
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cover = try container.decodeIfPresent(String.self, forKey: .cover)
        jumpType = try container.decodeIfPresent(Int.self, forKey: .jumpType)
        jumpEp = try container.decodeIfPresent(Int.self, forKey: .jumpEp)
        playStime = try container.decodeIfPresent(Int.self, forKey: .playStime)
        playEtime = try container.decodeIfPresent(Int.self, forKey: .playEtime)
        aid = try container.decodeIfPresent(Int.self, forKey: .aid)
        cid = try container.decodeIfPresent(Int.self, forKey: .cid)
        from = try container.decodeIfPresent(String.self, forKey: .from)
        epid = try container.decodeIfPresent(Int.self, forKey: .epid)
        seasonId = try container.decodeIfPresent(Int.self, forKey: .seasonId)
        soundSwitch = try container.decodeIfPresent(Bool.self, forKey: .soundSwitch) ?? false
        times = try container.decodeIfPresent(Int.self, forKey: .times)
        autoplayUri = try container.decodeIfPresent(String.self, forKey: .autoplayUri)
    }

    /// 显式成员初始化器:自定义 init(from:) 会吞掉合成的 memberwise init,供测试/预览直接构造
    init(
        cover: String? = nil,
        jumpType: Int? = nil,
        jumpEp: Int? = nil,
        playStime: Int? = nil,
        playEtime: Int? = nil,
        aid: Int? = nil,
        cid: Int? = nil,
        from: String? = nil,
        epid: Int? = nil,
        seasonId: Int? = nil,
        soundSwitch: Bool = false,
        times: Int? = nil,
        autoplayUri: String? = nil
    ) {
        self.cover = cover
        self.jumpType = jumpType
        self.jumpEp = jumpEp
        self.playStime = playStime
        self.playEtime = playEtime
        self.aid = aid
        self.cid = cid
        self.from = from
        self.epid = epid
        self.seasonId = seasonId
        self.soundSwitch = soundSwitch
        self.times = times
        self.autoplayUri = autoplayUri
    }

    /// 播放区间时长(秒);字段缺失时返回 nil 交由调用方回退
    var durationSeconds: Double? {
        guard let start = playStime, let end = playEtime, end > start else { return nil }
        return Double(end - start)
    }

    /// 是否应循环播放该区间(times>0,实测 99999 即"无限循环直至翻页")
    var shouldLoop: Bool {
        (times ?? 0) > 0
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
