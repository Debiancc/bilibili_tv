import Foundation

struct PGCSeasonDetailResponse: Codable {
    let code: Int
    let message: String?
    let result: PGCSeasonDetail?
}

struct PGCSeasonDetail: Codable {
    let seasonId: Int
    let seasonTitle: String?
    let title: String?
    let typeName: String?
    let cover: String?
    let squareCover: String?
    let evaluate: String?
    let alias: String?
    let rating: PGCRating?
    let areas: [PGCArea]
    let styles: [String]
    let publish: PGCPublishInfo?
    let stat: PGCStat?
    let actors: String?
    let staff: String?
    let episodes: [PGCEpisode]
    let section: [PGCSection]
    let seasons: [PGCRelatedSeason]
    let payment: PGCPaymentInfo?
    let rights: PGCRightsInfo?
    let userStatus: PGCUserStatus?

    enum CodingKeys: String, CodingKey {
        case seasonId = "season_id"
        case seasonTitle = "season_title"
        case title
        case typeName = "type_name"
        case cover
        case squareCover = "square_cover"
        case evaluate
        case alias
        case rating
        case areas
        case styles
        case publish
        case stat
        case actors
        case staff
        case episodes
        case section
        case seasons
        case payment
        case rights
        case userStatus = "user_status"
    }

    /// 集合字段缺省为空数组:字段缺失时等价位 nil,不破坏解码契约
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        seasonId = try container.decode(Int.self, forKey: .seasonId)
        seasonTitle = try container.decodeIfPresent(String.self, forKey: .seasonTitle)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        typeName = try container.decodeIfPresent(String.self, forKey: .typeName)
        cover = try container.decodeIfPresent(String.self, forKey: .cover)
        squareCover = try container.decodeIfPresent(String.self, forKey: .squareCover)
        evaluate = try container.decodeIfPresent(String.self, forKey: .evaluate)
        alias = try container.decodeIfPresent(String.self, forKey: .alias)
        rating = try container.decodeIfPresent(PGCRating.self, forKey: .rating)
        areas = try container.decodeIfPresent([PGCArea].self, forKey: .areas) ?? []
        styles = try container.decodeIfPresent([String].self, forKey: .styles) ?? []
        publish = try container.decodeIfPresent(PGCPublishInfo.self, forKey: .publish)
        stat = try container.decodeIfPresent(PGCStat.self, forKey: .stat)
        actors = try container.decodeIfPresent(String.self, forKey: .actors)
        staff = try container.decodeIfPresent(String.self, forKey: .staff)
        episodes = try container.decodeIfPresent([PGCEpisode].self, forKey: .episodes) ?? []
        section = try container.decodeIfPresent([PGCSection].self, forKey: .section) ?? []
        seasons = try container.decodeIfPresent([PGCRelatedSeason].self, forKey: .seasons) ?? []
        payment = try container.decodeIfPresent(PGCPaymentInfo.self, forKey: .payment)
        rights = try container.decodeIfPresent(PGCRightsInfo.self, forKey: .rights)
        userStatus = try container.decodeIfPresent(PGCUserStatus.self, forKey: .userStatus)
    }
}

extension PGCSeasonDetail {
    /// 显式成员初始化器:自定义 init(from:) 会吞掉合成的 memberwise init,
    /// 此处按成员顺序保留,供 mock/测试直接构造
    init(
        seasonId: Int,
        seasonTitle: String? = nil,
        title: String? = nil,
        typeName: String? = nil,
        cover: String? = nil,
        squareCover: String? = nil,
        evaluate: String? = nil,
        alias: String? = nil,
        rating: PGCRating? = nil,
        areas: [PGCArea] = [],
        styles: [String] = [],
        publish: PGCPublishInfo? = nil,
        stat: PGCStat? = nil,
        actors: String? = nil,
        staff: String? = nil,
        episodes: [PGCEpisode] = [],
        section: [PGCSection] = [],
        seasons: [PGCRelatedSeason] = [],
        payment: PGCPaymentInfo? = nil,
        rights: PGCRightsInfo? = nil,
        userStatus: PGCUserStatus? = nil
    ) {
        self.seasonId = seasonId
        self.seasonTitle = seasonTitle
        self.title = title
        self.typeName = typeName
        self.cover = cover
        self.squareCover = squareCover
        self.evaluate = evaluate
        self.alias = alias
        self.rating = rating
        self.areas = areas
        self.styles = styles
        self.publish = publish
        self.stat = stat
        self.actors = actors
        self.staff = staff
        self.episodes = episodes
        self.section = section
        self.seasons = seasons
        self.payment = payment
        self.rights = rights
        self.userStatus = userStatus
    }
}

struct PGCRating: Codable {
    let score: Double?
    let count: Int?
}

struct PGCArea: Codable {
    let id: Int?
    let name: String?
}

struct PGCPublishInfo: Codable {
    let pubTime: String?
    let pubTimeShow: String?
    let isFinish: Int?
    let isStarted: Int?

    enum CodingKeys: String, CodingKey {
        case pubTime = "pub_time"
        case pubTimeShow = "pub_time_show"
        case isFinish = "is_finish"
        case isStarted = "is_started"
    }
}

struct PGCStat: Codable {
    let views: Int?
    let favorites: Int?
    let coins: Int?
    let likes: Int?
    let danmakus: Int?
    let seriesFollow: Int?

    enum CodingKeys: String, CodingKey {
        case views
        case favorites
        case coins
        case likes
        case danmakus
        case seriesFollow = "series_follow"
    }
}

struct PGCEpisode: Codable, Identifiable, Hashable {
    var id: Int {
        parsedId ?? epId ?? 0
    }

    let parsedId: Int?
    let epId: Int?
    let aid: Int?
    let cid: Int?
    let bvid: String?
    let title: String?
    let longTitle: String?
    let cover: String?
    let badge: String?
    let duration: Int?
    let link: String?
    let showTitle: String?

    var formattedTitle: String {
        if let showTitle = showTitle, !showTitle.isEmpty {
            return showTitle
        }

        var prefix = ""
        if let title = title, !title.isEmpty {
            if Int(title) != nil {
                prefix = "第\(title)集 "
            } else {
                prefix = "\(title) "
            }
        }
        let mainTitle = longTitle ?? ""
        return prefix + mainTitle
    }

    var formattedDuration: String? {
        guard let ms = duration else { return nil }
        let totalSeconds = ms / 1_000
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let secs = totalSeconds % 60
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%02d:%02d", minutes, secs)
        }
    }

    enum CodingKeys: String, CodingKey {
        case parsedId = "id"
        case epId = "ep_id"
        case aid
        case cid
        case bvid
        case title
        case longTitle = "long_title"
        case cover
        case badge
        case duration
        case link
        case showTitle = "show_title"
    }
}

struct PGCSection: Codable, Identifiable, Hashable {
    let id: Int
    let title: String?
    let episodes: [PGCEpisode]

    /// episodes 缺省为空数组:字段缺失时等价位 nil,不破坏解码契约
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        episodes = try container.decodeIfPresent([PGCEpisode].self, forKey: .episodes) ?? []
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case episodes
    }
}

struct PGCRelatedSeason: Codable, Identifiable, Hashable {
    var id: Int { seasonId }
    let seasonId: Int
    let seasonTitle: String?
    let cover: String?
    let badge: String?

    enum CodingKeys: String, CodingKey {
        case seasonId = "season_id"
        case seasonTitle = "season_title"
        case cover
        case badge
    }
}

struct PGCPaymentInfo: Codable {
    let price: String?
    let vipPromotion: String?

    enum CodingKeys: String, CodingKey {
        case price
        case vipPromotion = "vip_promotion"
    }
}

struct PGCRightsInfo: Codable {
    let areaLimit: Int?
    let isPreview: Int?
    let allowDownload: Int?

    enum CodingKeys: String, CodingKey {
        case areaLimit = "area_limit"
        case isPreview = "is_preview"
        case allowDownload = "allow_download"
    }
}

struct PGCUserStatus: Codable {
    let follow: Int?
    let pay: Int?
}
