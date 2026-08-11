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

    /// 生成 4 秒 640x360 色块视频（H.264），首次生成后缓存到 tmp 目录
    @MainActor
    private static func generateVideoIfNeeded() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("uitest_mock_player.mp4")
        if FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        let writer = try? AVAssetWriter(outputURL: url, fileType: .mp4)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 640,
            AVVideoHeightKey: 360
        ]
        guard let writer, writer.canAdd(AVAssetWriterInput(mediaType: .video, outputSettings: settings)) else {
            return url
        }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        writer.add(input)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: 640,
                kCVPixelBufferHeightKey as String: 360
            ])
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        let queue = DispatchQueue(label: "uitest.mock.video")
        let group = DispatchGroup()
        group.enter()
        queue.async {
            let fps = 30
            let duration = 4
            for frame in 0..<(fps * duration) {
                while !input.isReadyForMoreMediaData {
                    Thread.sleep(forTimeInterval: 0.01)
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
        group.wait()
        writer.finishWriting {
            print("🎬 [UITest] mock player video written: \(url.path)")
        }
        while writer.status == .writing {
            Thread.sleep(forTimeInterval: 0.01)
        }
        return url
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
