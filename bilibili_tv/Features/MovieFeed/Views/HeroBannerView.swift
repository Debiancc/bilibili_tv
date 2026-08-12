import Kingfisher
import SwiftUI

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
            backgroundLayer
            contentStack
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 全出血背景:封面图 + 底部/左侧渐变,保证可读性并与下方 shelf 融合
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
        }
    }

    /// 操作按钮行:播放(聚焦时胶囊展开) / 详情 / 收藏 / 下一页
    private var actionButtons: some View {
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
}
