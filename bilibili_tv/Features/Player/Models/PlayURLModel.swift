import Foundation

struct PlayURLResponse: Decodable {
    let code: Int
    let message: String
    let result: PlayURLResult?
    let data: PlayURLResult?

    var activeResult: PlayURLResult? {
        result ?? data
    }
}

struct PlayURLResult: Decodable {
    let quality: Int?
    let format: String?
    let timelength: Int?
    let acceptFormat: String?
    let acceptDescription: [String]
    let acceptQuality: [Int]

    // 💡 识别 DRM 与普通流的核心标志位字段
    let isDrm: Bool
    let drmTechType: Int?

    // 🎬 付费/试看状态字段:is_preview=1 表示仅返回试看片段,error_code=-10403 表示未购买
    // vip_status=1 表示已开通大会员 (部分付费电影需单片购买,大会员不覆盖)
    let isPreview: Int?
    let hasPaid: Bool
    let errorCode: Int?
    let vipStatus: Int?
    let vipType: Int?

    let dash: DashInfo?
    let durl: [MP4URLItem]

    // 💬 弹幕所需 cid (弹幕接口 seg.so 以 cid 作为 oid)
    var cid: Int?

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
        case cid
    }

    /// 集合/标志位字段缺省为空:字段缺失时等价位 nil/空数组,不破坏解码契约
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        quality = try container.decodeIfPresent(Int.self, forKey: .quality)
        format = try container.decodeIfPresent(String.self, forKey: .format)
        timelength = try container.decodeIfPresent(Int.self, forKey: .timelength)
        acceptFormat = try container.decodeIfPresent(String.self, forKey: .acceptFormat)
        acceptDescription = try container.decodeIfPresent([String].self, forKey: .acceptDescription) ?? []
        acceptQuality = try container.decodeIfPresent([Int].self, forKey: .acceptQuality) ?? []
        isDrm = try container.decodeIfPresent(Bool.self, forKey: .isDrm) ?? false
        drmTechType = try container.decodeIfPresent(Int.self, forKey: .drmTechType)
        isPreview = try container.decodeIfPresent(Int.self, forKey: .isPreview)
        hasPaid = try container.decodeIfPresent(Bool.self, forKey: .hasPaid) ?? false
        errorCode = try container.decodeIfPresent(Int.self, forKey: .errorCode)
        vipStatus = try container.decodeIfPresent(Int.self, forKey: .vipStatus)
        vipType = try container.decodeIfPresent(Int.self, forKey: .vipType)
        dash = try container.decodeIfPresent(DashInfo.self, forKey: .dash)
        durl = try container.decodeIfPresent([MP4URLItem].self, forKey: .durl) ?? []
        cid = try container.decodeIfPresent(Int.self, forKey: .cid)
    }
}

extension PlayURLResult {
    /// 显式成员初始化器:自定义 init(from:) 会吞掉合成的 memberwise init,
    /// 按成员顺序保留默认值,供 mock/测试直接构造
    init(
        quality: Int? = nil,
        format: String? = nil,
        timelength: Int? = nil,
        acceptFormat: String? = nil,
        acceptDescription: [String] = [],
        acceptQuality: [Int] = [],
        isDrm: Bool = false,
        drmTechType: Int? = nil,
        isPreview: Int? = nil,
        hasPaid: Bool = false,
        errorCode: Int? = nil,
        vipStatus: Int? = nil,
        vipType: Int? = nil,
        dash: DashInfo? = nil,
        durl: [MP4URLItem] = [],
        cid: Int? = nil
    ) {
        self.quality = quality
        self.format = format
        self.timelength = timelength
        self.acceptFormat = acceptFormat
        self.acceptDescription = acceptDescription
        self.acceptQuality = acceptQuality
        self.isDrm = isDrm
        self.drmTechType = drmTechType
        self.isPreview = isPreview
        self.hasPaid = hasPaid
        self.errorCode = errorCode
        self.vipStatus = vipStatus
        self.vipType = vipType
        self.dash = dash
        self.durl = durl
        self.cid = cid
    }
}

extension PlayURLResult {
    /// 🎬 判断当前流是否为「试看/预览」:未购买时,B站只下发试看片段
    /// 依据:is_preview=1 / error_code=-10403(无权限观看)
    /// ⚠️ 不能把 has_paid=false 当作试看信号:免费内容的响应里 has_paid 也是 false,
    /// 只有 is_preview 和 error_code 能区分「试看」与「可正常播放」。
    var isPreviewOnly: Bool {
        if isPreview == 1 { return true }
        if errorCode == -10_403 { return true }
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
        if isDrm { return false }
        if let drmTech = drmTechType, drmTech != 0 { return false }
        return true
    }

    /// 根据请求的最高画质 (maxQn) 自动选择最佳 Dash 视频轨道
    /// Bilibili DASH 响应包含所有清晰度的轨道，必须按 qualityId 过滤
    /// 编码策略：抹掉 AV1 —— 当前市面全系 Apple TV 均无 AV1 硬件解码，
    /// 4K 软件解码吃力且 HDR 兼容性差；同清晰度优先 HEVC 再 H.264（见 VideoCodec.playbackPriority）
    func bestVideoTrack(maxQn: Int = 120) -> DashVideoItem? {
        guard let videos = dash?.video, !videos.isEmpty else { return nil }
        // 过滤掉超过请求清晰度的轨道（例如 qn=80 时排除 qualityId=120/4K）
        let eligible = videos.filter { ($0.qualityId ?? 0) <= maxQn }
        let qualityCandidates = eligible.isEmpty ? videos : eligible  // fallback 到全部
        // 仅保留有播放偏好的编码（HEVC/H.264），AV1 与未知编码直接出局
        let codecCandidates = qualityCandidates.filter {
            VideoCodec(rawValue: $0.codecId ?? 0)?.playbackPriority != nil
        }
        // codec 过滤后为空（如极端情况下仅剩 AV1 轨）时回退全部，保证不因偏好逻辑丢流
        let candidates = codecCandidates.isEmpty ? qualityCandidates : codecCandidates
        // 复合排序(清晰度优先 + 编码优先 + 码率次之),无法用 min/max 简化
        // swiftlint:disable:next sorted_first_last
        return candidates.sorted { v1, v2 in
            let q1 = v1.qualityId ?? 0
            let q2 = v2.qualityId ?? 0
            if q1 != q2 { return q1 > q2 }
            let c1 = VideoCodec(rawValue: v1.codecId ?? 0)?.playbackPriority ?? Int.max
            let c2 = VideoCodec(rawValue: v2.codecId ?? 0)?.playbackPriority ?? Int.max
            if c1 != c2 { return c1 < c2 }
            return (v1.bandwidth ?? 0) > (v2.bandwidth ?? 0)
        }.first
    }

    /// 自动选择最佳高品质音频轨道
    var bestAudioTrack: DashAudioItem? {
        guard let audios = dash?.audio, !audios.isEmpty else { return nil }
        return audios.max { ($0.bandwidth ?? 0) < ($1.bandwidth ?? 0) }
    }
}

/// B 站 DASH 视频轨道编码类型（DTO 字段 codecid 的语义映射）
/// 服务端取值空间是开放集合（AV1 即后新增），未知取值经 rawValue 返回 nil，
/// 解码契约不受影响；播放偏好由 playbackPriority 承载（低值优先）。
enum VideoCodec: Int {
    case h264 = 7
    case hevc = 12
    case av1 = 13

    /// 播放偏好序：HEVC 首选、H.264 次选；AV1 与未知编码为 nil（不参与偏好选择）
    var playbackPriority: Int? {
        switch self {
        case .hevc: return 0
        case .h264: return 1
        case .av1: return nil
        }
    }
}

struct DashInfo: Decodable {
    let duration: Int?
    let minBufferTime: Double?
    let video: [DashVideoItem]
    let audio: [DashAudioItem]

    enum CodingKeys: String, CodingKey {
        case duration
        case minBufferTime = "min_buffer_time"
        case video
        case audio
    }

    /// 音视频轨道缺省为空数组:字段缺失时等价位 nil,不破坏解码契约
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        duration = try container.decodeIfPresent(Int.self, forKey: .duration)
        minBufferTime = try container.decodeIfPresent(Double.self, forKey: .minBufferTime)
        video = try container.decodeIfPresent([DashVideoItem].self, forKey: .video) ?? []
        audio = try container.decodeIfPresent([DashAudioItem].self, forKey: .audio) ?? []
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
        initialization =
            try container.decodeIfPresent(String.self, forKey: .initialization)
            ?? container.decodeIfPresent(String.self, forKey: .initializationAlt)
        indexRange =
            try container.decodeIfPresent(String.self, forKey: .indexRange)
            ?? container.decodeIfPresent(String.self, forKey: .indexRangeAlt)
    }
}

struct DashVideoItem: Decodable, Identifiable {
    var id: String { "\(qualityId ?? 0)-\(codecs ?? "")-\(bandwidth ?? 0)" }
    let qualityId: Int?
    let baseUrl: String?
    let backupUrl: [String]
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
        backupUrl = try container.decodeIfPresent([String].self, forKey: .backupUrl) ?? []
        bandwidth = try container.decodeIfPresent(Int.self, forKey: .bandwidth)
        mimeType = try container.decodeIfPresent(String.self, forKey: .mimeType)
        codecs = try container.decodeIfPresent(String.self, forKey: .codecs)
        width = try container.decodeIfPresent(Int.self, forKey: .width)
        height = try container.decodeIfPresent(Int.self, forKey: .height)
        frameRate = try container.decodeIfPresent(String.self, forKey: .frameRate)
        codecId = try container.decodeIfPresent(Int.self, forKey: .codecId)
        drmType = try container.decodeIfPresent(Int.self, forKey: .drmType)
        segmentBase =
            (try? container.decodeIfPresent(SegmentBaseInfo.self, forKey: .segmentBase))
            ?? (try? container.decodeIfPresent(SegmentBaseInfo.self, forKey: .segmentBaseAlt))
    }
}

struct DashAudioItem: Decodable, Identifiable {
    var id: String { "\(audioId ?? 0)-\(codecs ?? "")-\(bandwidth ?? 0)" }
    let audioId: Int?
    let baseUrl: String?
    let backupUrl: [String]
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
        backupUrl = try container.decodeIfPresent([String].self, forKey: .backupUrl) ?? []
        bandwidth = try container.decodeIfPresent(Int.self, forKey: .bandwidth)
        mimeType = try container.decodeIfPresent(String.self, forKey: .mimeType)
        codecs = try container.decodeIfPresent(String.self, forKey: .codecs)
        codecId = try container.decodeIfPresent(Int.self, forKey: .codecId)
        drmType = try container.decodeIfPresent(Int.self, forKey: .drmType)
        segmentBase =
            (try? container.decodeIfPresent(SegmentBaseInfo.self, forKey: .segmentBase))
            ?? (try? container.decodeIfPresent(SegmentBaseInfo.self, forKey: .segmentBaseAlt))
    }
}

struct MP4URLItem: Decodable, Identifiable {
    var id: String { url ?? UUID().uuidString }
    let order: Int?
    let length: Int?
    let size: Int?
    let url: String?
    let backupUrl: [String]

    enum CodingKeys: String, CodingKey {
        case order
        case length
        case size
        case url
        case backupUrl = "backup_url"
    }

    /// 备用地址缺省为空数组:字段缺失时等价位 nil,不破坏解码契约
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        order = try container.decodeIfPresent(Int.self, forKey: .order)
        length = try container.decodeIfPresent(Int.self, forKey: .length)
        size = try container.decodeIfPresent(Int.self, forKey: .size)
        url = try container.decodeIfPresent(String.self, forKey: .url)
        backupUrl = try container.decodeIfPresent([String].self, forKey: .backupUrl) ?? []
    }
}

extension MP4URLItem {
    /// 显式成员初始化器:自定义 init(from:) 会吞掉合成的 memberwise init,供 mock/测试直接构造
    init(order: Int? = nil, length: Int? = nil, size: Int? = nil, url: String? = nil, backupUrl: [String] = []) {
        self.order = order
        self.length = length
        self.size = size
        self.url = url
        self.backupUrl = backupUrl
    }
}

struct SeasonDetailResponse: Decodable {
    let code: Int
    let message: String?
    let result: SeasonDetailResult?
}

struct EpDetailResponse: Decodable {
    let code: Int
    let result: EpDetailResult?
}

struct EpDetailResult: Decodable {
    let cid: Int?
}

struct SeasonDetailResult: Decodable {
    let episodes: [SeasonEpisode]

    /// 剧集缺省为空数组:字段缺失时等价位 nil,不破坏解码契约
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        episodes = try container.decodeIfPresent([SeasonEpisode].self, forKey: .episodes) ?? []
    }

    enum CodingKeys: String, CodingKey {
        case episodes
    }
}

struct SeasonEpisode: Decodable {
    let id: Int?
    let ep_id: Int?
    let cid: Int?
}
