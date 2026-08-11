import AVFoundation
import AVKit
import Foundation

/// 🏷️ 设置 AVPlayerItem 的 externalMetadata (标题/副标题),并异步加载封面 artwork
/// 方案 A (DASH/HLS) 与方案 B (MP4/durl 降级) 共用,保证所有播放路径的 Info 面板都有内容
/// (3a 从 BiliPlayerContainerView 迁出:随 loadVideo 加载流程迁入 PlayerViewModel 的附属逻辑)
@MainActor
func applyMetadata(to item: AVPlayerItem, title: String?, subtitle: String?, coverURL: URL?) {
    print("🔍 [Player] applyMetadata: title=\(title ?? "nil"), subtitle=\(subtitle ?? "nil"), coverURL=\(coverURL?.absoluteString ?? "nil")")
    var metadata: [AVMetadataItem] = []

    // ⚠️ tvOS Info 面板显示三要素 (踩坑记录):
    // 1. 每项必须设置 locale,否则 Info 面板完全不渲染
    // 2. description 为 nil/空字符串时,海报会被隐藏 (tvOS 已知 bug),需用 " " 占位
    // 3. artwork 必须设置 dataType (PNG/JPEG),否则海报不显示
    if let title {
        let titleItem = AVMutableMetadataItem()
        titleItem.identifier = .commonIdentifierTitle
        titleItem.value = title as NSString
        titleItem.extendedLanguageTag = "und"
        titleItem.locale = Locale.current
        metadata.append(titleItem)
    }

    // description 恒有值:subtitle 为空时用单个空格占位,避免海报被隐藏
    let subtitleText = (subtitle ?? "").isEmpty ? " " : subtitle ?? ""
    let subtitleItem = AVMutableMetadataItem()
    subtitleItem.identifier = .commonIdentifierDescription
    subtitleItem.value = subtitleText as NSString
    subtitleItem.extendedLanguageTag = "und"
    subtitleItem.locale = Locale.current
    metadata.append(subtitleItem)

    item.externalMetadata = metadata
    print("🔍 [Player] externalMetadata set with \(metadata.count) items")

    // 异步加载封面 artwork (Info 面板的海报)
    guard let coverURL else { return }
    Task {
        do {
            let (imageData, _) = try await withTimeout(seconds: 3.0) {
                try await URLSession.shared.data(from: coverURL)
            }
            let artworkItem = AVMutableMetadataItem()
            artworkItem.identifier = .commonIdentifierArtwork
            artworkItem.value = imageData as NSData
            artworkItem.extendedLanguageTag = "und"
            artworkItem.locale = Locale.current
            // 根据图片魔数设置 dataType,否则 tvOS 不渲染海报
            let isPNG = imageData.count > 8 && imageData.prefix(8) == Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
            artworkItem.dataType = isPNG ? (kCMMetadataBaseDataType_PNG as String) : (kCMMetadataBaseDataType_JPEG as String)

            var updatedMetadata = metadata
            updatedMetadata.append(artworkItem)
            item.externalMetadata = updatedMetadata
        } catch {
            print("⚠️ [Player] Failed to fetch artwork: \(error)")
        }
    }
}

// Helper function to add timeout to async operations
@MainActor
func withTimeout<T: Sendable>(seconds: TimeInterval, operation: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw NSError(domain: "TimeoutError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Operation timed out"])
        }
        let result =
            try await group.next() ?? { throw NSError(domain: "TimeoutError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Operation timed out"]) }()
        group.cancelAll()
        return result
    }
}
