import Combine
import Kingfisher
import SwiftUI

struct ContentView: View {
    @State private var viewModel: FeedViewModel
    @State private var selectedMovie: FeedItem?
    @State private var resumeToPlay: LocalWatchHistoryEntry?
    @State private var bannerToPlay: FeedItem?
    @State private var currentBannerIndex: Int? = 0
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
        isSnapshotTesting = true
        KingfisherManager.shared.cache.clearMemoryCache()
        KingfisherManager.shared.cache.clearDiskCache()
    }

    /// 与 prepareForSnapshotTesting() 配对的复位:进程级标志若不清理,
    /// 会泄漏到同进程后续测试(轮播焦点被持续抑制),制造跨用例污染。
    /// 各快照用例以 defer 保证提前退出也会复位。
    static func resetSnapshotTesting() {
        isSnapshotTesting = false
    }

    /// 快照渲染模式：由 prepareForSnapshotTesting() 置位，仅供测试前置调用。
    /// 视图据此关闭焦点副作用（defaultFocus / 兜底 Task）：
    /// drawHierarchyInKeyWindow 的真窗口会让焦点竞态性落到 Play 按钮，
    /// 展开态 + 玻璃透镜态使 hero 快照基准不可复现（precision 随机 ~0.5 失败）。
    static var isSnapshotTesting = false
    #endif
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
