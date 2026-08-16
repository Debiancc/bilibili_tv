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
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element) { index, item in
                    HeroBannerView(
                        item: item,
                        pageIndex: index,
                        buttonFocus: $focusedButton,
                        onPlay: { onPlay(item) },
                        onDetail: onDetail,
                        onNext: {
                            // 程序性翻页:只写选中页,焦点重锚由 onChange(of: selectedIndex) 统一处理
                            withAnimation {
                                selectedIndex = ((selectedIndex ?? 0) + 1) % items.count
                            }
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
        // 选中页与滚动位置双向绑定:用户方向键翻页由引擎滚动并更新选中页,
        // 程序性翻页(timer/下一页)写选中页驱动滚动。
        .scrollPosition(id: $selectedIndex)
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
        .onChange(of: selectedIndex) { _, newValue in
            // 页切换后把焦点重锚到"同按钮类型、新页面"。
            // 用户方向键驱动时焦点已在新页,写入同值无副作用;
            // 程序性翻页(timer/下一页按钮)时旧页按钮仍存活但已移出屏幕,
            // 必须重锚,否则下一次方向键会从屏外元素继续移动(反向滚动)。
            // 所有页面常驻层级,此处的写入不会与引擎的跨页过渡冲突。
            if focusedButton != nil, let newValue {
                focusedButton = focusedButton?.onPage(newValue)
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
    @Binding var selectedIndex: Int?
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
                // 写选中页触发滚动,焦点重锚由 HeroCarouselView.onChange 统一处理
                withAnimation {
                    selectedIndex = (currentIndex + 1) % count
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
