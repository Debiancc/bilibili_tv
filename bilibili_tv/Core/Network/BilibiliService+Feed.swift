import Foundation

extension BilibiliService {
    /// 电影频道 Feed 瀑布流列表请求
    func fetchMovieFeed(cursor: Int = 0) async throws -> FeedData {
        let urlString = "https://api.bilibili.com/pgc/page/web/feed"
        let queryItems = [
            URLQueryItem(name: "name", value: "movie"),
            URLQueryItem(name: "coursor", value: "\(cursor)"),
            URLQueryItem(name: "new_cursor_status", value: "true")
        ]
        
        let feedResponse: FeedResponse = try await execute(
            urlString: urlString,
            method: "GET",
            queryItems: queryItems
        )
        
        if feedResponse.code != 0 {
            throw NSError(domain: "BilibiliFeedError", code: feedResponse.code, userInfo: [NSLocalizedDescriptionKey: feedResponse.message])
        }
        
        guard let feedData = feedResponse.data else {
            throw NSError(domain: "BilibiliFeedError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Empty feed data"])
        }
        
        return feedData
    }
    /// 爬取 B 站电影频道页面的 __INITIAL_STATE__ 数据
    func fetchMovieWebInitialState() async throws -> WebInitialState {
        let urlString = "https://www.bilibili.com/movie/"
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode),
              let htmlString = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "BilibiliWebError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to fetch webpage"])
        }
        
        // 使用正则表达式提取 __INITIAL_STATE__
        guard let regex = try? NSRegularExpression(pattern: "window\\.__INITIAL_STATE__=(.*?);\\(function"),
              let match = regex.firstMatch(in: htmlString, range: NSRange(htmlString.startIndex..., in: htmlString)),
              let range = Range(match.range(at: 1), in: htmlString) else {
            throw NSError(domain: "BilibiliWebError", code: -2, userInfo: [NSLocalizedDescriptionKey: "Regex failed to find __INITIAL_STATE__"])
        }
        
        let jsonString = String(htmlString[range])
        guard let jsonData = jsonString.data(using: .utf8) else {
            throw NSError(domain: "BilibiliWebError", code: -3, userInfo: [NSLocalizedDescriptionKey: "Failed to convert JSON string to data"])
        }
        
        let decoder = JSONDecoder()
        do {
            let initialState = try decoder.decode(WebInitialState.self, from: jsonData)
            return initialState
        } catch {
            print("❌ JSON Decode Error: \(error)")
            throw error
        }
    }
}
