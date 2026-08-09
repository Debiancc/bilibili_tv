import Kingfisher
import SwiftUI

struct MovieDetailView: View {
    @State private var viewModel: MovieDetailViewModel

    @State private var isBookmarked = false
    @State private var isPlaying = false
    @FocusState private var isPlayFocused: Bool
    @FocusState private var isBookmarkFocused: Bool

    @State private var scrollY: CGFloat = 0
    @State private var isDescriptionExpanded: Bool = false

    @State private var selectedEpisode: PGCEpisode?

    init(item: FeedItem) {
        _viewModel = State(initialValue: MovieDetailViewModel(feedItem: item))
    }

    var body: some View {
        ZStack(alignment: .top) {
            // 背景层 (深色底 + 全屏海报 + 双向渐变蒙版)
            MovieDetailBackdrop(coverURL: viewModel.coverURL, scrollY: scrollY)

            // 📺 详情主体滚动布局
            ScrollView(.vertical, showsIndicators: false) {
                ScrollViewReader { scrollProxy in
                    VStack(alignment: .leading, spacing: 40) {
                        Color.clear.frame(height: 1).id("topOfPage")

                        // --- 顶部 Hero 区域 ---
                        MovieDetailHeroSection(
                            viewModel: viewModel,
                            isDescriptionExpanded: $isDescriptionExpanded,
                            isPlayFocused: $isPlayFocused,
                            isBookmarkFocused: $isBookmarkFocused,
                            isBookmarked: $isBookmarked,
                            scrollY: $scrollY,
                            onPlay: {
                                print("▶️ [MovieDetailView] 播放: \(viewModel.title)")
                                selectedEpisode = viewModel.episodes.first
                                isPlaying = true
                            },
                            onBookmarkToggle: {
                                isBookmarked.toggle()
                            },
                            scrollToTop: {
                                withAnimation(.easeOut(duration: 0.3)) { scrollProxy.scrollTo("topOfPage", anchor: .top) }
                            }
                        )
                        .padding(.leading, 90)
                        .padding(.bottom, 40)

                        // --- 底部内容区域 (需向下滚动) ---

                        // 选集列表
                        if !viewModel.episodes.isEmpty {
                            VStack(alignment: .leading, spacing: 20) {
                                Text("选集")
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                    .padding(.leading, 90)

                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 30) {
                                        ForEach(viewModel.episodes) { ep in
                                            EpisodeCardView(episode: ep) {
                                                selectedEpisode = ep
                                                isPlaying = true
                                            }
                                        }
                                    }
                                    .padding(.horizontal, 90)
                                    .padding(.vertical, 20)
                                }
                            }
                        }

                        // 演职人员
                        /*
                        if let actors = viewModel.seasonDetail?.actors {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("演职人员")
                                    .font(.headline)
                                    .foregroundStyle(.white)

                                Text(actors)
                                    .font(.body)
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                            .padding(.leading, 90)
                            .padding(.top, 20)
                            .focusable(true)
                        }
                        */

                        Spacer().frame(height: 100)
                    }
                }
            }
        }
        .task {
            await viewModel.fetchDetail()
        }
        .onAppear {
            isPlayFocused = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isPlayFocused = true
            }
        }
        .fullScreenCover(isPresented: $isPlaying) {
            let epToPlay = selectedEpisode?.epId ?? selectedEpisode?.id ?? viewModel.feedItem.episodeId
            let title = viewModel.seasonDetail?.seasonTitle ?? viewModel.seasonDetail?.title ?? viewModel.feedItem.title
            let subtitle = selectedEpisode?.formattedTitle ?? viewModel.feedItem.subtitle
            let coverString = selectedEpisode?.cover ?? viewModel.seasonDetail?.cover ?? viewModel.feedItem.cover
            let normalizedCoverString: String? = {
                guard var urlString = coverString else { return nil }
                if urlString.hasPrefix("//") {
                    urlString = "https:" + urlString
                } else if urlString.hasPrefix("http://") {
                    urlString = "https://" + urlString.dropFirst(7)
                }
                if urlString.hasSuffix(".webp") {
                    urlString = urlString.replacingOccurrences(of: ".webp", with: ".jpg")
                }
                return urlString
            }()
            let coverURL = normalizedCoverString.flatMap { URL(string: $0) }
            BiliPlayerContainerView(
                epId: epToPlay,
                seasonId: viewModel.feedItem.seasonId,
                title: title,
                subtitle: subtitle,
                coverURL: coverURL
            )
        }
    }
}

// MARK: - 背景层 (深色底 + 全屏海报 + 双向渐变蒙版)

private struct MovieDetailBackdrop: View {
    let coverURL: URL?
    let scrollY: CGFloat

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

            // 全屏高清海报 (Hero Background)
            GeometryReader { proxy in
                KFImage(coverURL)
                    .placeholder { Color.black }
                    .fade(duration: 0.5)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
                    // 向下滚动时，背景逐渐变暗，确保底部内容的可读性
                    .overlay(
                        Color.black.opacity(min(Double(max(0, -scrollY) / 600.0), 0.85))
                    )
            }
            .ignoresSafeArea()

            // Apple TV 风格双向渐变蒙版 (底部变暗 + 左侧变暗)
            LinearGradient(
                colors: [Color.clear, Color.black.opacity(0.7), Color.black.opacity(0.95)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            LinearGradient(
                colors: [Color.black.opacity(0.8), Color.black.opacity(0.3), Color.clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .ignoresSafeArea()
        }
    }
}

// MARK: - 顶部 Hero 区域

private struct MovieDetailHeroSection: View {
    let viewModel: MovieDetailViewModel
    @Binding var isDescriptionExpanded: Bool
    @FocusState.Binding var isPlayFocused: Bool
    @FocusState.Binding var isBookmarkFocused: Bool
    @Binding var isBookmarked: Bool
    @Binding var scrollY: CGFloat
    let onPlay: () -> Void
    let onBookmarkToggle: () -> Void
    let scrollToTop: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // 用 GeometryReader 追踪滚动位移
            GeometryReader { geo in
                Color.clear
                    .onChange(of: geo.frame(in: .global).minY) { _, newValue in
                        scrollY = newValue - 200  // 补偿初始安全区偏移
                    }
            }
            .frame(height: 0)

            // 预留高度，把文字推到屏幕左下侧
            Spacer()
                .frame(height: 100)
                .id("topSpacer")

            // 1. Logo 或 标题
            if let logoUrl = viewModel.feedItem.secureLogoURL {
                KFImage(logoUrl)
                    .setProcessor(LogoTrimmingProcessor())
                    .fade(duration: 0.3)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 500, maxHeight: 200, alignment: .bottomLeading)
            } else {
                Text(viewModel.title)
                    .font(.system(size: 64, weight: .heavy))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .shadow(color: .black.opacity(0.5), radius: 10, x: 0, y: 5)
            }

            // 2. 动态元数据 (标签)
            HStack(spacing: 12) {
                if let typeName = viewModel.typeNameText, !typeName.isEmpty {
                    BadgeLabel(title: typeName, color: .white)
                }

                if let rating = viewModel.ratingText {
                    HStack(spacing: 2) {
                        Text(rating).font(.caption)
                        Text("分").font(.caption).foregroundStyle(.white.opacity(0.8))
                    }
                }

                if let styles = viewModel.stylesText {
                    Text(styles)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                }

                if let year = viewModel.pubYear {
                    Text(year)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                }
            }

            // 3. 剧情简介 (简短/展开)
            if let desc = viewModel.description {
                Button(action: {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        isDescriptionExpanded.toggle()
                    }
                }) {
                    Text(desc)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.9))
                        .lineSpacing(8)
                        .lineLimit(isDescriptionExpanded ? nil : 4)
                        .frame(maxWidth: 900, minHeight: 56, alignment: .leading)
                        .multilineTextAlignment(.leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityValue(isDescriptionExpanded ? "已展开" : "已折叠")
                .accessibilityHint("激活可展开或折叠剧情简介")
            }

            // 4. 交互按钮
            HStack(spacing: 30) {
                Button(action: onPlay) {
                    HStack(spacing: 12) {
                        Image(systemName: "play.fill")
                            .font(.title2)
                        Text("立即播放")
                            .font(.headline)
                    }
                    .padding(.horizontal, 32)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.glassProminent)
                .focused($isPlayFocused)

                Button(action: onBookmarkToggle) {
                    HStack(spacing: 10) {
                        Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                            .foregroundStyle(isBookmarked ? .yellow : .white)
                        Text(isBookmarked ? "已追剧" : "追剧")
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.glass)
                .focused($isBookmarkFocused)
            }
            .padding(.top, 10)
            .onChange(of: isPlayFocused) { _, isFocused in
                if isFocused { scrollToTop() }
            }
            .onChange(of: isBookmarkFocused) { _, isFocused in
                if isFocused { scrollToTop() }
            }
        }
    }
}

// 徽章组件 (复用)
struct BadgeLabel: View {
    let title: String
    let color: Color

    var body: some View {
        Text(title)
            .font(.caption)
            .fontWeight(.semibold)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.25))
            .foregroundStyle(color)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(color.opacity(0.5), lineWidth: 1)
            )
            .cornerRadius(6)
    }
}

#Preview {
    MovieDetailView(
        item: FeedItem(
            // swiftlint:disable line_length
            title: "夏洛特烦恼", subtitle: "马冬梅的排列组合",
            cover: "https://i0.hdslb.com/bfs/bangumi/image/4276bcae64678156b596c4bba2e98876ed74e65d.png@3840w_2160h_1e.webp", rating: "9.5", badge: "DRM",
            link: "", episodeId: 320_665, seasonId: 33_354, stat: FeedStat(view: 34_320_099, danmaku: 0), rank: 1, indexShow: nil, rankTag: nil,
            brief:
                "昔日校花秋雅（王智 饰）的婚礼正在隆重举行，学生时代暗恋秋雅的男主角夏洛（沈腾 饰）看着周围事业成功的老同学，心中泛起酸味，借着七分醉意大闹婚礼现场，甚至惹得妻子马冬梅（马丽 饰）现场发飙，而他发泄过后却在马桶上睡着了。梦里他重回校园，追求到他心爱的女孩、让失望的母亲重展笑颜、甚至成为无所不能的流行乐坛巨星……\n醉生梦死中，他发现身边人都在利用自己，只有马冬梅是最值得珍惜的……",
            overlayImg: nil, logo: nil, ogvFusionInfo: nil, newEp: nil, desc: "DESC..........."
                // swiftlint:enable line_length
        ))
}
