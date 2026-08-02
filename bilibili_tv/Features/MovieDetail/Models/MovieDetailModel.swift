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
    let areas: [PGCArea]?
    let styles: [String]?
    let publish: PGCPublishInfo?
    let stat: PGCStat?
    let actors: String?
    let staff: String?
    let episodes: [PGCEpisode]?
    let section: [PGCSection]?
    let seasons: [PGCRelatedSeason]?
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
        return parsedId ?? epId ?? 0
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
    let episodes: [PGCEpisode]?
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
