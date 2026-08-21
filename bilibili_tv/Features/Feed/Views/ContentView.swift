import Combine
import Kingfisher
import SwiftUI

/// 主页 Tab 类型：频道 Tab + 系统搜索 Tab（sidebarAdaptable 侧边栏的 selection 类型）
enum HomeTab: Hashable {
    case channel(FeedChannel)
    case search
}

struct ContentView: View {
    @State private var viewModel: FeedViewModel
    /// 播放/详情意图协调器：叶子视图经环境直达，根视图以单一 fullScreenCover / navigationDestination 呈现
    @State private var playbackCoordinator = PlaybackCoordinator()
    #if DEBUG
    @State private var isShowingPulseConsole: Bool = false
    #endif

    /// 当前选中的 Tab：系统侧边栏（sidebarAdaptable）的 selection 事实源
    @State private var selectedTab: HomeTab = .channel(.movie)

    @MainActor
    init(viewModel: FeedViewModel? = nil) {
        _viewModel = State(initialValue: viewModel ?? FeedViewModel())
    }

    var body: some View {
        @Bindable var playbackCoordinator = playbackCoordinator
        // 📺 系统侧边栏：TabView + sidebarAdaptable 替换原自定义 ChannelSidebarView。
        // 每个频道一个 Tab，搜索用系统 role（固定放大镜入口），频道数据切换沿用原链路。
        TabView(selection: $selectedTab) {
            ForEach(FeedChannel.allCases) { channel in
                Tab(channel.title, systemImage: channel.iconName, value: HomeTab.channel(channel)) {
                    NavigationStack {
                        channelContent
                            // ▶️ 详情导航:叶子(hero 详情按钮 / shelf 卡片)经环境 coordinator 触发,
                            // 根视图以单一 navigationDestination 呈现(pop 时自动复位 activeDetail)
                            .navigationDestination(item: $playbackCoordinator.activeDetail) { movie in
                                DetailView(item: movie)
                            }
                    }
                }
            }
            // 🔍 搜索:系统 role 提供固定放大镜入口,内容复用 SearchView(结果点击经环境直达详情)
            Tab(value: .search, role: .search) {
                NavigationStack {
                    SearchView()
                        .navigationDestination(item: $playbackCoordinator.activeDetail) { movie in
                            DetailView(item: movie)
                        }
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        // ▶️ 统一播放呈现：Hero 横幅"立即播放" / 续播 shelf / 失败态续播 均经 coordinator 触发，
        // 退出后刷新本地进度（单一 cover，去重原双 cover 的重复 onDisappear 逻辑）
        .fullScreenCover(item: $playbackCoordinator.activePlayback) { context in
            playbackCover(context)
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
        .environment(\.playbackCoordinator, playbackCoordinator)
        .task {
            await performInitialLoad()
        }
        // 频道 tab 切换 → 数据切换沿用原链路：系统侧边栏只负责 UI 选中。
        // 切换副作用由绑定变化派生（viewModel.switchChannel 在加载中忽略请求，
        // 切换被接受后以 currentChannel 为准回写，避免选中与内容不一致）。
        .onChange(of: selectedTab) { _, newTab in
            guard case .channel(let channel) = newTab else { return }
            guard channel != viewModel.currentChannel else { return }
            Task {
                await viewModel.switchChannel(to: channel)
                if case .channel(let effective) = selectedTab, effective != viewModel.currentChannel {
                    selectedTab = .channel(viewModel.currentChannel)
                }
            }
        }
    }

    /// 主界面状态分发:背景 + 加载/失败/内容三态,续播 shelf 在部分态下优先渲染
    private var channelContent: some View {
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
                        }
                    )
                } else {
                    feedContent
                }
            }
        }
    }

    /// 统一播放 cover：参数来自 PlaybackContext，退出后刷新本地续播进度
    private func playbackCover(_ context: PlaybackContext) -> some View {
        PlaybackCoverView(context: context)
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
            // 仅当解码成功且已设置详情后才标记消费，
            // 解码失败时保留重试路径，避免后续 .task 无法再次尝试
            if let item = Self.makeDebugFeedItem(seasonID: debugSeasonID) {
                playbackCoordinator.openDetail(item)
                Self.didAutoOpen = true
            }
        }
        #endif
        await viewModel.fetchInitialFeed()
    }

    /// 内容态 Feed(loading/failed 但已有数据,或 idle/loaded 时渲染)
    private var feedContent: some View {
        FeedContentScrollView(viewModel: viewModel)
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

    /// UI 测试暂停轮播自动旋转（-uitestDisableRotation）：
    /// hero 轮播 8s 定时翻页会打断测试中的焦点序列（翻页改焦点归属、滚动视口），
    /// 需要做焦点导航的测试（如播放触发链路）应同时传入本参数。
    static var isUITestRotationDisabled: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-uitestDisableRotation")
        #else
        false
        #endif
    }
    #endif
}

// MARK: - Movie Shelf View
struct ShelfView: View {
    let title: String
    let items: [FeedItem]
    /// 详情导航经环境直达根视图协调器(阶段二:删除 selectedMovie 绑定钻透)
    @Environment(\.playbackCoordinator) private var playbackCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(title)
                .font(.subheadline)
                .padding(.horizontal, 50)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 25) {
                    ForEach(items) { item in
                        Button(action: {
                            playbackCoordinator.openDetail(item)
                        }) {
                            CardView(item: item)
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
struct CardView: View {
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
    /// 续播意图经环境直达根视图协调器
    @Environment(\.playbackCoordinator) private var playbackCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("继续观看")
                .font(.subheadline)
                .padding(.horizontal, 50)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 25) {
                    ForEach(items) { entry in
                        Button(action: {
                            playbackCoordinator.play(.resume(entry))
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
