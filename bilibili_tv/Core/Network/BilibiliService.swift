import Foundation

/// Bilibili 统一核心 API 服务引擎 (统一控制管道、自动 Headers/Cookie 注入与集中错误处理)
class BilibiliService {
    static let shared = BilibiliService()
    
    let session: URLSession
    let config = BilibiliNetworkConfig.shared
    
    init(session: URLSession? = nil) {
        if let customSession = session {
            self.session = customSession
        } else {
            // 💡 配置高可用弹性 URLSessionConfiguration (自动清退失效 HTTP/2 死连接，防止 Code=303 错误)
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = 15.0
            configuration.timeoutIntervalForResource = 30.0
            configuration.waitsForConnectivity = true
            configuration.httpMaximumConnectionsPerHost = 8
            
            // 🌟 开启 Pulse 自动抓包与全量 HTTP 流量监控
            PulseHelper.shared.configureURLSessionConfiguration(configuration)
            
            self.session = URLSession(configuration: configuration)
        }
    }
    
    /// 统一发送 HTTP 请求的核心方法 (自动注入 Header/Cookie，自动解析数据与集中捕获错误)
    func execute<T: Decodable>(
        urlString: String,
        method: String = "GET",
        queryItems: [URLQueryItem]? = nil
    ) async throws -> T {
        guard var components = URLComponents(string: urlString) else {
            throw URLError(.badURL)
        }
        
        if let queryItems = queryItems, !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        
        guard let url = components.url else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        
        // 🌟 统一注入中央控制处的全局 Headers 与共享 Cookie
        for (key, value) in config.commonHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        print("🌐 [Network Engine] Outgoing \(method) -> \(url.absoluteString)")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            print("❌ [Network Engine] HTTP Error Status: \(httpResponse.statusCode)")
            throw URLError(.badServerResponse)
        }
        
        let decoder = JSONDecoder()
        let decodedObject = try decoder.decode(T.self, from: data)
        return decodedObject
    }
}
