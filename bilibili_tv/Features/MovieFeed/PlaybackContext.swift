import Foundation

/// 统一播放请求模型，封装各入口（Hero 横幅 / 续播 shelf 等）所需全部参数。
/// `fullScreenCover(item:)` 以 `id` 驱动呈现：每次调用工厂生成全新 `id`，
/// 保证同一内容重复播放也能重新呈现 cover。
struct PlaybackContext: Identifiable, Equatable {
    let id = UUID()
    let epId: Int?
    let seasonId: Int?
    let title: String?
    let subtitle: String?
    let coverURL: URL?
    let resumeTime: Double

    /// 值语义相等性：忽略 `id`（每个实例唯一），仅比较播放参数。
    /// 含义 = "两个上下文描述同一次播放请求"，供状态断言与单测使用。
    static func == (lhs: PlaybackContext, rhs: PlaybackContext) -> Bool {
        lhs.epId == rhs.epId
            && lhs.seasonId == rhs.seasonId
            && lhs.title == rhs.title
            && lhs.subtitle == rhs.subtitle
            && lhs.coverURL == rhs.coverURL
            && lhs.resumeTime == rhs.resumeTime
    }

    /// Hero 横幅播放：从头播放
    static func banner(_ item: FeedItem) -> PlaybackContext {
        PlaybackContext(
            epId: item.episodeId,
            seasonId: item.seasonId,
            title: item.title,
            subtitle: item.subtitle,
            coverURL: item.secureCoverURL,
            resumeTime: 0
        )
    }

    /// 续播 shelf 播放：从上次进度续播
    static func resume(_ entry: LocalWatchHistoryEntry) -> PlaybackContext {
        PlaybackContext(
            epId: entry.epId,
            seasonId: entry.seasonId,
            title: entry.title,
            subtitle: entry.episodeTitle,
            coverURL: entry.secureCoverURL,
            resumeTime: Double(entry.progress)
        )
    }

    /// 详情页选集播放：从头播放。epId 缺失时回落到 `episode.id`（parsedId）；
    /// `episode` 为 nil（空选集兜底）时表达"整季/无选集"播放意图，epId 保持 nil，
    /// title/subtitle/coverURL 由调用方按 season/feedItem 兜底链解析后传入。
    static func episode(
        _ episode: PGCEpisode?,
        seasonId: Int?,
        title: String?,
        subtitle: String?,
        coverURL: URL?
    ) -> PlaybackContext {
        PlaybackContext(
            epId: episode?.epId ?? episode?.id,
            seasonId: seasonId,
            title: title,
            subtitle: subtitle,
            coverURL: coverURL,
            resumeTime: 0
        )
    }
}
