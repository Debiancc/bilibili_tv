import SwiftUI
import SwiftData
import Combine
import Kingfisher
struct ContentView: View {
    @State private var viewModel: FeedViewModel
    @State private var selectedMovie: FeedItem?
    @State private var resumeToPlay: LocalWatchHistoryEntry?
    @State private var currentBannerIndex: Int = 0
    #if DEBUG
    @State private var isShowingPulseConsole: Bool = false
    #endif
    /// 顶部 shelf 与 hero banner 的重叠量(负值=上移):
    /// 只允许 shelf 标题区与 banner 渐变重叠,卡片本体必须位于 banner 焦点框(0...1080)之下,
    /// 否则 tvOS 焦点引擎会因帧重叠而无法从 banner 下移到该 shelf 的卡片
    @State private var shelfOverlap: CGFloat = -40
    let bannerTimer = Timer.publish(every: 8, on: .main, in: .common).autoconnect()
    
    @MainActor
    init(viewModel: FeedViewModel? = nil) {
        _viewModel = State(initialValue: viewModel ?? FeedViewModel())
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background Color
                Color.black.ignoresSafeArea()
                
                // ▶️ 本地续播 shelf 优先:加载中/远程失败时也先渲染,离线启动仍可续播
                if viewModel.isLoading && viewModel.rankMovies.isEmpty && viewModel.resumeItems.isEmpty {
                    ProgressView("加载中...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = viewModel.errorMessage,
                          viewModel.rankMovies.isEmpty, viewModel.resumeItems.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 80))
                            .foregroundStyle(.orange)
                        Text("出错了")
                            .font(.headline)
                        Text(error)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Button("重试") {
                            Task {
                                await viewModel.fetchInitialFeed()
                            }
                        }
                        .buttonStyle(.glass)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 0) {
                            // 加载中/远程失败的顶部状态条(仍保留下方本地续播 shelf)
                            if let error = viewModel.errorMessage {
                                HStack(spacing: 16) {
                                    Image(systemName: "exclamationmark.triangle")
                                        .foregroundStyle(.orange)
                                    Text(error)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    Button("重试") {
                                        Task {
                                            await viewModel.fetchInitialFeed()
                                        }
                                    }
                                    .buttonStyle(.glass)
                                }
                                .padding(.top, 40)
                                .padding(.horizontal, 50)
                            } else if viewModel.isLoading, viewModel.rankMovies.isEmpty {
                                ProgressView()
                                    .padding(.top, 40)
                            }
                            // Hero Carousel
                            if !viewModel.bannerMovies.isEmpty {
                                HeroCarouselView(
                                    items: viewModel.bannerMovies,
                                    selectedIndex: $currentBannerIndex,
                                    selectedMovie: $selectedMovie
                                )
                                .frame(height: 1080)
                                .background(
                                    GeometryReader { geo in
                                        Color.clear
                                            .onChange(of: geo.frame(in: .named("feedScroll")).minY) { _, newValue in
                                                let target: CGFloat = newValue < -100 ? 0 : -40
                                                if shelfOverlap != target {
                                                    withAnimation(.easeOut(duration: 0.2)) {
                                                        shelfOverlap = target
                                                    }
                                                }
                                            }
                                    }
                                )
                                .onReceive(bannerTimer) { _ in
                                    withAnimation {
                                        currentBannerIndex = (currentBannerIndex + 1) % viewModel.bannerMovies.count
                                    }
                                }
                            }
                            
                            // Shelves
                            VStack(spacing: 60) {
                                if !viewModel.rankMovies.isEmpty {
                                    MovieShelfView(title: "电影热播榜", items: viewModel.rankMovies, selectedMovie: $selectedMovie)
                                }
                                
                                // ▶️ 继续观看:未登录或没有进行中的 PGC 观看记录时隐藏
                                if !viewModel.resumeItems.isEmpty {
                                    ResumeShelfView(items: viewModel.resumeItems) { entry in
                                        resumeToPlay = entry
                                    }
                                }
                                
                                if !viewModel.exclusiveMovies.isEmpty {
                                    MovieShelfView(title: "海量热播", items: viewModel.exclusiveMovies, selectedMovie: $selectedMovie)
                                }
                                
                                if !viewModel.comingSoonMovies.isEmpty {
                                    MovieShelfView(title: "即将上线", items: viewModel.comingSoonMovies, selectedMovie: $selectedMovie)
                                }
                                
                                Spacer(minLength: 100)
                            }
                            .padding(.top, shelfOverlap)
                        }
                    }
                    .coordinateSpace(.named("feedScroll"))
                    .edgesIgnoringSafeArea([.horizontal, .top])
                }
            }
            .navigationDestination(item: $selectedMovie) { movie in
                MovieDetailView(item: movie)
            }
            // ▶️ 继续观看:点卡片直接拉起播放器从上次进度续播
            .fullScreenCover(item: $resumeToPlay) { entry in
                BiliPlayerContainerView(
                    epId: entry.epId,
                    seasonId: entry.seasonId,
                    title: entry.title,
                    subtitle: entry.episodeTitle,
                    coverURL: entry.secureCoverURL,
                    resumeTime: Double(entry.progress)
                )
                .onDisappear {
                    // 播放器退出后刷新进度
                    Task {
                        await viewModel.fetchResumeWatching()
                    }
                }
            }
            #if DEBUG
            .fullScreenCover(isPresented: $isShowingPulseConsole) {
                PulseConsoleContainerView()
            }
            .onGlobalKeyShortcutNotification {
                print("⌨️ [ContentView] Toggle Pulse Console triggered via Notification!")
                isShowingPulseConsole.toggle()
            }
            #endif
            .task {
                #if DEBUG
                // 仅在首次 appear 时触发一次：.task 在从详情页返回时会重新执行，
                // 若不限一次会导致按 Esc 返回后又被自动带回详情页
                if !Self.didAutoOpen, let debugSeasonID = Self.debugOpenSeasonID() {
                    print("🧭 [Debug] Launch arg -debugOpenMovie detected, auto-opening season \(debugSeasonID)...")
                    // 仅当解码成功且已设置 selectedMovie 后才标记消费，
                    // 解码失败时保留重试路径，避免后续 .task 无法再次尝试
                    if let item = Self.makeDebugFeedItem(seasonID: debugSeasonID) {
                        selectedMovie = item
                        Self.didAutoOpen = true
                    }
                }
                #endif
                await viewModel.fetchInitialFeed()
            }
        }
    }

#if DEBUG
    /// 调试直达标记：保证 -debugOpenMovie 仅在 app 启动后首次 appear 触发一次
    private static var didAutoOpen = false

    /// 调试用：读取启动参数 `-debugOpenMovie <season_id>`，直接跳转到指定 PGC 详情页
    /// 用法：Xcode Scheme → Run → Arguments → 添加 `-debugOpenMovie 213048`
    private static func debugOpenSeasonID() -> Int? {
        let args = ProcessInfo.processInfo.arguments
        guard let idx = args.firstIndex(of: "-debugOpenMovie"),
              idx + 1 < args.count else { return nil }
        return Int(args[idx + 1])
    }

    /// 从 season_id 构造一个极简 FeedItem（仅需 seasonId，详情页会自行拉取完整数据）
    private static func makeDebugFeedItem(seasonID: Int) -> FeedItem? {
        let json = "{\"season_id\": \(seasonID)}"
        return try? JSONDecoder().decode(FeedItem.self, from: Data(json.utf8))
    }
#endif
}

// MARK: - Hero Carousel View
struct HeroCarouselView: View {
    let items: [FeedItem]
    @Binding var selectedIndex: Int
    @Binding var selectedMovie: FeedItem?
    
    var body: some View {
        TabView(selection: $selectedIndex) {
            ForEach(Array(items.enumerated()), id: \.element) { index, item in
                Button(action: {
                    selectedMovie = item
                }) {
                    HeroBannerView(item: item)
                }
                .buttonStyle(.plain) // Use plain to prevent card scaling on full-bleed images
                .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
    }
}

// MARK: - Hero Banner View
struct HeroBannerView: View {
    let item: FeedItem
    
    private var fallbackTitleText: some View {
        Text(item.title ?? "未知影片")
            .font(.system(size: 38, weight: .bold))
            .foregroundStyle(.white)
            .lineLimit(1)
    }
    
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Background Image
            KFImage(item.secureOverlayURL ?? item.highResCoverURL ?? item.secureCoverURL)
                .placeholder {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .fade(duration: 0.25)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            
            // Gradient Overlays for Legibility & Shelf Blending
            ZStack {
                // Vertical gradient for bottom shelf overlap
                LinearGradient(
                    gradient: Gradient(colors: [.clear, .black.opacity(0.95)]),
                    startPoint: .center,
                    endPoint: .bottom
                )
                
                // Horizontal gradient specifically for bottom-left text legibility
                LinearGradient(
                    gradient: Gradient(colors: [.black.opacity(0.9), .clear]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .padding(.trailing, 300) // Keep the right side of the screen clean
                .mask(
                    LinearGradient(
                        gradient: Gradient(colors: [.clear, .black]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
            
            // Content
            VStack(alignment: .leading, spacing: 10) {
                if let logoURL = item.secureLogoURL {
                    KFImage(logoURL)
                        .setProcessor(LogoTrimmingProcessor())
                        .placeholder {
                            fallbackTitleText
                        }
                        .onFailureView {
                            fallbackTitleText
                        }
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 500, maxHeight: 240, alignment: .leading)
                } else {
                    fallbackTitleText
                }
                
                // Meta info (category & tag)
                if let fusionInfo = item.ogvFusionInfo {
                    let metaText = [fusionInfo.category, fusionInfo.tag]
                        .compactMap { $0 }
                        .filter { !$0.isEmpty }
                        .joined(separator: " • ")
                    
                    if !metaText.isEmpty {
                        Text(metaText.uppercased())
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(1)
                    }
                }
                
                // Description
                if let desc = item.desc, !desc.isEmpty {
                    Text(desc)
                        .font(.system(size: 23, weight: .regular))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(2)
                        .lineSpacing(4)
                        .frame(maxWidth: 700, alignment: .leading)
                }
            }
            .padding(.horizontal, 90)
            .padding(.bottom, 280) // Push content well above the overlapping shelf
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            let bgURL = item.secureOverlayURL ?? item.highResCoverURL ?? item.secureCoverURL
//            print("🚀 [HeroBanner] Loading background image: \(bgURL?.absoluteString ?? "nil") for title: \(item.title ?? "Unknown")")
        }
    }
}

// MARK: - Movie Shelf View
struct MovieShelfView: View {
    let title: String
    let items: [FeedItem]
    @Binding var selectedMovie: FeedItem?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(title)
                .font(.subheadline)
                .padding(.horizontal, 50)
            
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 25) {
                    ForEach(items) { item in
                        Button(action: {
                            selectedMovie = item
                        }) {
                            MovieCardView(item: item)
                        }
                        .buttonStyle(.card)
                    }
                }
                .padding(.horizontal, 50)
                .padding(.vertical, 0) // Padding for focus scaling
            }
            .scrollClipDisabled() // Allow cards to scale outside scroll view bounds on tvOS 17+
        }
    }
}

// MARK: - Movie Card View
struct MovieCardView: View {
    let item: FeedItem
    
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            KFImage(item.secureCoverURL)
                .placeholder {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .overlay(
                            Image(systemName: "film")
                                .font(.system(size: 40))
                                .foregroundStyle(.white.opacity(0.4))
                        )
                }
                .fade(duration: 0.25)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 250, height: 375)
                .clipped()
            
            // 底部渐变 + 片名(仿"继续观看"卡片的标题样式)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title ?? "未知影片")
                    .font(.caption)
                    .bold()
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(maxHeight: .infinity, alignment: .bottomLeading)
            .background(
                LinearGradient(
                    colors: [.clear, .black.opacity(0.85)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            
//            if let rating = item.rating, !rating.isEmpty {
//                Text(rating)
//                    .font(.caption)
//                    .bold()
//                    .padding(6)
//                    .background(Color.orange)
//                    .foregroundStyle(.white)
//                    .cornerRadius(4)
//                    .padding(10)
//            }
        }
        .frame(width: 250, height: 375)
//        .cornerRadius(2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.title ?? "未知电影")
    }
}

// MARK: - ▶️ 继续观看 Shelf View
struct ResumeShelfView: View {
    let items: [LocalWatchHistoryEntry]
    let onSelect: (LocalWatchHistoryEntry) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("继续观看")
                .font(.subheadline)
                .padding(.horizontal, 50)
            
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 25) {
                    ForEach(items) { entry in
                        Button(action: {
                            onSelect(entry)
                        }) {
                            ResumeCardView(entry: entry)
                        }
                        .buttonStyle(.card)
                    }
                }
                .padding(.horizontal, 50)
                .padding(.vertical, 0)
            }
            .scrollClipDisabled()
        }
    }
}

// MARK: - ▶️ 继续观看卡片 (封面 + 底部进度条)
struct ResumeCardView: View {
    let entry: LocalWatchHistoryEntry
    
    private func formatTime(_ seconds: Int) -> String {
        let s = max(seconds, 0)
        let h = s / 3600
        let m = (s % 3600) / 60
        let sec = s % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, sec)
        }
        return String(format: "%02d:%02d", m, sec)
    }
    
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            KFImage(entry.secureCoverURL)
                .placeholder {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .overlay(
                            Image(systemName: "film")
                                .font(.system(size: 40))
                                .foregroundStyle(.white.opacity(0.4))
                        )
                }
                .fade(duration: 0.25)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 267, height: 225)
                .clipped()
            
            // 底部信息区:剧名/集数 + 进度条 + 时间
            VStack(alignment: .leading, spacing: 6) {
                Text(entry.title)
                    .font(.caption)
                    .bold()
                    .foregroundStyle(.white)
                    .lineLimit(1)
                
                if let episodeTitle = entry.episodeTitle, !episodeTitle.isEmpty {
                    Text(episodeTitle)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.8))
                        .lineLimit(1)
                }
                
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.3))
                        Capsule()
                            .fill(Color.white)
                            .frame(width: geo.size.width * entry.progressRatio)
                    }
                }
                .frame(height: 4)
                
                Text("\(formatTime(entry.progress))/\(formatTime(entry.duration))")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.8))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [.clear, .black.opacity(0.85)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        .frame(width: 267, height: 225)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("继续观看 \(entry.title) \(entry.episodeTitle ?? "") 进度 \(Int(entry.progressRatio * 100))%")
    }
}

#Preview {
    ContentView(viewModel: FeedViewModel.mock)
}
