import UIKit
import Kingfisher

/// 自动裁切 Logo 图片周围透明像素的 Kingfisher 图片处理器
/// 解决不同 Logo PNG 画布尺寸一致但内容边距不统一的问题
struct LogoTrimmingProcessor: ImageProcessor {
    let identifier = "com.bilibili.logo-trimming"
    
    func process(item: ImageProcessItem, options: KingfisherParsedOptionsInfo) -> KFCrossPlatformImage? {
        let image: UIImage
        switch item {
        case .image(let img):
            image = img
        case .data(let data):
            guard let img = UIImage(data: data) else { return nil }
            image = img
        }
        return image.trimmingTransparentPixels()
    }
}

extension UIImage {
    /// 扫描像素，找到非透明内容的 bounding box 并裁切
    func trimmingTransparentPixels(alphaThreshold: UInt8 = 10) -> UIImage? {
        guard let cgImage = self.cgImage else { return self }
        
        let width = cgImage.width
        let height = cgImage.height
        
        guard width > 0, height > 0 else { return self }
        
        // 分配 RGBA 像素缓冲区
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let totalBytes = height * bytesPerRow
        
        var pixelData = [UInt8](repeating: 0, count: totalBytes)
        
        guard let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return self }
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        // 扫描四个方向找到非透明内容的边界
        var minX = width
        var minY = height
        var maxX = 0
        var maxY = 0
        
        for y in 0..<height {
            for x in 0..<width {
                let alphaIndex = y * bytesPerRow + x * bytesPerPixel + 3 // RGBA 中 A 在第 4 位
                if pixelData[alphaIndex] > alphaThreshold {
                    minX = min(minX, x)
                    minY = min(minY, y)
                    maxX = max(maxX, x)
                    maxY = max(maxY, y)
                }
            }
        }
        
        // 没有找到任何非透明像素
        guard minX < maxX, minY < maxY else { return self }
        
        let contentRect = CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
        
        // 如果裁切量极小（< 5% 面积缩减），直接返回原图避免无意义的处理
        let originalArea = CGFloat(width * height)
        let croppedArea = contentRect.width * contentRect.height
        if croppedArea / originalArea > 0.95 {
            return self
        }
        
        guard let croppedCGImage = cgImage.cropping(to: contentRect) else { return self }
        
        return UIImage(cgImage: croppedCGImage, scale: self.scale, orientation: self.imageOrientation)
    }
}
