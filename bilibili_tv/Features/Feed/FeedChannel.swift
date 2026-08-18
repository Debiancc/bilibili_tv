import Foundation

/// PGC 频道分类（Bilibili TV 端 modpage 频道页与榜单 season_type 的语义对）
enum FeedChannel: Hashable, CaseIterable, Identifiable {
    /// 电影（TV 频道页 page_id=459，榜单 season_type=2）
    case movie
    /// 番剧/动画（TV 频道页 page_id=461，榜单 season_type=1）
    case anime

    var id: Self { self }

    /// 频道页 modpage page_id（与官方 TV 端一致：459=电影、461=番剧）
    var modPageID: Int {
        switch self {
        case .movie: return 459
        case .anime: return 461
        }
    }

    /// 榜单接口 season_type（1=番剧、2=电影、3=纪录片、4=国创、5=电视剧、7=综艺）
    var rankSeasonType: Int {
        switch self {
        case .movie: return 2
        case .anime: return 1
        }
    }

    /// 侧栏展示名
    var title: String {
        switch self {
        case .movie: return "电影"
        case .anime: return "番剧"
        }
    }

    /// 侧栏图标（SF Symbol）
    var iconName: String {
        switch self {
        case .movie: return "film"
        case .anime: return "sparkles.tv"
        }
    }
}
