import Foundation

struct FeedResponse: Codable {
    let code: Int
    let message: String
    let data: FeedData?
}

struct FeedData: Codable {
    let coursor: Int
    let hasNext: Bool
    let items: [FeedItem]

    enum CodingKeys: String, CodingKey {
        case coursor
        case hasNext = "has_next"
        case items
    }
}

struct FeedItem: Codable, Identifiable {
    var id: Int { episodeId }
    let title: String
    let subtitle: String
    let cover: String
    let rating: String?
    let link: String
    let episodeId: Int
    let seasonId: Int
    let stat: FeedStat?

    enum CodingKeys: String, CodingKey {
        case title
        case subtitle = "sub_title"
        case cover
        case rating
        case link
        case episodeId = "episode_id"
        case seasonId = "season_id"
        case stat
    }
}

struct FeedStat: Codable {
    let view: Int
    let danmaku: Int
}
