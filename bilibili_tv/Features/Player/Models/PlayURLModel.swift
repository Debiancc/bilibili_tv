import Foundation

struct PlayURLResponse: Codable {
    let code: Int
    let message: String
    let result: PlayURLResult?
    let data: PlayURLResult?
    
    var activeResult: PlayURLResult? {
        return result ?? data
    }
}

struct PlayURLResult: Codable {
    let quality: Int?
    let format: String?
    let timelength: Int?
    let acceptFormat: String?
    let acceptDescription: [String]?
    let acceptQuality: [Int]?
    
    // 💡 识别 DRM 与普通流的核心标志位字段
    let isDrm: Bool?
    let drmTechType: Int?
    
    let dash: DashInfo?
    let durl: [MP4URLItem]?
    
    enum CodingKeys: String, CodingKey {
        case quality
        case format
        case timelength
        case acceptFormat = "accept_format"
        case acceptDescription = "accept_description"
        case acceptQuality = "accept_quality"
        case isDrm = "is_drm"
        case drmTechType = "drm_tech_type"
        case dash
        case durl
    }
}

extension PlayURLResult {
    /// 💡 判定当前流是否为非 DRM 普通播放流 (is_drm != true 且 drm_tech_type == 0)
    var isStandardPlayURL: Bool {
        if isDrm == true { return false }
        if let drmTech = drmTechType, drmTech != 0 { return false }
        return true
    }
    
    /// 🌟 特性 6：使用 KeyPathComparator 声明式选择最高画质/高码率的 Dash 视频流 (4K / 1080P 60帧)
    var bestVideoTrack: DashVideoItem? {
        guard let videos = dash?.video, !videos.isEmpty else { return nil }
        return videos.sorted(using: [
            KeyPathComparator(\.qualityId, order: .reverse),
            KeyPathComparator(\.bandwidth, order: .reverse)
        ]).first
    }
    
    /// 自动选择最佳高品质音频轨道
    var bestAudioTrack: DashAudioItem? {
        guard let audios = dash?.audio, !audios.isEmpty else { return nil }
        return audios.sorted(using: KeyPathComparator(\.bandwidth, order: .reverse)).first
    }
}

struct DashInfo: Codable {
    let duration: Int?
    let minBufferTime: Double?
    let video: [DashVideoItem]?
    let audio: [DashAudioItem]?
    
    enum CodingKeys: String, CodingKey {
        case duration
        case minBufferTime = "min_buffer_time"
        case video
        case audio
    }
}

struct DashVideoItem: Codable, Identifiable {
    var id: String { "\(qualityId ?? 0)-\(codecs ?? "")-\(bandwidth ?? 0)" }
    let qualityId: Int?
    let baseUrl: String?
    let backupUrl: [String]?
    let bandwidth: Int?
    let mimeType: String?
    let codecs: String?
    let width: Int?
    let height: Int?
    let frameRate: String?
    let codecId: Int?
    let drmType: Int?
    
    enum CodingKeys: String, CodingKey {
        case qualityId = "id"
        case baseUrl = "baseUrl"
        case backupUrl = "backupUrl"
        case bandwidth
        case mimeType = "mimeType"
        case codecs
        case width
        case height
        case frameRate
        case codecId = "codecid"
        case drmType = "drm_type"
    }
}

struct DashAudioItem: Codable, Identifiable {
    var id: String { "\(audioId ?? 0)-\(codecs ?? "")-\(bandwidth ?? 0)" }
    let audioId: Int?
    let baseUrl: String?
    let backupUrl: [String]?
    let bandwidth: Int?
    let mimeType: String?
    let codecs: String?
    let codecId: Int?
    let drmType: Int?
    
    enum CodingKeys: String, CodingKey {
        case audioId = "id"
        case baseUrl = "baseUrl"
        case backupUrl = "backupUrl"
        case bandwidth
        case mimeType = "mimeType"
        case codecs
        case codecId = "codecid"
        case drmType = "drm_type"
    }
}

struct MP4URLItem: Codable, Identifiable {
    var id: String { url ?? UUID().uuidString }
    let order: Int?
    let length: Int?
    let size: Int?
    let url: String?
    let backupUrl: [String]?
    
    enum CodingKeys: String, CodingKey {
        case order
        case length
        case size
        case url
        case backupUrl = "backup_url"
    }
}
