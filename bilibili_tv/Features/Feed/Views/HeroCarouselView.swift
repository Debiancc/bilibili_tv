import Combine
import SwiftUI

// MARK: - Hero Focus

/// 每个 hero 页内可聚焦操作的唯一焦点标识:页索引 + 按钮类型。
/// 轮播页程序性切换时,可据此把焦点精确恢复到"同一按钮、新页面"。
enum HeroButtonFocus: Hashable {
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
    func onPage(_ page: Int) -> HeroButtonFocus {
        switch self {
        case .play: return .play(page)
        case .detail: return .detail(page)
        case .bookmark: return .bookmark(page)
        case .next: return .next(page)
        }
    }
}

// MARK: - Hero Carousel View

/// 轮播主体:横向 ScrollView + 全宽分页,替代 TabView(.page)。
///
/// 为什么不用 TabView(.page):
/// TabView 翻页会销毁/重建页面视图,焦点引擎必须在跨页过渡中"恢复"焦点;
/// 滚动停止后的焦点归还(按元素身份)会把它拉回旧页,导致"弹回当前页"。
/// 本实现所有页面视图常驻层级(非 Lazy),焦点引擎只在存活的元素间移动焦点,
/// 从机制上消除回弹路径;程序性翻页(定时器自动轮播)后显式重锚焦点到
/// "同按钮类型、新页面"——此时无 TabView 过渡在飞行,写 FocusState 不会与引擎冲突。
struct HeroCarouselView: View {
    let items: [FeedItem]
    @Binding var selectedIndex: Int?
    /// 指示条随 shelf 重叠量同步上移(负值=上移)
    var indicatorOffset: CGFloat = 0
    /// 本 Tab 是否为当前选中 Tab:false 时所有页视频不激活。
    /// 显式门控替代对 TabView 切换 onDisappear 的依赖(TabView 切换时非活动
    /// Tab 的视图节点保留、onDisappear 不可靠),否则电影/番剧双 Tab 的视频
    /// 会同时解码播放(双音频输出)
    var isTabSelected: Bool = true
    /// 是否有路由/覆盖盖在 **本 Tab** 的 feed 之上(详情页/播放 cover/账号页/调试控制台):
    /// 覆盖期间轮播背景视频暂停、自动轮播停走。经 PlaybackCoordinator.isFeedCovered(for:)
    /// 从根视图按 owner Tab 域内化后透传(切 Tab 不清旧 Tab 的 activeDetail,
    /// 非本 Tab 的详情不得误冻本 Tab 轮播)
    var isFeedCovered: Bool = false
    /// 详情回调:只通知"当前页的详情被按下",item 由宿主经 items[selectedIndex] 推导
    let onDetail: () -> Void
    /// 记录焦点当前落在哪个 hero 页的哪个操作(nil = 焦点已移出 hero,如停在 shelf 上)
    @FocusState private var focusedButton: HeroButtonFocus?

    /// 当前活动页(焦点所在页优先,无焦点时取选中页)
    private var activePageIndex: Int {
        focusedButton?.page ?? selectedIndex ?? 0
    }

    /// 焦点是否位于轮播区域内(hero 页按钮或回绕锚点):
    /// 焦点移出轮播(shelf 卡片等)时背景视频暂停,移回后由 setActive(true)
    /// 从断点续播。纯函数版本见 isFocusWithin(buttonFocus:wrapAnchorFocused:)。
    var isFocusWithinCarousel: Bool {
        Self.isFocusWithin(buttonFocus: focusedButton, wrapAnchorFocused: isWrapAnchorFocused)
    }

    /// 焦点局部性判定(纯函数,便于脱离焦点引擎单测):
    /// ⚠️ 必须并入回绕锚点:末页按钮→锚点交接瞬间 button 焦点已变 nil 而锚点
    /// 尚未落定(isWrapAnchorEnabled 注释记录的交接期),漏掉会造成背景视频
    /// 一次无谓的 pause→resume 顿挫。
    static func isFocusWithin(buttonFocus: HeroButtonFocus?, wrapAnchorFocused: Bool) -> Bool {
        buttonFocus != nil || wrapAnchorFocused
    }

    /// 背景视频驱动状态:当前页已失败(取流/播放异常)的页集合,失败页回退固定计时器
    @State private var videoFailedPages: Set<Int> = []
    /// 当前页视频播放进度(0..1,驱动模式下指示条进度=视频进度)
    @State private var activeVideoProgress: CGFloat = 0
    /// 「→ 回绕承接锚点」焦点状态(锚点本体见 wrapAnchor)
    @FocusState private var isWrapAnchorFocused: Bool
    /// 程序性翻页的重锚确认任务(见 verifyRotationReanchor)
    @State private var reanchorVerifyTask: Task<Void, Never>?
    /// 使已排队的重锚任务失效,防止跨越 Tab/覆盖层/数据刷新生命周期写回旧焦点
    @State private var reanchorGeneration = 0

    /// 当前页是否应由背景视频驱动自动轮播:
    /// 统一语义(忽略 API times 字段):有 play_focus 且未失败的页均由视频驱动
    /// (播完 → 3s fallback → 翻页);失败页回退固定计时器。
    /// 快照测试或 UITest (-uitestMockFeed) 模式下禁用视频驱动，回退为确定性的计时器轮播。
    /// ⚠️ 区间完整性必须与 BannerVideoController.load 的守卫一致(两端齐全且 end > start):
    /// 残缺区间(仅一端)若被当作驱动,指示条计时器停走且控制器无视频时钟可供给,
    /// 该页将永不自动翻页且无恢复路径。
    private var isActivePageVideoDriven: Bool {
        #if DEBUG
        if ContentView.isSnapshotTesting || ProcessInfo.processInfo.arguments.contains("-uitestMockFeed") {
            return false
        }
        #endif
        guard items.indices.contains(activePageIndex),
            let playFocus = items[activePageIndex].playFocus,
            playFocus.durationSeconds != nil,
            !videoFailedPages.contains(activePageIndex)
        else { return false }
        return true
    }

    var body: some View {
        Group {
            if isFocusSideEffectsDisabled {
                // 快照渲染:关闭焦点锚点与兜底写入,保证确定性的"无焦点"渲染
                core
            } else {
                core
                    // tvOS 焦点锚点:首次进入页面时默认聚焦第一页 Play 按钮。
                    // 原来 Play 用 .glassProminent 时天然是页面首选焦点;改回 .glass 圆钮后失去该锚点,
                    // 页面级方向键会直接掉到 shelf。显式声明默认焦点以恢复"方向键先进按钮组"。
                    .defaultFocus($focusedButton, .play(0), priority: .automatic)
                    .onAppear {
                        // 兜底:defaultFocus 在部分 tvOS 版本/场景下不生效,显式聚焦首屏 Play 按钮。
                        // 延迟一拍等布局完成,再写入焦点。
                        if focusedButton == nil {
                            Task { @MainActor in
                                try? await Task.sleep(nanoseconds: 200_000_000)
                                if focusedButton == nil {
                                    focusedButton = .play(0)
                                }
                            }
                        }
                    }
                    .onChange(of: focusedButton) { oldValue, newValue in
                        reanchorBackNavigation(from: oldValue, to: newValue)
                    }
            }
        }
        // 频道切换/数据刷新整体替换 items 时,清空按索引记忆的失败标记与进度:
        // 索引在下一页素材中会复用,旧频道的失败标记不能污染新频道的视频驱动
        .onChange(of: items) { _, _ in
            cancelRotationReanchor()
            videoFailedPages = []
            activeVideoProgress = 0
        }
        .onChange(of: isTabSelected) { _, _ in
            cancelRotationReanchor()
        }
        .onChange(of: isFeedCovered) { _, _ in
            cancelRotationReanchor()
        }
        .onDisappear {
            cancelRotationReanchor()
        }
    }

    /// 快照渲染（DEBUG 构建）时为 true：快照需要确定性"无焦点"渲染
    private var isFocusSideEffectsDisabled: Bool {
        #if DEBUG
        ContentView.isSnapshotTesting
        #else
        false
        #endif
    }

    private var core: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                // 身份用页索引,与 pageIndex/.id(index)/scrollPosition 一致:
                // 用 FeedItem 作身份时,相等条目会产生重复子身份,
                // SwiftUI 更新时可能复用错误的页面状态并把焦点挪到错误页
                ForEach(items.indices, id: \.self) { index in
                    let item = items[index]
                    HeroBannerView(
                        item: item,
                        pageIndex: index,
                        buttonFocus: $focusedButton,
                        onDetail: onDetail,
                        onNext: {
                            // 程序性翻页:焦点先行,由引擎滚动揭示目标页
                            rotateProgrammatically()
                        },
                        // 覆盖门控在此单点生效(isFeedCovered 已按 owner Tab 域内化,
                        // 经 ContentView 透传):视频 + 指示条/轮播共用同一门控源
                        isVideoActive: isTabSelected
                            && !isFeedCovered
                            && isFocusWithinCarousel
                            && index == activePageIndex,
                        onVideoReady: {
                            // 视频就绪:该页保持驱动(无额外动作,指示条进度开始走视频时钟)
                        },
                        onVideoProgress: { progress in
                            if index == activePageIndex {
                                activeVideoProgress = progress
                            }
                        },
                        onVideoFinished: {
                            guard index == activePageIndex else { return }
                            activeVideoProgress = 0
                            rotateProgrammatically()
                        },
                        onVideoFailed: {
                            videoFailedPages.insert(index)
                            activeVideoProgress = 0
                        }
                    )
                    .id(index)
                    .frame(width: 1_920, height: 1_080)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        // 聚焦缩放允许溢出滚动视图边界(与 shelf 卡片一致)
        .scrollClipDisabled()
        // 显式钉死高度:tvOS 画布固定 1920×1080,ScrollView 在宿主安全区/尺寸提议
        // 变化时(如快照测试窗口)会自我膨胀导致页面超高、底部按钮被裁出可视区。
        .frame(height: 1_080)
        // 选中页与滚动位置双向绑定:用户方向键翻页由引擎滚动并更新选中页;
        // 程序性翻页走 rotateProgrammatically(),selectedIndex 在焦点位于 hero 时
        // 不直接写(scrollPosition 对程序性写入不滚动,反而回填旧值,详见其注释)
        .scrollPosition(id: $selectedIndex)
        .overlay(alignment: .bottom) {
            PageIndicatorView(
                count: items.count,
                selectedIndex: $selectedIndex,
                onAutoRotate: { rotateProgrammatically() },
                // UITest 可用 -uitestRotationInterval=N 缩短自动轮播间隔
                // （仅 testAutoRotateKeepsNewPage 传入）；release 下恒为 nil → 默认 8s
                rotationInterval: ContentView.uitestRotationInterval ?? 8,
                useVideoProgress: isActivePageVideoDriven,
                videoProgressValue: activeVideoProgress,
                isEnabled: isTabSelected && !isFeedCovered
            )
            .padding(.bottom, 20)
            .offset(y: indicatorOffset)
            .animation(.easeOut(duration: 0.2), value: indicatorOffset)
        }
        .overlay(alignment: .bottomTrailing) {
            wrapAnchor
        }
    }

    // MARK: - Wrap-around Anchor

    /// 回绕承接锚点尺寸:透明面板,垂直带与 HeroBannerView 操作按钮行对齐
    private static let wrapAnchorWidth: CGFloat = 60
    private static let wrapAnchorHeight: CGFloat = 140
    /// 锚点底缘:按钮中心 ≈ 页底 280 + 按钮高/2 + 少量上垫 → 距底约 309
    private static let wrapAnchorBottom: CGFloat = 239

    /// 右缘「→ 回绕承接锚点」:焦点在末页按钮组时按 →,引擎自然落到本不可见面板
    /// (按钮组右方唯一候选),获焦后重锚到页 0 Play ——「焦点先行、引擎滚动揭示目标页」,
    /// 与 rotateProgrammatically 同机制。
    ///
    /// 为什么不用 onMoveCommand:该 hook 不消费按键,与焦点引擎对同一次 → 的自行处理
    /// 双写竞态,破坏回退导航(0918af4 引入、1af423b 回退的历史回归)。锚点由引擎
    /// 独立完成落点,应用只在焦点落定后重锚,无竞态;复用 FeedContentScrollView
    /// 「↑ 承接锚点」已验证的模式。
    ///
    /// 焦点不在末页按钮组时锚点不注册焦点:中间页按 → 仍正常跨页翻页,shelf 方向
    /// 检索不受吸引。「下一部」按钮(真正的最右元素)恢复时需同步调整注册条件。
    private var wrapAnchor: some View {
        Color.clear
            .frame(width: Self.wrapAnchorWidth, height: Self.wrapAnchorHeight)
            .padding(.bottom, Self.wrapAnchorBottom)
            .focusable(isWrapAnchorEnabled)
            .focused($isWrapAnchorFocused)
            .onChange(of: isWrapAnchorFocused) { _, focused in
                guard focused, items.count > 1 else { return }
                focusedButton = .play(0)
            }
            .accessibilityHidden(true)
    }

    /// 锚点是否注册焦点:多页 + 本 Tab 可见 + (焦点正落在末页按钮组 或 焦点已落上
    /// 锚点的交接期);快照渲染禁用。交接期保留注册的原因:焦点从末页按钮移上锚点
    /// 瞬间 focusedButton 已变 nil、play(0) 重锚尚未写入,若此刻撤销锚点的焦点资格,
    /// 引擎会在交接中途把焦点重定向、回绕被掐断(PR #46 review 2026-09)。
    private var isWrapAnchorEnabled: Bool {
        guard !isFocusSideEffectsDisabled, isTabSelected, items.count > 1 else { return false }
        return focusedButton?.page == items.count - 1 || isWrapAnchorFocused
    }

    /// 程序性翻页(定时器自动轮播)。
    /// 焦点在 hero 时只写焦点到"同按钮类型、新页面":焦点引擎会滚动 ScrollView
    /// 揭示新聚焦的按钮,selectedIndex 由 scrollPosition 回填 —— 禁止此时直接写
    /// selectedIndex:焦点牵制下 scrollPosition 不滚动并立刻回填旧值,还会与
    /// 焦点重锚互相放大成 0⇄1 乒乓(自动轮播失效,已实测)。
    /// 焦点不在 hero(如停在 shelf)时无焦点牵制,直接写 selectedIndex 驱动滚动。
    private func rotateProgrammatically() {
        guard !items.isEmpty else { return }
        let current = focusedButton?.page ?? selectedIndex ?? 0
        let next = (current + 1) % items.count
        if let focused = focusedButton {
            focusedButton = focused.onPage(next)
            verifyRotationReanchor(from: focused, targetPage: next)
        } else {
            cancelRotationReanchor()
            withAnimation {
                selectedIndex = next
            }
        }
    }

    /// 程序性轮播重锚的重试判定(纯函数,可在焦点引擎外单测):
    /// 引擎回吐写入的签名 = 焦点原封不动停在「翻页前的那一个按钮」。
    /// nil(焦点已移出轮播)或已落到其他元素(用户已操作)均不重试。
    static func shouldReissueRotationFocus(current: HeroButtonFocus?, source: HeroButtonFocus) -> Bool {
        current == source
    }

    /// 取消当前重锚确认并使其代际失效。
    private func cancelRotationReanchor() {
        reanchorVerifyTask?.cancel()
        reanchorVerifyTask = nil
        reanchorGeneration += 1
    }

    /// 程序性翻页的重锚确认与有限重试(issue #57)。
    /// 焦点引擎可能在 ScrollView 滚动/重锚过渡中丢弃 FocusState 写入,使焦点
    /// 停在翻页前的按钮。写入后延迟一拍核对,只在仍命中原按钮的回吐签名时重写;
    /// 用户焦点、Tab/覆盖层或数据上下文发生变化时,任务会被取消且代际失效。
    private func verifyRotationReanchor(from source: HeroButtonFocus, targetPage: Int) {
        cancelRotationReanchor()
        let generation = reanchorGeneration
        reanchorVerifyTask = Task { @MainActor in
            for _ in 0..<3 {
                do {
                    try await Task.sleep(nanoseconds: 500_000_000)
                } catch {
                    return
                }
                guard !Task.isCancelled,
                    generation == reanchorGeneration,
                    items.indices.contains(source.page),
                    items.indices.contains(targetPage),
                    Self.shouldReissueRotationFocus(current: focusedButton, source: source)
                else { return }
                focusedButton = source.onPage(targetPage)
            }
        }
    }

    /// 按 ← 跨页返回上一页时,焦点引擎按几何最近原则落在上一页最右侧按钮,
    /// 与按 → 翻到下一页时自然落在 Play 按钮的体验不对称;
    /// 这里检测"从右侧页的 Play 跨页落点"并把焦点重锚到该页的 Play 按钮。
    /// 重锚写入会再触发一次 onChange,但彼时 oldValue 非 .play,守卫直接放行,不会循环。
    private func reanchorBackNavigation(from oldValue: HeroButtonFocus?, to newValue: HeroButtonFocus?) {
        guard case .play(let fromPage)? = oldValue,
            let landed = newValue,
            landed.page == fromPage - 1
        else { return }
        if case .play = landed { return }
        focusedButton = .play(landed.page)
    }
}

// MARK: - Page Indicator View (active 展开为带倒计时进度的线段)

/// 当前页指示器:active 时展开成一条线段并在内部填充倒计时进度(填满即自动翻页),
/// deactive 时收回为圆点。任何 selection 变化(定时翻页或用户手动方向键翻页)都会重置进度。
struct PageIndicatorView: View {
    let count: Int
    @Binding var selectedIndex: Int?
    /// 自动轮播触发回调:在进度走满时调用,翻页动作(焦点先行)由宿主执行
    var onAutoRotate: () -> Void = {}
    /// 自动轮播间隔(秒),默认 8s
    var rotationInterval: TimeInterval = 8
    /// active 线段完全展开后的宽度
    var expandedWidth: CGFloat = 24
    /// 圆点直径(也是线段高度)
    var dotSize: CGFloat = 8
    /// 视频驱动模式:true 时固定计时器停止,进度由 videoProgressValue 驱动(播完即翻页)
    var useVideoProgress: Bool = false
    /// 视频区间进度(0..1),仅 useVideoProgress 时生效
    var videoProgressValue: CGFloat = 0
    /// 是否启用自动轮播:非选中 Tab 或被覆盖(详情页/播放 cover/账号页)时传 false。
    /// 非选中 Tab 的视图节点被 TabView 保留,fallback 定时器若不停止,其 onAutoRotate
    /// 会经 rotateProgrammatically 写共享的 FeedViewModel.currentBannerIndex,
    /// 导致可见 Tab 的轮播被不可见 Tab 翻页;覆盖期间停走避免「盖在下面的轮播自己翻页」。
    /// 焦点移出轮播不经此门控:视频驱动模式下指示条进度完全交由视频时钟,
    /// 焦点离开→视频 pause→时钟停走→指示条冻结(轮播「等待」用户回来,
    /// 产品决策见 issue #52),此时 useVideoProgress 恒 true、fallback 定时器
    /// 提前 return 不推进——冻结是预期行为,不是缺陷。
    var isEnabled: Bool = true

    @State private var progress: CGFloat = 0
    private let ticker = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    private var currentIndex: Int { selectedIndex ?? 0 }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<max(count, 1), id: \.self) { index in
                indicator(for: index)
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selectedIndex)
            }
        }
        .onReceive(ticker) { _ in
            // UI 测试确定性模式: 暂停自动轮播，避免 8s 翻页打断测试中的焦点序列
            if ContentView.isUITestRotationDisabled { return }
            // 非选中 Tab:停止 fallback 定时器,防止改共享 currentBannerIndex
            guard isEnabled, count > 1 else { return }
            // 视频驱动模式:倒计时交给视频时钟,固定计时器不推进
            if useVideoProgress { return }
            let step = CGFloat(0.1 / rotationInterval)
            let newValue = progress + step
            if newValue >= 1 {
                // 翻页动作交给宿主(焦点先行),此处只负责计时与进度
                onAutoRotate()
                progress = 0
            } else {
                progress = newValue
            }
        }
        .onChange(of: currentIndex) { _, _ in
            // 只在"有效页码"变化时重置进度:scrollPosition(Binding<Int?>) 会自发
            // 发出 nil/回填抖动,若直接观察可选值,抖动会把 progress 无限清零,
            // 自动轮播永远凑不满一个周期(进度线冻结)
            progress = 0
        }
        .onChange(of: useVideoProgress) { _, isVideo in
            if isVideo {
                progress = videoProgressValue
            }
        }
        .onChange(of: videoProgressValue) { _, value in
            if useVideoProgress {
                progress = min(max(value, 0), 1)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func indicator(for index: Int) -> some View {
        let isActive = index == currentIndex
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
