import Foundation

struct PlayURLResponse: Decodable {
    let code: Int
    let message: String
    let result: PlayURLResult?
    let data: PlayURLResult?
    
    var activeResult: PlayURLResult? {
        return result ?? data
    }
}

struct PlayURLResult: Decodable {
    let quality: Int?
    let format: String?
    let timelength: Int?
    let acceptFormat: String?
    let acceptDescription: [String]?
    let acceptQuality: [Int]?
    
    // 💡 识别 DRM 与普通流的核心标志位字段
    let isDrm: Bool?
    let drmTechType: Int?

    // 🎬 付费/试看状态字段:is_preview=1 表示仅返回试看片段,error_code=-10403 表示未购买
    // vip_status=1 表示已开通大会员 (部分付费电影需单片购买,大会员不覆盖)
    let isPreview: Int?
    let hasPaid: Bool?
    let errorCode: Int?
    let vipStatus: Int?
    let vipType: Int?

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
        case isPreview = "is_preview"
        case hasPaid = "has_paid"
        case errorCode = "error_code"
        case vipStatus = "vip_status"
        case vipType = "vip_type"
        case dash
        case durl
    }
}

extension PlayURLResult {
    /// 🎬 判断当前流是否为「试看/预览」:未购买时,B站只下发试看片段
    /// 依据:is_preview=1 / error_code=-10403(无权限观看)
    /// ⚠️ 不能把 has_paid=false 当作试看信号:免费内容的响应里 has_paid 也是 false,
    /// 只有 is_preview 和 error_code 能区分「试看」与「可正常播放」。
    var isPreviewOnly: Bool {
        if isPreview == 1 { return true }
        if errorCode == -10403 { return true }
        return false
    }

    /// 🎬 试看提示的「观看全片」部分文案:
    /// - 已是大会员 (vip_status=1) → 付费电影需单片购买,提示「购买本片」
    /// - 未开通大会员 → 提示「购买或开通大会员」
    var purchaseHintText: String? {
        guard isPreviewOnly else { return nil }
        if vipStatus == 1 {
            return "观看全片需购买本片"
        }
        return "观看全片需购买或开通大会员"
    }
}

extension PlayURLResult {
    /// 💡 判定当前流是否为非 DRM 普通播放流 (is_drm != true 且 drm_tech_type == 0)
    var isStandardPlayURL: Bool {
        if isDrm == true { return false }
        if let drmTech = drmTechType, drmTech != 0 { return false }
        return true
    }
    
    /// 根据请求的最高画质 (maxQn) 自动选择最佳 Dash 视频轨道
    /// Bilibili DASH 响应包含所有清晰度的轨道，必须按 qualityId 过滤
    func bestVideoTrack(maxQn: Int = 120) -> DashVideoItem? {
        guard let videos = dash?.video, !videos.isEmpty else { return nil }
        // 过滤掉超过请求清晰度的轨道（例如 qn=80 时排除 qualityId=120/4K）
        let eligible = videos.filter { ($0.qualityId ?? 0) <= maxQn }
        let candidates = eligible.isEmpty ? videos : eligible  // fallback 到全部
        return candidates.sorted { v1, v2 in
            let q1 = v1.qualityId ?? 0
            let q2 = v2.qualityId ?? 0
            if q1 != q2 { return q1 > q2 }
            return (v1.bandwidth ?? 0) > (v2.bandwidth ?? 0)
        }.first
    }
    
    /// 自动选择最佳高品质音频轨道
    var bestAudioTrack: DashAudioItem? {
        guard let audios = dash?.audio, !audios.isEmpty else { return nil }
        return audios.sorted { ($0.bandwidth ?? 0) > ($1.bandwidth ?? 0) }.first
    }
}

struct DashInfo: Decodable {
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

struct SegmentBaseInfo: Decodable {
    let initialization: String?
    let indexRange: String?
    
    enum CodingKeys: String, CodingKey {
        case initialization = "initialization"
        case indexRange = "index_range"
        case initializationAlt = "Initialization"
        case indexRangeAlt = "indexRange"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        initialization = try container.decodeIfPresent(String.self, forKey: .initialization)
            ?? container.decodeIfPresent(String.self, forKey: .initializationAlt)
        indexRange = try container.decodeIfPresent(String.self, forKey: .indexRange)
            ?? container.decodeIfPresent(String.self, forKey: .indexRangeAlt)
    }
}

struct DashVideoItem: Decodable, Identifiable {
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
    let segmentBase: SegmentBaseInfo?
    
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
        case segmentBase = "segment_base"
        case segmentBaseAlt = "SegmentBase"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        qualityId = try container.decodeIfPresent(Int.self, forKey: .qualityId)
        baseUrl = try container.decodeIfPresent(String.self, forKey: .baseUrl)
        backupUrl = try container.decodeIfPresent([String].self, forKey: .backupUrl)
        bandwidth = try container.decodeIfPresent(Int.self, forKey: .bandwidth)
        mimeType = try container.decodeIfPresent(String.self, forKey: .mimeType)
        codecs = try container.decodeIfPresent(String.self, forKey: .codecs)
        width = try container.decodeIfPresent(Int.self, forKey: .width)
        height = try container.decodeIfPresent(Int.self, forKey: .height)
        frameRate = try container.decodeIfPresent(String.self, forKey: .frameRate)
        codecId = try container.decodeIfPresent(Int.self, forKey: .codecId)
        drmType = try container.decodeIfPresent(Int.self, forKey: .drmType)
        segmentBase = (try? container.decodeIfPresent(SegmentBaseInfo.self, forKey: .segmentBase))
            ?? (try? container.decodeIfPresent(SegmentBaseInfo.self, forKey: .segmentBaseAlt))
    }
}

struct DashAudioItem: Decodable, Identifiable {
    var id: String { "\(audioId ?? 0)-\(codecs ?? "")-\(bandwidth ?? 0)" }
    let audioId: Int?
    let baseUrl: String?
    let backupUrl: [String]?
    let bandwidth: Int?
    let mimeType: String?
    let codecs: String?
    let codecId: Int?
    let drmType: Int?
    let segmentBase: SegmentBaseInfo?
    
    enum CodingKeys: String, CodingKey {
        case audioId = "id"
        case baseUrl = "baseUrl"
        case backupUrl = "backupUrl"
        case bandwidth
        case mimeType = "mimeType"
        case codecs
        case codecId = "codecid"
        case drmType = "drm_type"
        case segmentBase = "segment_base"
        case segmentBaseAlt = "SegmentBase"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        audioId = try container.decodeIfPresent(Int.self, forKey: .audioId)
        baseUrl = try container.decodeIfPresent(String.self, forKey: .baseUrl)
        backupUrl = try container.decodeIfPresent([String].self, forKey: .backupUrl)
        bandwidth = try container.decodeIfPresent(Int.self, forKey: .bandwidth)
        mimeType = try container.decodeIfPresent(String.self, forKey: .mimeType)
        codecs = try container.decodeIfPresent(String.self, forKey: .codecs)
        codecId = try container.decodeIfPresent(Int.self, forKey: .codecId)
        drmType = try container.decodeIfPresent(Int.self, forKey: .drmType)
        segmentBase = (try? container.decodeIfPresent(SegmentBaseInfo.self, forKey: .segmentBase))
            ?? (try? container.decodeIfPresent(SegmentBaseInfo.self, forKey: .segmentBaseAlt))
    }
}

struct MP4URLItem: Decodable, Identifiable {
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

struct SeasonDetailResponse: Decodable {
    let code: Int
    let message: String?
    let result: SeasonDetailResult?
}

struct SeasonDetailResult: Decodable {
    let episodes: [SeasonEpisode]?
}

struct SeasonEpisode: Decodable {
    let id: Int?
    let ep_id: Int?
    let cid: Int?
}
