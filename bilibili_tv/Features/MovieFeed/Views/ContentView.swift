import Combine
import Kingfisher
import SwiftUI

struct ContentView: View {
    @State private var viewModel: FeedViewModel
    @State private var selectedMovie: FeedItem?
    @State private var resumeToPlay: LocalWatchHistoryEntry?
    @State private var bannerToPlay: FeedItem?
    @State private var currentBannerIndex: Int = 0
    #if DEBUG
    @State private var isShowingPulseConsole: Bool = false
    #endif
    /// 顶部 shelf 与 hero banner 的重叠量(负值=上移):
    /// 只允许 shelf 标题区与 banner 渐变重叠,卡片本体必须位于 banner 焦点框(0...1080)之下,
    /// 否则 tvOS 焦点引擎会因帧重叠而无法从 banner 下移到该 shelf 的卡片
    @State private var shelfOverlap: CGFloat = -120

    /// 当前选中的 PGC 频道（决定主 feed 内容，侧栏悬浮切换）
    @State private var selectedChannel: FeedChannel = .movie

    @MainActor
    init(viewModel: FeedViewModel? = nil) {
        _viewModel = State(initialValue: viewModel ?? FeedViewModel())
    }

    var body: some View {
        NavigationStack {
            mainStackContent
        }
        .navigationDestination(item: $selectedMovie) { movie in
            MovieDetailView(item: movie)
        }
        // ▶️ 继续观看:点卡片直接拉起播放器从上次进度续播
        .fullScreenCover(item: $resumeToPlay) { entry in
            resumePlaybackCover(entry)
        }
        // ▶️ Hero 横幅"立即播放":直接拉起播放器
        .fullScreenCover(item: $bannerToPlay) { item in
            bannerPlaybackCover(item)
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
            await performInitialLoad()
        }
    }

    /// 主界面状态分发:背景 + 加载/失败/内容三态,续播 shelf 在部分态下优先渲染
    private var mainStackContent: some View {
        ZStack {
            // Background Color
            Color.black.ignoresSafeArea()

            // ▶️ 本地续播 shelf 优先:加载中/远程失败时也先渲染,离线启动仍可续播
            // ⚠️ 全屏加载态只看远程数据(rank/banner)是否就绪,不能因 resumeItems 已填充
            // 而提前退出——否则冷启动会先单独闪出「继续观看」shelf,再出现完整主界面。
            switch viewModel.state {
            case .idle, .loaded:
                feedContent
            case .loading:
                if viewModel.rankMovies.isEmpty && viewModel.bannerMovies.isEmpty {
                    FeedLoadingView()
                } else {
                    feedContent
                }
            case .failed(let message):
                if viewModel.rankMovies.isEmpty {
                    FeedErrorView(
                        errorMessage: message,
                        resumeItems: viewModel.resumeItems,
                        onRetry: {
                            Task {
                                await viewModel.fetchInitialFeed()
                            }
                        },
                        onResume: { resumeToPlay = $0 }
                    )
                } else {
                    feedContent
                }
            }
        }
        // ⚠️ 悬浮侧栏放 ZStack 内容之后:侧栏是浮层(不参与主内容布局),
        // 放在 ZStack 内会压缩/遮蔽 feed 卡片。用 overlay 保证不挤压主视图宽度,
        // 同时侧栏焦点独立于主内容(焦点引擎按 frame 重叠路由方向键)。
        .overlay(alignment: .leading) {
            ChannelSidebarView(
                channels: FeedChannel.allCases,
                selectedChannel: $selectedChannel,
                isInteractionReady: isSidebarInteractionReady,
                onSelect: { channel in
                    // ⚠️ 先同步 UI 选中态再发起切换;但 switchChannel 在加载中会忽略请求,
                    // 需在切换被接受后以 viewModel.currentChannel 为准回写,避免侧边栏与
                    // feed 频道不一致(选中显示 A,内容仍是 B)。
                    selectedChannel = channel
                    // 切频道后 hero 轮播内容整体替换,索引归零避免 TabView selection 越界
                    currentBannerIndex = 0
                    Task {
                        await viewModel.switchChannel(to: channel)
                        if selectedChannel != viewModel.currentChannel {
                            selectedChannel = viewModel.currentChannel
                        }
                    }
                }
            )
        }
    }

    /// 续播播放器 cover:退出后刷新本地进度
    private func resumePlaybackCover(_ entry: LocalWatchHistoryEntry) -> some View {
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

    /// 横幅播放器 cover:退出后刷新续播进度
    private func bannerPlaybackCover(_ item: FeedItem) -> some View {
        BiliPlayerContainerView(
            epId: item.episodeId,
            seasonId: item.seasonId,
            title: item.title,
            subtitle: item.subtitle,
            coverURL: item.secureCoverURL
        )
        .onDisappear {
            // 播放器退出后刷新续播进度
            Task {
                await viewModel.fetchResumeWatching()
            }
        }
    }

    /// 启动任务:调试直达（仅首帧一次）+ 拉取初始 Feed
    private func performInitialLoad() async {
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

    /// 侧边栏交互闸门:主内容区存在可聚焦元素时才允许"聚焦即展开"。
    /// 冷启动加载中(loading 且无数据)主区只有 FeedLoadingView(无焦点项),
    /// 入口按钮会独占初始焦点,若允许展开会在 feed 就绪后 hero 抢焦点时闪一下又收起。
    private var isSidebarInteractionReady: Bool {
        switch viewModel.state {
        case .idle:
            // 空 feedContent(无卡片/无焦点项),等待 .task 触发加载
            return false
        case .loading:
            // 已有数据的 loading 态渲染 feedContent(有焦点项)
            return !viewModel.rankMovies.isEmpty || !viewModel.bannerMovies.isEmpty
        case .loaded, .failed:
            // loaded 渲染 feedContent;failed 渲染 FeedErrorView(重试按钮可聚焦)
            return true
        }
    }

    /// 内容态 Feed(loading/failed 但已有数据,或 idle/loaded 时渲染)
    private var feedContent: some View {
        FeedContentScrollView(
            viewModel: viewModel,
            selectedMovie: $selectedMovie,
            currentBannerIndex: $currentBannerIndex,
            bannerToPlay: $bannerToPlay,
            shelfOverlap: $shelfOverlap,
            onResume: { resumeToPlay = $0 }
        )
    }

    #if DEBUG
    /// 调试直达标记：保证 -debugOpenMovie 仅在 app 启动后首次 appear 触发一次
    private static var didAutoOpen = false

    /// 调试用：读取启动参数 `-debugOpenMovie <season_id>`，直接跳转到指定 PGC 详情页
    /// 用法：Xcode Scheme → Run → Arguments → 添加 `-debugOpenMovie 213048`
    private static func debugOpenSeasonID() -> Int? {
        let args = ProcessInfo.processInfo.arguments
        guard let idx = args.firstIndex(of: "-debugOpenMovie"),
            idx + 1 < args.count
        else { return nil }
        return Int(args[idx + 1])
    }

    /// 从 season_id 构造一个极简 FeedItem（仅需 seasonId，详情页会自行拉取完整数据）
    private static func makeDebugFeedItem(seasonID: Int) -> FeedItem? {
        let json = "{\"season_id\": \(seasonID)}"
        return try? JSONDecoder().decode(FeedItem.self, from: Data(json.utf8))
    }

    /// Snapshot 测试用：清空 Kingfisher 内存/磁盘缓存，保证 KFImage 在同步渲染瞬间
    /// 必然停留在 placeholder（灰块）状态，使快照在本地与 CI 之间确定性一致。
    /// 否则热缓存会渲染真实海报、冷缓存渲染灰块，同一基准在不同机器上无法复现。
    static func prepareForSnapshotTesting() {
        KingfisherManager.shared.cache.clearMemoryCache()
        KingfisherManager.shared.cache.clearDiskCache()
    }
    #endif
}

// MARK: - Hero Focus

/// 每个 hero 页内可聚焦操作的唯一焦点标识（解耦页码，跨页翻页时保持按钮类型一致）
enum HeroButtonFocus: Hashable {
    case play
    case detail
    case bookmark
    case next
}

// MARK: - Hero Carousel View
struct HeroCarouselView: View {
    let items: [FeedItem]
    @Binding var selectedIndex: Int
    @Binding var selectedMovie: FeedItem?
    @Binding var bannerToPlay: FeedItem?
    /// 指示条随 shelf 重叠量同步上移(负值=上移)
    var indicatorOffset: CGFloat = 0
    /// 记录焦点当前落在哪个 hero 操作(nil = 焦点已移出 hero,如停在 shelf 上)
    @FocusState private var focusedButton: HeroButtonFocus?

    var body: some View {
        TabView(selection: $selectedIndex) {
            ForEach(Array(items.enumerated()), id: \.element) { index, item in
                HeroBannerView(
                    item: item,
                    buttonFocus: $focusedButton,
                    onPlay: { bannerToPlay = item },
                    onDetail: { selectedMovie = item },
                    onNext: {
                        withAnimation {
                            selectedIndex = (selectedIndex + 1) % items.count
                        }
                    }
                )
                .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        // tvOS 焦点锚点:首次进入页面时默认聚焦 Play 按钮。
        // 原来 Play 用 .glassProminent 时天然是页面首选焦点;改回 .glass 圆钮后失去该锚点,
        // 页面级方向键会直接掉到 shelf。显式声明默认焦点以恢复"方向键先进按钮组"。
        .defaultFocus($focusedButton, .play, priority: .automatic)
        .onAppear {
            // 兜底:defaultFocus 在部分 tvOS 版本/场景下不生效,显式聚焦首屏 Play 按钮。
            // 延迟一拍等 TabView 页面与按钮完成布局,再写入焦点。
            if focusedButton == nil {
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    if focusedButton == nil {
                        focusedButton = .play
                    }
                }
            }
        }
        .overlay(alignment: .bottom) {
            PageIndicatorView(
                count: items.count,
                selectedIndex: $selectedIndex
            )
            .padding(.bottom, 20)
            .offset(y: indicatorOffset)
            .animation(.easeOut(duration: 0.2), value: indicatorOffset)
        }
    }
}

// MARK: - Page Indicator View (active 展开为带倒计时进度的线段)
/// 当前页指示器:active 时展开成一条线段并在内部填充倒计时进度(填满即自动翻页),
/// deactive 时收回为圆点。任何 selection 变化(定时翻页或用户手动方向键翻页)都会重置进度。
struct PageIndicatorView: View {
    let count: Int
    @Binding var selectedIndex: Int
    /// 自动轮播间隔(秒),默认 8s
    var rotationInterval: TimeInterval = 8
    /// active 线段完全展开后的宽度
    var expandedWidth: CGFloat = 24
    /// 圆点直径(也是线段高度)
    var dotSize: CGFloat = 8

    @State private var progress: CGFloat = 0
    private let ticker = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<max(count, 1), id: \.self) { index in
                indicator(for: index)
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selectedIndex)
            }
        }
        .onReceive(ticker) { _ in
            guard count > 1 else { return }
            let step = CGFloat(0.1 / rotationInterval)
            let newValue = progress + step
            if newValue >= 1 {
                withAnimation {
                    selectedIndex = (selectedIndex + 1) % count
                }
                progress = 0
            } else {
                progress = newValue
            }
        }
        .onChange(of: selectedIndex) { _, _ in
            progress = 0
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func indicator(for index: Int) -> some View {
        let isActive = index == selectedIndex
        ZStack(alignment: .leading) {
            Capsule()
                .fill(Color.white.opacity(0.35))
            if isActive {
                Capsule()
                    .fill(Color.white)
                    .frame(width: (isActive ? expandedWidth : dotSize) * min(progress, 1))
            }
        }
        .frame(width: isActive ? expandedWidth : dotSize, height: dotSize)
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
                .padding(.vertical, 0)  // Padding for focus scaling
            }
            .scrollClipDisabled()  // Allow cards to scale outside scroll view bounds on tvOS 17+
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
        let h = s / 3_600
        let m = (s % 3_600) / 60
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
