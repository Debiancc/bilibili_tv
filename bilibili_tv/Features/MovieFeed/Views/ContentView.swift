import Combine
import Kingfisher
import SwiftData
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
                // ⚠️ 全屏加载态只看远程数据(rank/banner)是否就绪,不能因 resumeItems 已填充
                // 而提前退出——否则冷启动会先单独闪出「继续观看」shelf,再出现完整主界面。
                if viewModel.isLoading && viewModel.rankMovies.isEmpty && viewModel.bannerMovies.isEmpty {
                    ProgressView("加载中...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = viewModel.errorMessage,
                    viewModel.rankMovies.isEmpty
                {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 60) {
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
                            .padding(.top, 120)
                            // ▶️ 远程失败时仍保留本地续播 shelf,离线可续播
                            if !viewModel.resumeItems.isEmpty {
                                ResumeShelfView(items: viewModel.resumeItems) { entry in
                                    resumeToPlay = entry
                                }
                            }
                        }
                    }
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
                                    selectedMovie: $selectedMovie,
                                    bannerToPlay: $bannerToPlay,
                                    indicatorOffset: shelfOverlap
                                )
                                .frame(height: 1_080)
                                .background(
                                    GeometryReader { geo in
                                        Color.clear
                                            .onChange(of: geo.frame(in: .named("feedScroll")).minY) { _, newValue in
                                                let target: CGFloat = newValue < -100 ? 0 : -120
                                                if shelfOverlap != target {
                                                    withAnimation(.easeOut(duration: 0.2)) {
                                                        shelfOverlap = target
                                                    }
                                                }
                                            }
                                    }
                                )
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
            // ▶️ Hero 横幅"立即播放":直接拉起播放器
            .fullScreenCover(item: $bannerToPlay) { item in
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
            idx + 1 < args.count
        else { return nil }
        return Int(args[idx + 1])
    }

    /// 从 season_id 构造一个极简 FeedItem（仅需 seasonId，详情页会自行拉取完整数据）
    private static func makeDebugFeedItem(seasonID: Int) -> FeedItem? {
        let json = "{\"season_id\": \(seasonID)}"
        return try? JSONDecoder().decode(FeedItem.self, from: Data(json.utf8))
    }
    #endif
}

// MARK: - Hero Focus

/// 每个 hero 页内可聚焦操作的唯一焦点标识:页索引 + 按钮类型。
/// 轮播页程序性切换时,可据此把焦点精确恢复到"同一按钮、新页面"。
enum HeroFocus: Hashable {
    case play(Int)
    case detail(Int)
    case bookmark(Int)
    case next(Int)

    /// 页索引
    var page: Int {
        switch self {
        case .play(let page), .detail(let page), .bookmark(let page), .next(let page):
            return page
        }
    }

    /// 保持当前按钮类型、切换到指定页(用于自动轮播/手动翻页后的焦点同步)
    func onPage(_ page: Int) -> HeroFocus {
        switch self {
        case .play: return .play(page)
        case .detail: return .detail(page)
        case .bookmark: return .bookmark(page)
        case .next: return .next(page)
        }
    }
}

// MARK: - Hero Carousel View
struct HeroCarouselView: View {
    let items: [FeedItem]
    @Binding var selectedIndex: Int
    @Binding var selectedMovie: FeedItem?
    @Binding var bannerToPlay: FeedItem?
    /// 指示条随 shelf 重叠量同步上移(负值=上移)
    var indicatorOffset: CGFloat = 0
    /// 记录焦点当前落在哪个 hero 页的哪个操作(nil = 焦点已移出 hero,如停在 shelf 上)
    @FocusState private var focusedItem: HeroFocus?

    var body: some View {
        TabView(selection: $selectedIndex) {
            ForEach(Array(items.enumerated()), id: \.element) { index, item in
                HeroBannerView(
                    item: item,
                    pageIndex: index,
                    pageFocus: $focusedItem,
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
        .defaultFocus($focusedItem, .play(0), priority: .automatic)
        .onAppear {
            // 兜底:defaultFocus 在部分 tvOS 版本/场景下不生效,显式聚焦首屏 Play 按钮。
            // 延迟一拍等 TabView 页面与按钮完成布局,再写入焦点。
            if focusedItem == nil {
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    if focusedItem == nil {
                        focusedItem = .play(0)
                    }
                }
            }
        }
        .onChange(of: selectedIndex) { _, newValue in
            // tvOS 的 .page TabView 由焦点引擎驱动翻页:自动轮播是程序性改 selection,
            // 焦点不会跟随,导致首次方向键只被焦点引擎"吃掉"去对齐当前页。
            // 仅当 hero 仍持有焦点时,把焦点精确恢复到"同操作、新页面";
            // 若用户已下移到 shelf(focusedItem == nil),绝不抢焦点。
            if focusedItem != nil {
                focusedItem = focusedItem?.onPage(newValue)
            }
        }
        .overlay(alignment: .bottom) {
            PageIndicatorView(count: items.count, selectedIndex: $selectedIndex)
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

// MARK: - Hero Circle Icon Button
/// 圆形毛玻璃图标按钮的通用外观(类似 CSS class):50pt 圆形 .glass 按钮 + 40pt 图标。
/// 详情 / 收藏 / 下一页三颗按钮共用;播放按钮因需胶囊展开动画,单独实现。
private struct HeroCircleIconButton: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: 40, weight: .regular))
            .frame(width: 50, height: 50)
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
    }
}

// MARK: - Hero Banner View
struct HeroBannerView: View {
    let item: FeedItem
    /// 当前页索引,用于将页内按钮焦点同步回轮播页级焦点
    let pageIndex: Int
    @FocusState.Binding var pageFocus: HeroFocus?
    let onPlay: () -> Void
    let onDetail: () -> Void
    let onNext: () -> Void
    @State private var isBookmarked = false
    /// Play 按钮展开状态(独立 @State,由 pageFocus 变化用显式 withAnimation 驱动;
    /// 不直接派生自 @FocusState,否则焦点引擎在"失去焦点"时禁用隐式动画,收起方向不带动画)
    @State private var isPlayExpanded = false

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
                .padding(.trailing, 300)  // Keep the right side of the screen clean
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

                // Action buttons: 播放 / 详情 / 收藏 / 下一页
                // 统一 50pt 圆形毛玻璃按钮 + 40pt 图标(Apple TV+ 紧凑风格);
                // 播放按钮聚焦(active)时宽度弹簧展开为药丸形,文字淡入,图标位置保持不动。
                HStack(spacing: 24) {
                    Button(action: onPlay) {
                        HStack(spacing: isPlayExpanded ? 12 : 0) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 40, weight: .regular))
                                .foregroundStyle(.white)
                            if isPlayExpanded {
                                Text("立即播放")
                                    .font(.system(size: 29, weight: .semibold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .padding(.leading, isPlayExpanded ? 14 : 0)
                        .frame(width: isPlayExpanded ? 184 : 50, height: 50)
                    }
                    .buttonStyle(.glass)
                    // 关键:始终 .capsule。宽=高=50 时 CapsuleShape 即完美圆形,
                    // 宽度展开时由 frame 动画驱动,从圆形连续渐变到药丸(形状本身不可动画,
                    // 不要用 buttonBorderShape(isPlayActive ? .capsule : .circle) 条件切换)。
                    .buttonBorderShape(.capsule)
                    .focused($pageFocus, equals: .play(pageIndex))
                    .zIndex(isPlayExpanded ? 1 : 0)
                    .onAppear {
                        // 初始同步:默认焦点已在 Play 时,onChange 不会触发,需按当前焦点设置展开态
                        isPlayExpanded = (pageFocus == .play(pageIndex))
                    }
                    .onChange(of: pageFocus) { _, newValue in
                        // 显式动画驱动展开/收起:不依赖 @FocusState 的隐式动画 transaction,
                        // 保证"获得焦点展开"与"失去焦点收起"都有动画。
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                            isPlayExpanded = (newValue == .play(pageIndex))
                        }
                    }

                    Button(action: onDetail) {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.white)
                    }
                    .modifier(HeroCircleIconButton())
                    .focused($pageFocus, equals: .detail(pageIndex))

                    Button(action: { isBookmarked.toggle() }) {
                        Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                            .foregroundStyle(isBookmarked ? .yellow : .white)
                    }
                    .modifier(HeroCircleIconButton())
                    .focused($pageFocus, equals: .bookmark(pageIndex))

                    Button(action: onNext) {
                        Image(systemName: "forward.end")
                            .foregroundStyle(.white)
                    }
                    .modifier(HeroCircleIconButton())
                    .focused($pageFocus, equals: .next(pageIndex))
                }
                .padding(.top, 8)
            }
            .padding(.horizontal, 90)
            .padding(.bottom, 280)  // Push content well above the overlapping shelf
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
