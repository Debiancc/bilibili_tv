import Foundation

/// 🎬 本地播放记录条目 (续播数据源)
/// 字段与远程观看历史 (WatchHistoryEntry) 对齐,但标题/封面来自播放时的元数据,
/// 不依赖服务端历史接口。按 season_id 去重,保留最新观看的一集。
struct LocalWatchHistoryEntry: Codable, Identifiable, Hashable {
    let seasonId: Int?
    let epId: Int?
    let cid: Int?
    let title: String
    let episodeTitle: String?
    let coverURLString: String?
    var progress: Int
    var duration: Int
    var viewAt: Int

    var id: String {
        seasonId.map { "ss-\($0)" } ?? "ep-\(epId ?? 0)"
    }

    /// 观看进度比例 (0...1),用于进度条
    var progressRatio: Double {
        guard duration > 0 else { return 0 }
        return min(max(Double(progress) / Double(duration), 0), 1)
    }

    /// 安全的 https 封面 URL (接口可能返回 http 直链)
    var secureCoverURL: URL? {
        guard var s = coverURLString, !s.isEmpty else { return nil }
        if s.hasPrefix("//") {
            s = "https:" + s
        } else if s.hasPrefix("http://") {
            s = s.replacingOccurrences(of: "http://", with: "https://")
        }
        return URL(string: s)
    }
}

/// 📼 本地播放记录存储 (UserDefaults JSON 持久化)
/// 数据源 = 本地记录;远程上报 (BilibiliService.reportWatchProgress) 为预留 API,
/// 待接入真实 aid 解析后可作为补充数据源。
@MainActor
final class LocalWatchHistoryStore {
    static let shared = LocalWatchHistoryStore()

    private let storageKey = "local_watch_history"
    private var cache: [LocalWatchHistoryEntry]?

    private init() {}

    /// 全部进行中的记录 (progress < duration,即未看完),按观看时间倒序
    func fetchResumeItems() -> [LocalWatchHistoryEntry] {
        allEntries()
            .filter { $0.duration > 0 && $0.progress < $0.duration }
            .sorted { $0.viewAt > $1.viewAt }
    }

    /// 记录/更新播放进度 (按 season_id 去重,保留最新观看的一集)
    func record(
        seasonId: Int?,
        epId: Int?,
        cid: Int?,
        title: String,
        episodeTitle: String?,
        coverURLString: String?,
        progress: Int,
        duration: Int
    ) {
        guard progress > 0 else { return }
        var entries = allEntries()

        if duration > 0, progress >= duration {
            // ▶️ 已看完:移除记录,不再出现在"继续观看"
            entries.removeAll { $0.id == (seasonId.map { "ss-\($0)" } ?? "ep-\(epId ?? 0)") }
        } else {
            let newEntry = LocalWatchHistoryEntry(
                seasonId: seasonId,
                epId: epId,
                cid: cid,
                title: title,
                episodeTitle: episodeTitle,
                coverURLString: coverURLString,
                progress: progress,
                duration: duration,
                viewAt: Int(Date().timeIntervalSince1970)
            )
            if let index = entries.firstIndex(where: { $0.seasonId != nil && $0.seasonId == newEntry.seasonId }) {
                entries[index] = newEntry
            } else {
                entries.append(newEntry)
            }
        }

        cache = entries
        persist(entries)
    }

    /// 清除某条记录 (退出登录等场景)
    func remove(seasonId: Int?) {
        guard let seasonId else { return }
        var entries = allEntries()
        entries.removeAll { $0.seasonId == seasonId }
        cache = entries
        persist(entries)
    }

    /// 清空全部记录
    func clearAll() {
        cache = []
        persist([])
    }

    // MARK: - 私有

    private func allEntries() -> [LocalWatchHistoryEntry] {
        if let cache { return cache }
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let entries = try? JSONDecoder().decode([LocalWatchHistoryEntry].self, from: data) else {
            return []
        }
        cache = entries
        return entries
    }

    private func persist(_ entries: [LocalWatchHistoryEntry]) {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}
