import SwiftUI

/// 频道侧边栏：对齐 Apple TV+ 实测设计——
/// 悬浮面板（非贴边）：左/上/下均留 ~32pt，四角全圆角(~40pt)，宽 ~420pt，
/// 深墨青灰毛玻璃（强模糊+暗化），active 条目 = 白色圆角矩形 + 深色 Semibold 文字。
/// 无折叠态入口：由宿主经 revealRequest（feed 顶部 ↑）唤起展开。
struct ChannelSidebarView: View {
    let channels: [FeedChannel]
    /// 唯一事实源：条目按钮直接写绑定，切换副作用由宿主（ContentView）经 onChange 派生。
    @Binding var selectedChannel: FeedChannel
    /// 内容就绪闸门:主内容区存在可聚焦元素时才允许"聚焦即展开"。
    /// 冷启动加载中(loading 且无数据)主区只有 FeedLoadingView(无焦点项),
    /// 此时唤起展开会在 feed 就绪后 hero 抢回焦点时闪一下又收起。
    var isInteractionReady: Bool = true
    /// 外部唤起请求(feed 顶部按 ↑ 时宿主递增):展开面板并聚焦当前频道条目
    var revealRequest: Int = 0
    /// 搜索入口点击回调(宿主 push SearchView)
    var onSearchTap: () -> Void = {}

    /// 侧边栏内当前聚焦的频道（nil = 焦点已移出侧边栏）
    @FocusState private var focusedChannel: FeedChannel?
    /// 搜索入口是否聚焦（焦点落在搜索按钮时 focusedChannel 为 nil,
    /// 若不单独跟踪会被"焦点移出 → 收起"逻辑误判为离开侧边栏）
    @FocusState private var isSearchFocused: Bool

    @State private var isExpanded: Bool = false

    // MARK: - Apple TV+ 实测对齐参数
    private let sidebarWidth: CGFloat = 420
    private let cornerRadius: CGFloat = 40

    var body: some View {
        // ZStack 撑满父视图,面板内容用 inset 定位,保证悬浮间距不受 overlay 对齐影响
        ZStack(alignment: .topLeading) {
            if isExpanded {
                expandedSidebar
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: isExpanded)
        .onAppear {
            #if DEBUG
            // -uitestFocusSidebar: 初始展开并聚焦当前频道条目,替代原「入口独占初始焦点」语义
            if ContentView.isUITestSidebarFocusMode, isInteractionReady {
                isExpanded = true
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    focusedChannel = selectedChannel
                }
            }
            #endif
        }
        .onChange(of: isInteractionReady) { _, isReady in
            #if DEBUG
            // 冷启动时闸门可能初始为 false(loading 且无数据),就绪后需补一次展开,
            // 否则 -uitestFocusSidebar 展开逻辑只走了 onAppear 一次、错过就绪时机。
            guard isReady, ContentView.isUITestSidebarFocusMode else { return }
            isExpanded = true
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 250_000_000)
                focusedChannel = selectedChannel
            }
            #endif
        }
        .onChange(of: revealRequest) { _, _ in
            // 宿主 ↑ 唤起:展开面板并聚焦当前频道条目(闸门防止冷启动加载中闪开)
            guard isInteractionReady else { return }
            isExpanded = true
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 250_000_000)
                focusedChannel = selectedChannel
            }
        }
        .onChange(of: focusedChannel) { _, newValue in
            // 焦点从条目移出(回主内容) → 收起;移入条目时保持展开。
            // ⚠️ 焦点移到搜索按钮时 focusedChannel 也会变 nil,此时不收起
            if newValue == nil && !isSearchFocused {
                isExpanded = false
            }
        }
        .onChange(of: isSearchFocused) { _, newValue in
            // 焦点进入搜索按钮保持展开;从搜索按钮移出且未回到条目时收起
            if !newValue && focusedChannel == nil {
                isExpanded = false
            }
        }
    }

    /// 搜索入口:右上角 icon 按钮,点击经宿主回调跳转 SearchView
    private var searchButton: some View {
        Button {
            onSearchTap()
            // 立即收起并交还焦点,避免面板残留遮住搜索页
            isExpanded = false
            focusedChannel = nil
        } label: {
            Circle()
                .fill(isSearchFocused ? Color.white : .clear)
                .frame(width: 56, height: 56)
                .overlay(
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(isSearchFocused ? Color.black.opacity(0.9) : Color.white.opacity(0.82))
                )
        }
        .buttonStyle(SidebarChannelButtonStyle())
        .focusEffectDisabled()
        .focused($isSearchFocused)
        .accessibilityLabel("搜索")
    }

    /// 展开态:悬浮面板（四周留白、四角圆角）
    private var expandedSidebar: some View {
        VStack(alignment: .leading, spacing: 5) {
            // 搜索入口:右上角 icon 形式,不占频道列表行
            HStack {
                Spacer(minLength: 0)
                searchButton
            }
            .padding(.bottom, 12)
            .padding(.trailing, 8)

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

#Preview {
    ChannelSidebarView(
        channels: FeedChannel.allCases,
        selectedChannel: .constant(.movie)
    )
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.black)
}
