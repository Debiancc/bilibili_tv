import Combine
import Kingfisher
import SwiftUI

/// 主页 Tab 类型：频道 Tab + 系统搜索 Tab（sidebarAdaptable 侧边栏的 selection 类型）
enum HomeTab: Hashable {
    case channel(FeedChannel)
    case search
    /// 账号页（侧边栏顶部：头像 + 昵称）
    case account
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

    #if compiler(>=6.4)
    /// tvOS 27+ 账号页呈现标记:经 sidebar header 点击弹出(fullScreenCover)
    @State private var isAccountPresented = false
    #endif

    @MainActor
    init(viewModel: FeedViewModel? = nil) {
        _viewModel = State(initialValue: viewModel ?? FeedViewModel())
    }

    var body: some View {
        #if compiler(>=6.4)
        // 🎯 tvOS 27+: 账号头像+昵称作为 sidebar 顶部 header(tabViewSidebarHeader,公开 API),
        // 点击以 fullScreenCover 弹出账号页——不占 sidebar 条目(空 label Tab 会渲染空白药丸);
        // tvOS <27 回退为 sidebar 首条 item(label 渲染头像)。
        if #available(tvOS 27.0, *) {
            mainTabView
                .tabViewSidebarHeader { accountSidebarHeader }
                .fullScreenCover(isPresented: $isAccountPresented) { accountSheet }
                // 账号页 cover 与播放 cover 一样不保证触发底层视图 onDisappear:
                // 经 coordinator 显式标记,轮播背景视频据此暂停
                .onChange(of: isAccountPresented) { _, presented in
                    playbackCoordinator.isAccountOverlayPresented = presented
                }
        } else {
            mainTabView
        }
        #else
        mainTabView
        #endif
    }

    #if compiler(>=6.4)
    /// sidebar header 内容:头像+昵称,点击弹出账号页
    private var accountSidebarHeader: some View {
        Button {
            isAccountPresented = true
        } label: {
            AccountSidebarLabel(showsName: true)
        }
        .buttonStyle(.plain)
    }

    /// 账号页(cover 呈现):右上角关闭按钮;退出登录后由 AuthManager 驱动根视图切换
    private var accountSheet: some View {
        AccountView()
            .overlay(alignment: .topTrailing) {
                Button {
                    isAccountPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 40))
                        .padding(40)
                }
                .buttonStyle(.plain)
            }
    }
    #endif

    /// 账号 Tab(承载账号页):仅 tvOS <27 使用(首条 item);tvOS 27+ 由 header cover 呈现,不占条目
    @TabContentBuilder<HomeTab>
    private var accountTab: some TabContent<HomeTab> {
        #if compiler(>=6.4)
        if #unavailable(tvOS 27.0) {
            Tab(value: HomeTab.account) {
                NavigationStack {
                    AccountView()
                }
            } label: {
                AccountSidebarLabel()
            }
        }
        #else
        Tab(value: HomeTab.account) {
            NavigationStack {
                AccountView()
            }
        } label: {
            AccountSidebarLabel()
        }
        #endif
    }

    /// 主 TabView 完整链:所有共享导航/呈现样式集中于此
    @ViewBuilder
    private var mainTabView: some View {
        @Bindable var playbackCoordinator = playbackCoordinator
        TabView(selection: $selectedTab) {
            accountTab
            ForEach(FeedChannel.allCases) { channel in
                Tab(channel.title, systemImage: channel.iconName, value: HomeTab.channel(channel)) {
                    NavigationStack {
                        channelContent(for: channel)
                            // ▶️ 详情导航:叶子(hero 详情按钮 / shelf 卡片)经环境 coordinator 触发,
                            // 根视图以 navigationDestination 呈现(pop 时自动复位 activeDetail)
                            .navigationDestination(item: detailBinding(for: .channel(channel))) { movie in
                                DetailView(item: movie)
                            }
                    }
                }
            }
            // 🔍 搜索:系统 role 提供固定放大镜入口,内容复用 SearchView(结果点击经环境直达详情)
            Tab(value: .search, role: .search) {
                NavigationStack {
                    SearchView()
                        .navigationDestination(item: detailBinding(for: .search)) { movie in
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
        .onChange(of: isShowingPulseConsole) { _, shown in
            playbackCoordinator.isPulseConsoleOverlayPresented = shown
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
        // 切换副作用由绑定变化派生：switchChannel 内部串行化切换流程，
        // 加载中收到的新选择记为 pending 并在当前加载完成后继续消费；
        // 仅首屏拉取中的切换会被丢弃，此时以 currentChannel 为准回写选中态。
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

    /// 详情绑定按 Tab 隔离:sidebarAdaptable 下每个 Tab 各有独立 NavigationStack,
    /// 若它们共享同一个 activeDetail,设值时所有栈(含不可见 Tab)会一起 push、
    /// menu 返回时一起 pop,焦点没有确定落点(返回后回不到 feed 卡片)。
    /// 只有拥有该详情的 Tab 透出非 nil,写入直达 coordinator(pop 时自动复位);
    /// 复位(nil 写入)仅 owner tab 生效,防止其它栈的杂散 set(nil) 误清详情。
    private func detailBinding(for tab: HomeTab) -> Binding<FeedItem?> {
        Binding(
            get: { playbackCoordinator.activeDetailOwner == tab ? playbackCoordinator.activeDetail : nil },
            set: { newItem in
                if let newItem {
                    playbackCoordinator.openDetail(newItem, owner: tab)
                } else if playbackCoordinator.activeDetailOwner == tab {
                    playbackCoordinator.clearDetail()
                }
            }
        )
    }

    /// 主界面状态分发:背景 + 加载/失败/内容三态,续播 shelf 在部分态下优先渲染。
    /// 按频道参数化:ownerTab 固定为该 Tab 自身频道(此前共享全局 selectedTab,
    /// 非选中 Tab 的内容会拿到错误的 ownerTab),isTabSelected 驱动轮播视频的
    /// 「本 Tab 可见」门控(TabView 切换不依赖 onDisappear)
    private func channelContent(for channel: FeedChannel) -> some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // ▶️ 本地续播 shelf 优先:加载中/远程失败时也先渲染,离线启动仍可续播
            // ⚠️ 全屏加载态只看远程数据(rank/banner)是否就绪,不能因 resumeItems 已填充
            // 而提前退出——否则冷启动会先单独闪出「继续观看」shelf,再出现完整主界面。
            let isTabSelected = selectedTab == .channel(channel)
            // ⚠️ 必须在 body 求值内读取(Observation 追踪才生效):
            // 覆盖状态变化(详情 push/pop 等)驱动 feed 内容刷新,
            // 轮播视频/计时器经透传的门控同步暂停/恢复
            let isFeedCovered = playbackCoordinator.isFeedCovered(for: .channel(channel))
            switch viewModel.state {
            case .idle, .loaded:
                feedContent(for: .channel(channel), isTabSelected: isTabSelected, isFeedCovered: isFeedCovered)
            case .loading:
                if viewModel.rankMovies.isEmpty && viewModel.bannerMovies.isEmpty {
                    FeedLoadingView()
                } else {
                    feedContent(for: .channel(channel), isTabSelected: isTabSelected, isFeedCovered: isFeedCovered)
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
                    feedContent(for: .channel(channel), isTabSelected: isTabSelected, isFeedCovered: isFeedCovered)
                }
            }
        }
    }

    /// 统一播放 cover:参数来自 PlaybackContext,退出后刷新本地续播进度
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
                playbackCoordinator.openDetail(item, owner: selectedTab)
                Self.didAutoOpen = true
            }
        }
        #endif
        await viewModel.fetchInitialFeed()
    }

    /// 内容态 Feed(loading/failed 但已有数据,或 idle/loaded 时渲染)
    /// isTabSelected 驱动轮播视频的「本 Tab 可见」门控(TabView 切换不依赖 onDisappear);
    /// isFeedCovered 驱动「无路由/覆盖遮挡」门控(详情页/播放 cover/账号页/控制台)
    private func feedContent(for ownerTab: HomeTab, isTabSelected: Bool, isFeedCovered: Bool) -> some View {
        FeedContentScrollView(viewModel: viewModel, ownerTab: ownerTab, isTabSelected: isTabSelected, isFeedCovered: isFeedCovered)
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

    // MARK: UITest 启动参数（Release 也可编译）
    // 以下两个成员必须位于上面的 #if DEBUG 区之外：app target 的 Release 配置
    // 不定义 DEBUG（project.pbxproj 仅 Debug 设 SWIFT_ACTIVE_COMPILATION_CONDITIONS），
    // 而 HeroCarouselView 的引用点（PageIndicatorView ticker、rotationInterval）
    // 无条件调用，Release 下需要这两个成员存在——内部 #if DEBUG 提供非 DEBUG 兜底。
    // 快照测试成员（isSnapshotTesting 等）的所有引用点均已 #if DEBUG 守卫，
    // 可继续留在上方 DEBUG-only 区。

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

    /// UI 测试自定义自动轮播间隔（-uitestRotationInterval=<秒>）：
    /// 仅 testAutoRotateKeepsNewPage 使用——等真实 8s 轮播是该用例的主要固定耗时，
    /// 传短间隔（如 2s）把"等待轮播翻页"压缩到秒级；其余焦点测试一律传
    /// -uitestDisableRotation 暂停轮播。非 DEBUG 构建恒为 nil（落回默认 8s）。
    static var uitestRotationInterval: TimeInterval? {
        #if DEBUG
        let prefix = "-uitestRotationInterval="
        guard
            let flag = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix(prefix) }),
            let seconds = TimeInterval(flag.dropFirst(prefix.count)),
            // 拒绝 0/负数/非有限值:PageIndicatorView 以此为分母,0 会让进度每个
            // tick 即满格(0.1s 翻页)、负数/NaN/inf 让轮播永不发生
            seconds.isFinite,
            seconds > 0
        else { return nil }
        return seconds
        #else
        return nil
        #endif
    }
}

// MARK: - Movie Shelf View
struct ShelfView: View {
    let title: String
    let items: [FeedItem]
    let ownerTab: HomeTab
    /// 详情导航经环境直达根视图协调器(阶段二:删除 selectedMovie 绑定钻透)
    @Environment(\.playbackCoordinator) private var playbackCoordinator
    /// 卡片级焦点标识(值 = FeedItem.id,行内唯一):行尾回绕时程序性写回首卡
    @FocusState private var focusedCardID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(title)
                .font(.subheadline)
                .padding(.horizontal, 50)

            // 非 Lazy:回绕要把焦点程序性写到任意卡(含离屏首卡),
            // LazyHStack 回收后的卡没有可寻焦节点;行卡数量有上限,代价可接受
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: ShelfWrapAnchor.rowSpacing) {
                    ForEach(items) { item in
                        Button(action: {
                            playbackCoordinator.openDetail(item, owner: ownerTab)
                        }) {
                            CardView(item: item)
                        }
                        .buttonStyle(.card)
                        .focused($focusedCardID, equals: item.id)
                    }
                    ShelfWrapAnchor(
                        height: CardView.contentSize.height,
                        isFocusEnabled: ShelfWrapAnchor.isRowWrapEnabled(itemCount: items.count)
                    ) {
                        focusedCardID = items.first?.id
                    }
                }
                .padding(.horizontal, 50)
                // 抵消锚点占位(宽+间距),卡片绝对位置与快照基线保持不变
                .padding(.trailing, ShelfWrapAnchor.layoutCompensation)
                .padding(.vertical, 0)  // Padding for focus scaling
            }
            .scrollClipDisabled()  // Allow cards to scale outside scroll view bounds on tvOS 17+
        }
    }
}

// MARK: - Movie Card View
struct CardView: View {
    /// 卡片固定尺寸(行回绕锚点与快照基线共享该值)
    static let contentSize = CGSize(width: 250, height: 375)

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
                .scaledToFill()
                .frame(width: Self.contentSize.width, height: Self.contentSize.height)
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
        .frame(width: Self.contentSize.width, height: Self.contentSize.height)
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
    /// 卡片级焦点标识(值 = LocalWatchHistoryEntry.id):行尾回绕时写回首卡
    @FocusState private var focusedEntryID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("继续观看")
                .font(.subheadline)
                .padding(.horizontal, 50)

            // 非 Lazy:同 ShelfView,回绕需可寻焦到离屏首卡
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: ShelfWrapAnchor.rowSpacing) {
                    ForEach(items) { entry in
                        Button(action: {
                            playbackCoordinator.play(.resume(entry))
                        }) {
                            ResumeCardView(entry: entry)
                        }
                        .buttonStyle(.card)
                        .focused($focusedEntryID, equals: entry.id)
                    }
                    ShelfWrapAnchor(
                        height: ResumeCardView.contentSize.height,
                        isFocusEnabled: ShelfWrapAnchor.isRowWrapEnabled(itemCount: items.count)
                    ) {
                        focusedEntryID = items.first?.id
                    }
                }
                .padding(.horizontal, 50)
                // 抵消锚点占位(宽+间距),与快照基线保持一致
                .padding(.trailing, ShelfWrapAnchor.layoutCompensation)
                .padding(.vertical, 0)
            }
            .scrollClipDisabled()
        }
    }
}

// MARK: - ▶️ 继续观看卡片 (封面 + 底部进度条)
struct ResumeCardView: View {
    /// 卡片固定尺寸(行回绕锚点与快照基线共享该值)
    static let contentSize = CGSize(width: 267, height: 225)

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
                .scaledToFill()
                .frame(width: Self.contentSize.width, height: Self.contentSize.height)
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
        .frame(width: Self.contentSize.width, height: Self.contentSize.height)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("继续观看 \(entry.title) \(entry.episodeTitle ?? "") 进度 \(Int(entry.progressRatio * 100))%")
    }
}

#Preview {
    ContentView(viewModel: FeedViewModel.mock)
}
