import Foundation

class BilibiliService {
    static let shared = BilibiliService()
    
    private let session: URLSession
    
    init() {
        let config = URLSessionConfiguration.default
        self.session = URLSession(configuration: config)
    }
    
    func fetchMovieFeed(cursor: Int = 0) async throws -> FeedData {
        let urlString = "https://api.bilibili.com/pgc/page/web/feed?name=movie&coursor=\(cursor)&new_cursor_status=true"
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        // Headers from the user's curl
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "accept")
        request.setValue("en,zh-CN;q=0.9,zh;q=0.8,ko;q=0.7,zh-TW;q=0.6,ja;q=0.5,de;q=0.4", forHTTPHeaderField: "accept-language")
        request.setValue("https://www.bilibili.com", forHTTPHeaderField: "origin")
        request.setValue("https://www.bilibili.com/movie/?spm_id_from=333.1007.0.0", forHTTPHeaderField: "referer")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/146.0.0.0 Safari/537.36", forHTTPHeaderField: "user-agent")
        
        // Cookie from the user's curl
        let cookie = "buvid3=54A2ED24-678A-E5A2-DA75-D296A223F20244795infoc; b_nut=1759035444; buvid_fp=66f2836d5d23746cd021921a65519570; LIVE_BUVID=AUTO7417590354461792; PVID=1; _uuid=3F14D772-42A10-788E-8116-CEF5847AA62B46397infoc; enable_web_push=DISABLE; DedeUserID=286552227; DedeUserID__ckMd5=d804c8e4ec5563bb; theme-tip-show=SHOWED; rpdid=|(k|~ulYJRRu0J\\'u~lmulu|ll; CURRENT_QUALITY=120; theme-avatar-tip-show=SHOWED; lang=zh-Hans; bili_ticket=eyJhbGciOiJIUzI1NiIsImtpZCI6InMwMyIsInR5cCI6IkpXVCJ9.eyJleHAiOjE3NzY3NDY5NDEsImlhdCI6MTc3NjQ4NzY4MSwicGx0IjotMX0.5dkxCRIpHSMZW4QvGZAsSB2itSCxxwro7Ir5wC6xgcM; bili_ticket_expires=1776746881; buvid4=41467C47-3B97-5CA6-79AF-9DCCDF0D35EG28303-026041812-olGSNhMwfL2LfMkJ2RApwg%3D%3D; SESSDATA=ef3279cd%2C1792039928%2Cb5a73%2A41CjCXtjxWJGyzLOa3XD6qPU7RbtDWNE7iHVfCbFMvY88UxaQw7oZJB5UIeeS9tqNPXZ8SVm1aaVZLNzJDb0ZLV1FhaUZPZXc3YUJ4QndSVjFBUXNpbkxrOUpmTnU2cmFKS3Zha0FhS19zQnQyRVpRSWtFVjRVbkZSdURuQ203eUJ1bXJOZ0hCZnVBIIEC; bili_jct=ffc376aa8bb1adce35ec9031e16eaea7; home_feed_column=4; browser_resolution=1097-1168; bp_t_offset_286552227=1192495676869574656; CURRENT_FNVAL=16; sid=5x5afrj6; b_lsid=D1250FD3_19D9F27CFBB"
        request.setValue(cookie, forHTTPHeaderField: "cookie")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        
        let decoder = JSONDecoder()
        let feedResponse = try decoder.decode(FeedResponse.self, from: data)
        
        if feedResponse.code != 0 {
            throw NSError(domain: "BilibiliError", code: feedResponse.code, userInfo: [NSLocalizedDescriptionKey: feedResponse.message])
        }
        
        guard let feedData = feedResponse.data else {
            throw NSError(domain: "BilibiliError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Empty data"])
        }
        
        return feedData
    }
}
