import Foundation

/// 综合搜索响应包装（web 语义 `/x/web-interface/search/all/v2`）
struct SearchResponse: Decodable {
    let code: Int
    let message: String?
    let data: SearchData?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = try container.decode(Int.self, forKey: .code)
        message = try container.decodeIfPresent(String.self, forKey: .message)
        data = try container.decodeIfPresent(SearchData.self, forKey: .data)
    }

    enum CodingKeys: String, CodingKey {
        case code
        case message
        case data
    }
}

extension SearchResponse {
    init(code: Int, message: String?, data: SearchData?) {
        self.code = code
        self.message = message
        self.data = data
    }
}

/// 搜索结果数据：result 按 result_type 分组，PGC-only 只消费 media_bangumi / media_ft
struct SearchData: Decodable {
    let sections: [SearchResultSection]
    let numResults: Int?
    /// 总页数：search/all/v2 返回 `numPages`（实测字段），非 `pages`
    let numPages: Int?

    /// result 缺省为空数组、分页字段缺省为 nil：字段缺失不破坏解码契约
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sections = try container.decodeIfPresent([SearchResultSection].self, forKey: .result) ?? []
        numResults = try container.decodeIfPresent(Int.self, forKey: .numResults)
        numPages = try container.decodeIfPresent(Int.self, forKey: .numPages)
    }

    enum CodingKeys: String, CodingKey {
        case result
        case numResults
        case numPages
    }
}

extension SearchData {
    init(sections: [SearchResultSection], numResults: Int?, numPages: Int?) {
        self.sections = sections
        self.numResults = numResults
        self.numPages = numPages
    }
}

/// 搜索结果分组：result_type = media_bangumi(番剧/动画) / media_ft(影视)
struct SearchResultSection: Decodable, Hashable {
    let resultType: String
    let items: [SearchResultItem]

    /// 是否为 PGC 分组（本项目只展示这些）
    var isPGC: Bool {
        resultType == "media_bangumi" || resultType == "media_ft"
    }

    /// 分组展示名（对齐官方语义）
    var title: String {
        switch resultType {
        case "media_bangumi": return "番剧"
        case "media_ft": return "影视"
        default: return resultType
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        resultType = try container.decode(String.self, forKey: .resultType)
        items = try container.decodeIfPresent([SearchResultItem].self, forKey: .data) ?? []
    }

    enum CodingKeys: String, CodingKey {
        case resultType = "result_type"
        case data
    }
}

extension SearchResultSection {
    init(resultType: String, items: [SearchResultItem]) {
        self.resultType = resultType
        self.items = items
    }
}

/// 单个 PGC 搜索结果（media_bangumi / media_ft 共用字段集）
struct SearchResultItem: Decodable, Hashable, Identifiable {
    let seasonId: Int?
    let episodeId: Int?
    let title: String?
    let cover: String?
    let styles: String?
    let score: Double?
    let areas: [String]
    let goto: String?
    let desc: String?

    var id: String {
        if let ss = seasonId { return "ss-\(ss)" }
        if let ep = episodeId { return "ep-\(ep)" }
        return "title-\(title ?? "")-\(cover ?? "")"
    }

    /// 去掉搜索 API 返回的 `<em class="keyword">` 高亮标签
    var plainTitle: String? {
        guard let title else { return nil }
        return
            title
            .replacingOccurrences(of: #"</?em[^>]*>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        seasonId = try container.decodeIfPresent(Int.self, forKey: .seasonId)
        episodeId = try container.decodeIfPresent(Int.self, forKey: .episodeId)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        cover = try container.decodeIfPresent(String.self, forKey: .cover)
        styles = try container.decodeIfPresent(String.self, forKey: .styles)
        score = try container.decodeIfPresent(Double.self, forKey: .score)
        // areas 两种形态:media_ft 为字符串数组,media_bangumi 为 [{name:...}] 对象数组
        if let strings = try? container.decode([String].self, forKey: .areas) {
            areas = strings
        } else if let objects = try? container.decode([SearchAreaObject].self, forKey: .areas) {
            areas = objects.compactMap(\.name)
        } else {
            areas = []
        }
        goto = try container.decodeIfPresent(String.self, forKey: .goto)
        desc = try container.decodeIfPresent(String.self, forKey: .desc)
    }

    enum CodingKeys: String, CodingKey {
        case seasonId = "season_id"
        case episodeId = "episode_id"
        case title
        case cover
        case styles
        case score
        case areas
        case goto
        case desc
    }
}

/// media_bangumi 形态的 areas 元素：{ name: "日本" }
private struct SearchAreaObject: Decodable {
    let name: String?
}

extension SearchResultItem {
    init(
        seasonId: Int?,
        episodeId: Int?,
        title: String?,
        cover: String?,
        styles: String?,
        score: Double?,
        areas: [String],
        goto: String?,
        desc: String?
    ) {
        self.seasonId = seasonId
        self.episodeId = episodeId
        self.title = title
        self.cover = cover
        self.styles = styles
        self.score = score
        self.areas = areas
        self.goto = goto
        self.desc = desc
    }
}

extension SearchResultItem {
    /// 映射为 FeedItem（仅 seasonId/title/cover 驱动详情导航与卡片渲染，
    /// 其余字段沿用搜索语义或留空）
    var feedItem: FeedItem {
        FeedItem(
            title: plainTitle,
            subtitle: styles,
            cover: cover,
            rating: score.map { String(format: "%.1f", $0) },
            badge: nil,
            link: nil,
            episodeId: episodeId,
            seasonId: seasonId,
            stat: nil,
            rank: nil,
            indexShow: nil,
            rankTag: nil,
            brief: desc,
            overlayImg: nil,
            logo: nil,
            ogvFusionInfo: nil,
            newEp: nil,
            desc: desc
        )
    }
}
