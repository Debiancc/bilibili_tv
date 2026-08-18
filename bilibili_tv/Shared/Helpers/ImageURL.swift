import Foundation

/// URL 规范化共享工具（阶段五）：统一处理协议相对地址、http 直链与 CDN 切片参数。
/// 原先该逻辑在 FeedModel / LocalWatchHistoryStore / HistoryModel / DetailViewModel /
/// DetailView / EpisodeCardView 等处重复实现，统一收敛到此处。
enum ImageURL {
    /// 安全的 https 地址：`//` 协议相对地址补 `https:`，`http://` 直链升级为 `https://`
    /// （scheme 大小写不敏感，`HTTP://` 同样处理）。空串 / nil 返回 nil，其余原样返回。
    static func secure(_ raw: String?) -> String? {
        guard var s = raw, !s.isEmpty else { return nil }
        if s.hasPrefix("//") {
            s = "https:" + s
        } else if s.lowercased().hasPrefix("http://") {
            s = "https://" + s.dropFirst(7)
        }
        return s
    }

    /// 追加 Bilibili CDN 切片参数：仅当 base（`?`/`#` 之前的路径部分）尚未携带 `@` 切片时
    /// 追加，并插在 query/fragment 之前，避免切片参数落到 query 之后。
    static func cdn(_ raw: String, suffix: String) -> String {
        let boundary = raw.firstIndex(where: { $0 == "?" || $0 == "#" }) ?? raw.endIndex
        let base = String(raw[..<boundary])
        let trailing = String(raw[boundary...])
        return base.contains("@") ? raw : base + suffix + trailing
    }

    /// `.webp` → `.jpg`（播放器封面不支持 webp 解码的场景使用），其余后缀原样返回。
    static func webpToJpg(_ raw: String) -> String {
        raw.hasSuffix(".webp") ? raw.replacingOccurrences(of: ".webp", with: ".jpg") : raw
    }
}
