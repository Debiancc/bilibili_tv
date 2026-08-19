import SwiftUI

/// 频道侧边栏：对齐 Apple TV+ 实测设计——
/// 悬浮面板（非贴边）：左/上/下均留 ~65-70pt，四角全圆角(~40pt)，宽 ~420pt，
/// 深墨青灰毛玻璃（强模糊+暗化），active 条目 = 白色圆角矩形 + 深色 Semibold 文字。
/// 折叠时仅左上角保留一个当前频道图标入口；入口获得焦点后展开完整列表。
struct ChannelSidebarView: View {
    let channels: [FeedChannel]
    /// 唯一事实源：条目按钮直接写绑定，切换副作用由宿主（ContentView）经 onChange 派生。
    @Binding var selectedChannel: FeedChannel
    /// 内容就绪闸门:主内容区存在可聚焦元素时才允许"聚焦即展开"。
    /// 冷启动加载中(loading 且无数据)主区只有 FeedLoadingView(无焦点项),
    /// 入口按钮独占初始焦点,若允许展开会在 feed 就绪后 hero 抢回焦点时闪一下又收起。
    var isInteractionReady: Bool = true
    /// 外部唤起请求(feed 顶部按 ↑ 时宿主递增):聚焦入口按钮,
    /// 走现有"聚焦即展开"链路,与遥控器直接聚焦入口的行为完全一致。
    var revealRequest: Int = 0

    /// 侧边栏内当前聚焦的频道（nil = 焦点已移出侧边栏）
    @FocusState private var focusedChannel: FeedChannel?
    /// 折叠态左上角入口按钮是否聚焦
    @FocusState private var isEntryFocused: Bool

    @State private var isExpanded: Bool = false

    // MARK: - Apple TV+ 实测对齐参数
    private let sidebarWidth: CGFloat = 420
    private let horizontalInset: CGFloat = 70
    private let verticalInset: CGFloat = 70
    private let cornerRadius: CGFloat = 40

    var body: some View {
        // ZStack 撑满父视图,面板内容用 inset 定位,保证悬浮间距不受 overlay 对齐影响
        ZStack(alignment: .topLeading) {
            entryButton
                .opacity(isExpanded ? 0 : 1)
                .allowsHitTesting(!isExpanded)

            if isExpanded {
                expandedSidebar
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: isExpanded)
        .onChange(of: isEntryFocused) { _, newValue in
            #if DEBUG
            let focusedDesc = focusedChannel.map(String.init(describing:)) ?? "nil"
            UITestDiagnostics.log("ChannelSidebar isEntryFocused -> \(newValue) (ready=\(isInteractionReady) focusedChannel=\(focusedDesc))")
            #endif
            // 入口聚焦 → 展开,并把焦点移交到当前频道条目。
            // ⚠️ 内容未就绪时不展开:冷启动时入口是屏上唯一可聚焦元素,
            // 焦点引擎会把初始焦点交给它,立即展开会在 feed 就绪后 hero
            // 抢回焦点时造成"侧边栏闪一下又消失"。
            if newValue && isInteractionReady {
                isExpanded = true
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    focusedChannel = selectedChannel
                }
            } else if focusedChannel == nil {
                isExpanded = false
            }
        }
        .onChange(of: focusedChannel) { _, newValue in
            // 焦点从条目移出(回主内容) → 收起;移入条目时保持展开
            if newValue == nil && !isEntryFocused {
                isExpanded = false
            }
        }
        .onChange(of: revealRequest) { _, _ in
            // 宿主 ↑ 唤起:聚焦入口即展开(依赖 isInteractionReady 闸门,
            // 冷启动加载中不展开,与遥控器直触入口的语义一致)
            if isInteractionReady {
                isEntryFocused = true
            }
        }
    }

    /// 折叠态入口:左上角当前频道图标按钮
    @ViewBuilder
    private var entryButton: some View {
        if ContentView.isUITestSidebarFocusMode {
            // -uitestFocusSidebar: 锚定入口为默认焦点,保证冷启动确定性落在入口
            // (仅测试模式;生产模式保持系统默认焦点语义,不额外锚定)
            entryButtonBody
                .defaultFocus($isEntryFocused, true, priority: .automatic)
                .onAppear {
                    // 兜底:defaultFocus 在部分 tvOS 版本/场景下不生效(与 hero 同坑),
                    // 延迟一拍显式聚焦入口,触发"聚焦即展开"
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 250_000_000)
                        isEntryFocused = true
                    }
                }
        } else if ContentView.isUITestHeroFocusMode {
            // -uitestFocusHeroPlay: 禁用入口聚焦能力,让 hero Play 成为唯一初始焦点
            // （消除冷启动「入口 vs hero」竞态，详见 ContentView.isUITestHeroFocusMode）
            entryButtonBody
                .focusable(false)
        } else {
            entryButtonBody
        }
    }

    private var entryButtonBody: some View {
        Button {
            #if DEBUG
            UITestDiagnostics.log("ChannelSidebar entry tapped (wasExpanded=\(isExpanded))")
            #endif
            isExpanded = true
            // 入口即透明:立即把焦点移交给当前频道条目,避免面板展开后焦点悬空
            // (与 isEntryFocused onChange 的移交路径一致,覆盖 Select 直触入口的场景)
            Task { @MainActor in
                await Task.yield()
                focusedChannel = selectedChannel
            }
        } label: {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.regularMaterial)
                .frame(width: 64, height: 64)
                .overlay(
                    Image(systemName: selectedChannel.iconName)
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.white)
                )
        }
        .buttonStyle(SidebarChannelButtonStyle())
        .focusEffectDisabled()
        .focused($isEntryFocused)
        .padding(.leading, horizontalInset)
        .padding(.top, verticalInset)
        .accessibilityLabel("频道")
    }

    /// 展开态:悬浮面板（四周留白、四角圆角）
    private var expandedSidebar: some View {
        VStack(alignment: .leading, spacing: 5) {
            ChannelSidebarHeader()
                .padding(.bottom, 30)
                .padding(.leading, 16)

            ForEach(channels) { channel in
                channelButton(channel)
            }

            Spacer(minLength: 0)
        }
        .padding(.top, 24)
        .padding(.horizontal, 14)
        .frame(width: sidebarWidth, alignment: .leading)
        .background(
            // 对齐 Apple TV+:深墨青灰毛玻璃(regularMaterial 强模糊 + 青墨 tint 暗化)
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.regularMaterial)
        )
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color(red: 0.04, green: 0.13, blue: 0.15).opacity(0.45))
        )
        .clipShape(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
        .padding(.leading, horizontalInset)
        .padding(.vertical, verticalInset)
    }

    /// 单个频道条目:active = 白色圆角矩形 + 深色 Semibold 文字(对齐 Apple TV+)
    private func channelButton(_ channel: FeedChannel) -> some View {
        let isFocused = focusedChannel == channel
        // 选中态与聚焦态分离:isSelected 语义 = 当前实际频道,而非临时聚焦
        let isSelected = selectedChannel == channel
        return Button {
            // 切换只写绑定,副作用(频道加载/回写一致性)由宿主 onChange 派生
            selectedChannel = channel
            // 选中后焦点交还主内容,侧边栏自动收起
            focusedChannel = nil
        } label: {
            HStack(spacing: 16) {
                Image(systemName: channel.iconName)
                    .font(.system(size: 28, weight: .medium))
                    .frame(width: 32)
                Text(channel.title)
                    .font(.body)
                    .fontWeight(isFocused ? .semibold : .medium)
                    .lineLimit(1)
            }
            .foregroundStyle(isFocused ? Color.black.opacity(0.9) : Color.white.opacity(0.82))
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isFocused ? Color.white : .clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(SidebarChannelButtonStyle())
        // ⚠️ 系统默认按钮样式(tvOS)聚焦时会渲染灰白全宽高亮层,与自定义白色
        // active 圆角矩形叠加成双层效果;必须用自定义 ButtonStyle 彻底移除
        .focusEffectDisabled()
        .focused($focusedChannel, equals: channel)
        .accessibilityLabel(channel.title)
        // 选中语义跟随 selectedChannel,不能跟随焦点(focus 可以落在未选中频道上)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// 完全自定义的按钮样式:不做任何系统装饰(无系统聚焦高亮层)。
/// tvOS 上 `.plain` 聚焦时仍会渲染系统灰白高亮,需自定义 style 才能彻底移除,
/// 聚焦视觉完全由 @FocusState 驱动的自定义白色圆角矩形负责。
private struct SidebarChannelButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

/// 侧边栏顶部区域:品牌标识行(对应 Apple TV+ 的用户头像+名称区)
private struct ChannelSidebarHeader: View {
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.pink.opacity(0.9), Color.blue.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "play.tv.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 40, height: 40)

            Text("BiliTV")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("BiliTV")
    }
}

#Preview {
    ChannelSidebarView(
        channels: FeedChannel.allCases,
        selectedChannel: .constant(.movie)
    )
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.black)
}
