import Foundation

/// Bilibili API 端点集中定义。
/// 统一持有 host + path + queryItems，业务代码不再内联裸 URL 字符串。
enum BilibiliAPI {
    // MARK: - Feed / 榜单

    /// 电影频道 Feed 瀑布流
    case movieFeed(cursor: Int)

    /// TV 端页面模块 (modpage_v2)
    case tvModPage(pageId: Int)

    /// 电影频道热播榜
    case movieRankList(day: Int, seasonType: Int)

    // MARK: - PGC 详情

    /// 影视/番剧/纪录片 Season 详情
    case seasonDetail(seasonId: Int?, epId: Int?)

    /// 单集详情 (pgc/view/web/ep)
    case epDetail(epId: Int)

    // MARK: - 播放

    /// PGC 标准播放流
    case playURL(epId: Int?, cid: Int?, qn: Int)

    /// OGV DRM 预检探针
    case drmCheck(epId: Int?, cid: Int?, qn: Int)

    // MARK: - 登录

    /// 生成扫码登录二维码
    case qrGenerate

    /// 轮询二维码扫码状态
    case qrPoll(qrcodeKey: String)

    // MARK: - 历史 / 心跳

    /// 拉取用户观看历史
    case history(ps: Int)

    /// PGC 观看进度心跳上报
    case heartbeat

    // MARK: - 弹幕

    /// 弹幕分段接口 (seg.so)
    case danmakuSegment(cid: Int, segmentIndex: Int)

    /// 基础主机：扫码登录走 passport，其余走 api
    private var baseURLString: String {
        switch self {
        case .qrGenerate, .qrPoll:
            return "https://passport.bilibili.com"
        default:
            return "https://api.bilibili.com"
        }
    }

    /// 端点完整 URL（host + path）
    var urlString: String {
        baseURLString + path
    }

    var path: String {
        switch self {
        case .movieFeed:
            return "/pgc/page/web/feed"
        case .tvModPage:
            return "/x/tv/modpage_v2"
        case .movieRankList:
            return "/pgc/season/rank/web/list"
        case .seasonDetail:
            return "/pgc/view/web/season"
        case .epDetail:
            return "/pgc/view/web/ep"
        case .playURL:
            return "/pgc/player/web/playurl"
        case .drmCheck:
            return "/ogv/player/pre/check/drm"
        case .qrGenerate:
            return "/x/passport-login/web/qrcode/generate"
        case .qrPoll:
            return "/x/passport-login/web/qrcode/poll"
        case .history:
            return "/x/v2/history"
        case .heartbeat:
            return "/x/click-interface/web/heartbeat"
        case .danmakuSegment:
            return "/x/v2/dm/list/seg.so"
        }
    }

    var queryItems: [URLQueryItem] {
        switch self {
        case .movieFeed(let cursor):
            return [
                URLQueryItem(name: "name", value: "movie"),
                URLQueryItem(name: "coursor", value: "\(cursor)"),
                URLQueryItem(name: "new_cursor_status", value: "true")
            ]
        case .tvModPage(let pageId):
            return [
                URLQueryItem(name: "page_id", value: "\(pageId)"),
                URLQueryItem(name: "fourk", value: "1"),
                URLQueryItem(name: "build", value: "108700"),
                URLQueryItem(name: "mobi_app", value: "android_tv_yst"),
                URLQueryItem(name: "platform", value: "android")
            ]
        case .movieRankList(let day, let seasonType):
            return [
                URLQueryItem(name: "day", value: "\(day)"),
                URLQueryItem(name: "season_type", value: "\(seasonType)")
            ]
        case .seasonDetail(let seasonId, let epId):
            var items = [URLQueryItem]()
            if let seasonId {
                items.append(URLQueryItem(name: "season_id", value: "\(seasonId)"))
            }
            if let epId {
                items.append(URLQueryItem(name: "ep_id", value: "\(epId)"))
            }
            return items
        case .epDetail(let epId):
            return [URLQueryItem(name: "ep_id", value: "\(epId)")]
        case .playURL(let epId, let cid, let qn):
            var items = [
                URLQueryItem(name: "qn", value: "\(qn)"),
                URLQueryItem(name: "fnval", value: "4048"),
                URLQueryItem(name: "fnver", value: "0"),
                URLQueryItem(name: "fourk", value: "1")
            ]
            if let epId {
                items.append(URLQueryItem(name: "ep_id", value: "\(epId)"))
            }
            if let cid {
                items.append(URLQueryItem(name: "cid", value: "\(cid)"))
            }
            return items
        case .drmCheck(let epId, let cid, let qn):
            var items = [
                URLQueryItem(name: "drm_tech_type", value: "2"),
                URLQueryItem(name: "qn", value: "\(qn)"),
                URLQueryItem(name: "fnval", value: "4048"),
                URLQueryItem(name: "fnver", value: "0"),
                URLQueryItem(name: "fourk", value: "1")
            ]
            if let epId {
                items.append(URLQueryItem(name: "ep_id", value: "\(epId)"))
            }
            if let cid {
                items.append(URLQueryItem(name: "cid", value: "\(cid)"))
            }
            return items
        case .qrGenerate:
            return []
        case .qrPoll(let qrcodeKey):
            return [URLQueryItem(name: "qrcode_key", value: qrcodeKey)]
        case .history(let ps):
            return [URLQueryItem(name: "ps", value: "\(ps)")]
        case .heartbeat:
            return []
        case .danmakuSegment(let cid, let segmentIndex):
            return [
                URLQueryItem(name: "type", value: "1"),
                URLQueryItem(name: "oid", value: "\(cid)"),
                URLQueryItem(name: "segment_index", value: "\(segmentIndex)")
            ]
        }
    }
}
