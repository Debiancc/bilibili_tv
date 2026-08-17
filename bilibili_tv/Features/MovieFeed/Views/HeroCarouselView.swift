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
/// 从机制上消除回弹路径;程序性翻页(timer/下一页按钮)后显式重锚焦点到
/// "同按钮类型、新页面"——此时无 TabView 过渡在飞行,写 FocusState 不会与引擎冲突。
struct HeroCarouselView: View {
    let items: [FeedItem]
    @Binding var selectedIndex: Int?
    /// 指示条随 shelf 重叠量同步上移(负值=上移)
    var indicatorOffset: CGFloat = 0
    /// 播放回调:携带被按页的 item(焦点页 == 当前页,selectedIndex 也可推导,
    /// 但播放是高频主操作,直接给 item 免去宿主再查一次数组)
    let onPlay: (FeedItem) -> Void
    /// 详情回调:只通知"当前页的详情被按下",item 由宿主经 items[selectedIndex] 推导
    let onDetail: () -> Void
    /// 记录焦点当前落在哪个 hero 页的哪个操作(nil = 焦点已移出 hero,如停在 shelf 上)
    @FocusState private var focusedButton: HeroButtonFocus?

    var body: some View {
        Group {
            if isSnapshotTestingMode {
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
            }
        }
    }

    /// 仅 DEBUG 构建且测试前置调用了 prepareForSnapshotTesting() 时为 true
    private var isSnapshotTestingMode: Bool {
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
                        onPlay: { onPlay(item) },
                        onDetail: onDetail,
                        onNext: {
                            // 程序性翻页:焦点先行,由引擎滚动揭示目标页
                            rotateProgrammatically()
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
                onAutoRotate: { rotateProgrammatically() }
            )
            .padding(.bottom, 20)
            .offset(y: indicatorOffset)
            .animation(.easeOut(duration: 0.2), value: indicatorOffset)
        }
    }

    /// 程序性翻页(timer/下一页按钮)。
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
        } else {
            withAnimation {
                selectedIndex = next
            }
        }
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
            guard count > 1 else { return }
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
