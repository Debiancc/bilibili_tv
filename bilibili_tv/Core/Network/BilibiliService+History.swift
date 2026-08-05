import Foundation

/// 观看进度上报接口的最小响应 (POST x/click-interface/web/heartbeat)
struct HistoryReportResponse: Codable {
    let code: Int
    let message: String?
}

extension BilibiliService {
    /// 拉取用户观看历史,过滤 PGC 并按剧集去重(保留最近看过的一集),按观看时间倒序
    /// 仅保留"真正在追"的条目:进度 > 0 且未看完
    /// 未登录 / 接口异常时返回空数组,调用方无需感知登录态
    func fetchWatchHistory(ps: Int = 20) async -> [WatchHistoryEntry] {
        let urlString = "https://api.bilibili.com/x/v2/history"
        do {
            let response: WatchHistoryResponse = try await execute(
                urlString: urlString,
                queryItems: [URLQueryItem(name: "ps", value: "\(ps)")]
            )
            guard response.code == 0, let entries = response.data else {
                print("⚠️ [History] fetch failed, code=\(response.code), msg=\(response.message ?? "nil")")
                return []
            }

            let inProgress = entries.filter {
                $0.isPGC && $0.progress > 0 && $0.duration > 0 && $0.progress < $0.duration
            }
            let deduped = Dictionary(grouping: inProgress, by: { $0.bangumi?.season?.seasonId ?? -1 })
                .values
                .map { group in group.max { $0.viewAt < $1.viewAt }! }
            return deduped.sorted { $0.viewAt > $1.viewAt }
        } catch {
            print("⚠️ [History] fetch error: \(error)")
            return []
        }
    }

    /// 上报观看进度 (PGC 心跳上报)
    /// platform 三件套 (mobi_app/device/platform=web) 是历史记录被识别为 PGC 的关键
    /// fire-and-forget:失败仅记日志,不影响播放
    func reportWatchProgress(epId: Int?, seasonId: Int?, cid: Int, playedTime: Int) async {
        var form: [String: String] = [
            "aid": "0",
            "cid": "\(cid)",
            "played_time": "\(playedTime)",
            "type": "4",
            "sub_type": "1",
            "mobi_app": "web",
            "device": "web",
            "platform": "web",
        ]
        if let epId {
            form["epid"] = "\(epId)"
        }
        if let seasonId {
            form["sid"] = "\(seasonId)"
        }

        do {
            let response: HistoryReportResponse = try await postForm(
                urlString: "https://api.bilibili.com/x/click-interface/web/heartbeat",
                form: form
            )
            print("📡 [History] reported progress: ep=\(epId ?? -1) ss=\(seasonId ?? -1) cid=\(cid) t=\(playedTime)s -> code=\(response.code) \(response.message ?? "")")
        } catch {
            print("⚠️ [History] report failed: \(error)")
        }
    }

    /// POST 表单上报辅助 (application/x-www-form-urlencoded),复用统一 Header/Cookie 注入
    private func postForm<T: Decodable>(urlString: String, form: [String: String]) async throws -> T {
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        for (key, value) in config.commonHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = form.map { "\($0.key)=\($0.value)" }.joined(separator: "&").data(using: .utf8)

        print("🌐 [Network Engine] Outgoing POST -> \(url.absoluteString)")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            print("❌ [Network Engine] HTTP Error Status: \(httpResponse.statusCode)")
            throw URLError(.badServerResponse)
        }

        return try JSONDecoder().decode(T.self, from: data)
    }
}
