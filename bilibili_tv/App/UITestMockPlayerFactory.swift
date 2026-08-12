import AVFoundation
import Foundation
import UIKit

/// UI 测试专用：生成本地可播放视频（焦点导航测试无需网络）。
/// `-uitestMockPlayer` 启动参数下由 bilibili_tvApp 调用，构造 .ready 态的 PlayerViewModel
/// 并用本地生成的 4 秒色块视频作为播放流，使 AVPlayerViewController 的 transport bar
/// 可正常显示与获得焦点（AVKit 无真实播放流时不渲染 transport bar）。
#if DEBUG
enum UITestMockPlayerFactory {
    @MainActor
    static func makeViewModel() -> PlayerViewModel {
        let url = generateVideoIfNeeded()
        let vm = PlayerViewModel(epId: 320_665, seasonId: 33_354, title: "夏洛特烦恼", subtitle: "马冬梅的排列组合")
        vm.currentCid = 123_456
        vm.player = AVPlayer(url: url)
        vm.state = .ready
        return vm
    }

    /// 生成 4 秒 640x360 色块视频（H.264），首次生成后缓存到 tmp 目录。
    /// 生产者与写入均有超时上限——测试装置绝不能让 app 启动无限期阻塞；
    /// 缓存文件用 isReadable + duration 校验，损坏则删除重建。
    @MainActor
    private static func generateVideoIfNeeded() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("uitest_mock_player.mp4")
        if let cached = usableCachedVideo(at: url) {
            return cached
        }
        let bundle = makeVideoWriter(outputURL: url)
        bundle.writer.startWriting()
        bundle.writer.startSession(atSourceTime: .zero)
        guard produceFrames(into: bundle.adaptor, input: bundle.input) else {
            try? FileManager.default.removeItem(at: url)
            fatalError("[UITest] 视频生成超时或失败：\(url.path)")
        }
        finishWriting(bundle.writer, outputURL: url)
        return url
    }

    /// 校验并返回可用的缓存视频；缓存损坏则删除，返回 nil 触发重新生成。
    /// AVAsset 的同步可读性/时长属性在 tvOS 16+ 已废弃，故用有界等待的
    /// 异步 load 校验（最多 2 秒，避免缓存校验本身阻塞启动）。
    private static func usableCachedVideo(at url: URL) -> URL? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let asset = AVURLAsset(url: url)
        let semaphore = DispatchSemaphore(value: 0)
        let result = MutableBox<(isReadable: Bool, seconds: Double)?>(nil)
        Task.detached {
            let isReadable = (try? await asset.load(.isReadable)) ?? false
            let seconds = (try? await asset.load(.duration))?.seconds ?? 0
            result.update { $0 = (isReadable, seconds) }
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 2)
        if let loaded = result.value, loaded.isReadable, loaded.seconds > 0.5 {
            return url
        }
        try? FileManager.default.removeItem(at: url)
        return nil
    }

    /// NSLock 保护的可变值容器，用于跨线程传递单个值。
    private final class MutableBox<Value>: @unchecked Sendable {
        private let lock = NSLock()
        private var storedValue: Value

        init(_ value: Value) {
            storedValue = value
        }

        var value: Value {
            lock.withLock { storedValue }
        }

        func update(_ transform: (inout Value) -> Void) {
            lock.withLock { transform(&storedValue) }
        }
    }

    /// 装配 H.264 写入器与其 pixel-buffer adaptor。
    private static func makeVideoWriter(outputURL url: URL) -> VideoWriterBundle {
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 640,
            AVVideoHeightKey: 360
        ]
        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mp4) else {
            fatalError("[UITest] 无法创建 AVAssetWriter：\(url.path)")
        }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        guard writer.canAdd(input) else {
            fatalError("[UITest] AVAssetWriter 无法添加 H.264 input")
        }
        writer.add(input)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: 640,
                kCVPixelBufferHeightKey as String: 360
            ])
        return VideoWriterBundle(writer: writer, input: input, adaptor: adaptor)
    }

    private struct VideoWriterBundle {
        let writer: AVAssetWriter
        let input: AVAssetWriterInput
        let adaptor: AVAssetWriterInputPixelBufferAdaptor
    }

    /// 在后台队列按帧生产视频数据：单帧等待写入能力最多 5 秒（500 * 0.01s），
    /// 整体最多 10 秒；任一超时即返回 false（调用方 fatalError，绝不挂起启动）。
    private static func produceFrames(
        into adaptor: AVAssetWriterInputPixelBufferAdaptor,
        input: AVAssetWriterInput
    ) -> Bool {
        let fps = 30
        let duration = 4
        let producerFailed = MutableBox(false)
        let queue = DispatchQueue(label: "uitest.mock.video")
        let group = DispatchGroup()
        group.enter()
        queue.async {
            for frame in 0..<(fps * duration) {
                var spins = 0
                while !input.isReadyForMoreMediaData, spins < 500 {
                    Thread.sleep(forTimeInterval: 0.01)
                    spins += 1
                }
                guard input.isReadyForMoreMediaData else {
                    producerFailed.update { $0 = true }
                    group.leave()
                    return
                }
                let time = CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(fps))
                if let pool = adaptor.pixelBufferPool,
                    let buffer = createPixelBuffer(from: pool, frame: frame, fps: fps)
                {
                    adaptor.append(buffer, withPresentationTime: time)
                }
            }
            input.markAsFinished()
            group.leave()
        }
        return group.wait(timeout: .now() + 10) != .timedOut && !producerFailed.value
    }

    /// 结束写入并等待落盘，最多 5 秒；失败时删除半成品文件并显式报错。
    private static func finishWriting(_ writer: AVAssetWriter, outputURL url: URL) {
        writer.finishWriting {
            print("🎬 [UITest] mock player video written: \(url.path)")
        }
        var waits = 0
        while writer.status == .writing, waits < 500 {
            Thread.sleep(forTimeInterval: 0.01)
            waits += 1
        }
        guard writer.status == .completed else {
            try? FileManager.default.removeItem(at: url)
            fatalError("[UITest] 视频写入失败：\(writer.error?.localizedDescription ?? "unknown")")
        }
    }

    private static func createPixelBuffer(from pool: CVPixelBufferPool, frame: Int, fps: Int) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        guard let buffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: CVPixelBufferGetWidth(buffer),
            height: CVPixelBufferGetHeight(buffer),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        )
        // 每秒换一种颜色,便于肉眼/截图确认视频确实在播放
        let colors: [CGColor] = [
            CGColor(red: 0.2, green: 0.3, blue: 0.8, alpha: 1),
            CGColor(red: 0.8, green: 0.2, blue: 0.2, alpha: 1),
            CGColor(red: 0.1, green: 0.7, blue: 0.4, alpha: 1),
            CGColor(red: 0.8, green: 0.7, blue: 0.1, alpha: 1)
        ]
        let colorIndex = min(frame / fps, colors.count - 1)
        context?.setFillColor(colors[colorIndex])
        context?.fill(CGRect(x: 0, y: 0, width: 640, height: 360))
        // 显示帧号,便于确认播放进度（draw(at:) 使用 UIKit 当前上下文,需 Push）
        if let context {
            UIGraphicsPushContext(context)
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            let frameText = "frame \(frame)" as NSString
            frameText.draw(
                at: CGPoint(x: 20, y: 20),
                withAttributes: [
                    NSAttributedString.Key.font: UIFont.systemFont(ofSize: 32)
                ])
            UIGraphicsPopContext()
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        return buffer
    }
}
#endif
