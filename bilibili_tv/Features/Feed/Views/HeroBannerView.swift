import Kingfisher
import SwiftUI

// MARK: - Hero Circle Icon Label

/// 圆形毛玻璃图标按钮的内部 Label 布局:50pt 居中槽位 + 40pt 图标。
/// 作用在 Button 内部 Label 上,使 .glass 样式自适应底板内边距,与播放按钮高度保持一致。
private struct HeroCircleIconLabel: ViewModifier {
    let color: Color

    func body(content: Content) -> some View {
        content
            .font(.system(size: 40, weight: .regular))
            .foregroundStyle(color)
            .frame(width: 50, height: 50)
    }
}

// MARK: - Hero Banner View

struct HeroBannerView: View {
    let item: FeedItem
    /// 当前页索引,用于将页内按钮焦点同步回轮播页级焦点
    let pageIndex: Int
    @FocusState.Binding var buttonFocus: HeroButtonFocus?
    let onDetail: () -> Void
    let onNext: () -> Void
    /// 背景视频是否激活(由宿主合成:活动页 + 本 Tab 选中 + 焦点在轮播内;
    /// 覆盖类门控由 BannerVideoBackgroundView 经 coordinator 自行订阅)
    var isVideoActive: Bool = false
    /// 背景视频事件(驱动轮播:ready=停止固定计时器、progress=指示条进度、finished=翻页、failed=回退计时器)
    var onVideoReady: () -> Void = {}
    var onVideoProgress: (CGFloat) -> Void = { _ in }
    var onVideoFinished: () -> Void = {}
    var onVideoFailed: () -> Void = {}
    /// 播放意图经环境直达根视图协调器,不再经轮播/滚动容器转发
    @Environment(\.playbackCoordinator) private var playbackCoordinator
    @State private var isBookmarked = false
    /// Play 按钮展开状态(独立 @State,由 buttonFocus 变化用显式 withAnimation 驱动;
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
            backgroundLayer
            contentStack
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 全出血背景:封面图 + 底部/左侧渐变,保证可读性并与下方 shelf 融合;
    /// 有 play_focus 时叠加背景视频(活动页播放,无则保持纯图片)
    private var backgroundLayer: some View {
        ZStack {
            KFImage(item.secureOverlayURL ?? item.highResCoverURL ?? item.secureCoverURL)
                .placeholder {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .fade(duration: 0.25)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()

            // 🎬 背景视频层(预告片):封面之上、渐变之下;无 play_focus 时渲染空视图
            BannerVideoBackgroundView(
                playFocus: item.playFocus,
                isActive: isVideoActive,
                onReady: onVideoReady,
                onProgress: onVideoProgress,
                onFinished: onVideoFinished,
                onFailed: onVideoFailed
            )

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
        }
    }

    /// 前景内容:logo/标题 + 分类信息 + 简介 + 操作按钮
    private var contentStack: some View {
        VStack(alignment: .leading, spacing: 10) {
            titleSection
            actionButtons
        }
        .padding(.horizontal, 90)
        .padding(.bottom, 280)  // Push content well above the overlapping shelf
    }

    /// 标题区:优先展示台标,失败/缺失时回退文字标题,随后是分类信息与简介
    private var titleSection: some View {
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
                    .scaledToFit()
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
        }
    }

    /// 操作按钮行:播放(聚焦时胶囊展开) / 详情 / 收藏
    /// (「下一部」按钮暂时停用,恢复时取消注释并同步恢复 HeroButtonFocus.next 的使用)
    private var actionButtons: some View {
        HStack(spacing: 24) {
            Button(action: { playbackCoordinator.play(.banner(item)) }) {
                HStack {
                    Image(systemName: "play.fill")
                        .font(.system(size: 40, weight: .regular))
                        .foregroundStyle(.white)
                    // 文字必须用条件插入真正移出布局:常驻 + opacity(0) 的隐藏文字
                    // 仍会参与 .glass 胶囊的内在尺寸计算,把收起态撑成宽>高的椭圆。
                    // fixedSize 防展开动画中被压缩截断
                    if isPlayExpanded {
                        Text("立即播放")
                            .font(.system(size: 29, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
                // 尺寸必须加在 label 上:tvOS 26 .glass 胶囊按 label 内容自适应,
                // 外层 .frame 只占位不塑形。不用 alignment/.clipped:
                // 玻璃层不遵守 label 内的裁切,反而产生渲染几何错乱
                .frame(width: isPlayExpanded ? 184 : 50, height: 50)
            }
            .accessibilityLabel("立即播放")
            .buttonStyle(.glass)
            // 关键:始终 .capsule。宽=高=50 时 CapsuleShape 即完美圆形,
            // 宽度展开时由 frame 动画驱动,从圆形连续渐变到药丸(形状本身不可动画,
            // 不要用 buttonBorderShape(isPlayActive ? .capsule : .circle) 条件切换)。
            .buttonBorderShape(.capsule)
            .focused($buttonFocus, equals: .play(pageIndex))
            .onAppear {
                // 初始同步:默认焦点已在 Play 时,onChange 不会触发,需按当前焦点设置展开态
                isPlayExpanded = (buttonFocus == .play(pageIndex))
            }
            .onChange(of: buttonFocus) { _, newValue in
                // 显式动画驱动展开/收起:不依赖 @FocusState 的隐式动画 transaction,
                // 保证"获得焦点展开"与"失去焦点收起"都有动画。
                withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                    isPlayExpanded = (newValue == .play(pageIndex))
                }
            }

            Button(action: onDetail) {
                Image(systemName: "info.circle")
                    .modifier(HeroCircleIconLabel(color: .white))
            }
            .accessibilityLabel("详情")
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .focused($buttonFocus, equals: .detail(pageIndex))

            Button(action: { isBookmarked.toggle() }) {
                Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                    .modifier(HeroCircleIconLabel(color: isBookmarked ? .yellow : .white))
            }
            .accessibilityLabel(isBookmarked ? "取消收藏" : "收藏")
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .focused($buttonFocus, equals: .bookmark(pageIndex))

            // 「下一部」按钮暂时停用(产品决策):注释而非删除,便于恢复。
            // Button(action: onNext) {
            //     Image(systemName: "forward.end")
            //         .modifier(HeroCircleIconLabel(color: .white))
            // }
            // .accessibilityLabel("下一部")
            // .buttonStyle(.glass)
            // .buttonBorderShape(.circle)
            // .focused($buttonFocus, equals: .next(pageIndex))
        }
        .padding(.top, 8)
    }
}

// MARK: - Preview

#Preview("HeroBannerView") {
    struct PreviewContainer: View {
        @FocusState private var focus: HeroButtonFocus?
        var body: some View {
            HeroBannerView(
                item: FeedItem(
                    title: "昭阳公主",
                    subtitle: "寒门状元X冷宫公主",
                    cover: "https://i0.hdslb.com/bfs/bangumi/image/fda56a06b6e9eccafa3687fee7ed347ba31af726.png",
                    rating: nil,
                    badge: nil,
                    link: nil,
                    episodeId: nil,
                    seasonId: 157_324,
                    stat: nil,
                    rank: 1,
                    indexShow: nil,
                    rankTag: nil,
                    brief: nil,
                    overlayImg: "https://i0.hdslb.com/bfs/tvcover/24ca16ceb8f1ce747714b38a0f44ece5a20b6ddf.jpg",
                    logo: "https://i0.hdslb.com/bfs/tvcover/c8457c92cff69dbb5982399d36eaef498e57ecbd.png",
                    ogvFusionInfo: .init(category: "电视剧", tag: "情感 古装"),
                    newEp: .init(indexShow: "全18集"),
                    desc: """
                        《昭阳公主》由上海宽娱数码科技有限公司出品。改编自晋江文学城小说《平阳公主》，原著：青帷。
                        寒门沈孝一心苦读只为入朝为官，查清父亲死因，却因意外与昭阳公主李述一夜春风后又被其弃之。
                        不久后他高中状元，新考鹿鸣宴沈孝面圣，第一道奏疏就是弹劾这位“骄奢淫逸”的公主......两人从相杀到相惜，
                        相互欣赏生出情愫。从对立到联手，沈孝助公主挣脱枷锁，两人在并肩对抗的路上，意识到这阶级之争背后的症结：
                        只有国泰民安才能有个人命运的安好。
                        """
                ),
                pageIndex: 0,
                buttonFocus: $focus,
                onDetail: {},
                onNext: {}
            )
            .frame(width: 1_920, height: 1_080)
        }
    }
    return PreviewContainer()
}
