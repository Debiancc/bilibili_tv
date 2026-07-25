import SwiftUI
import Observation

/// 🌟 特性 3：Swift 6 原生 actor 线程安全内存缓存管理器
actor ImageCacheManager {
    static let shared = ImageCacheManager()
    
    private var cache: [URL: UIImage] = [:]
    private let limit = 150
    
    private init() {}
    
    func image(for url: URL) -> UIImage? {
        return cache[url]
    }
    
    func insertImage(_ image: UIImage, for url: URL) {
        if cache.count >= limit {
            cache.removeAll()
        }
        cache[url] = image
    }
}

/// 支持 Swift 6 actor 缓存的轻量级 AsyncImage 替换组件
struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    let url: URL?
    @ViewBuilder let content: (Image) -> Content
    @ViewBuilder let placeholder: () -> Placeholder
    
    @State private var loadedImage: UIImage? = nil
    
    var body: some View {
        Group {
            if let uiImage = loadedImage {
                content(Image(uiImage: uiImage))
            } else {
                placeholder()
                    .task(id: url) {
                        await loadImage()
                    }
            }
        }
        .task(id: url) {
            // 🌟 特性 4：语法解包简写与 actor 异步提取
            guard let url, loadedImage == nil else { return }
            if let cached = await ImageCacheManager.shared.image(for: url) {
                self.loadedImage = cached
            }
        }
    }
    
    private func loadImage() async {
        // 🌟 特性 4：Swift 现代 Optional 解包简写
        guard let url else { return }
        
        if let cached = await ImageCacheManager.shared.image(for: url) {
            self.loadedImage = cached
            return
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let uiImage = UIImage(data: data) {
                await ImageCacheManager.shared.insertImage(uiImage, for: url)
                await MainActor.run {
                    self.loadedImage = uiImage
                }
            }
        } catch {
            // 静默失败，显示 placeholder
        }
    }
}
