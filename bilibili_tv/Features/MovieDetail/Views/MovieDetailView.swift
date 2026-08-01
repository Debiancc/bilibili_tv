import SwiftUI
import Kingfisher

struct MovieDetailView: View {
    @State private var viewModel: MovieDetailViewModel
    
    @State private var isBookmarked = false
    @State private var isPlaying = false
    @FocusState private var isPlayFocused: Bool
    
    @State private var scrollY: CGFloat = 0
    
    @State private var selectedEpisode: PGCEpisode? = nil
    
    init(item: FeedItem) {
        _viewModel = State(initialValue: MovieDetailViewModel(feedItem: item))
    }
    
    var body: some View {
        ZStack(alignment: .top) {
            // 🎬 1. 基础深色背景
            Color.black.ignoresSafeArea()
            
            // 2. 全屏高清海报 (Hero Background)
            GeometryReader { proxy in
                KFImage(viewModel.coverURL)
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
            
            // 3. Apple TV 风格双向渐变蒙版 (底部变暗 + 左侧变暗)
            // 底部蒙版
            LinearGradient(
                colors: [Color.clear, Color.black.opacity(0.7), Color.black.opacity(0.95)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            // 左侧蒙版
            LinearGradient(
                colors: [Color.black.opacity(0.8), Color.black.opacity(0.3), Color.clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .ignoresSafeArea()
            
            // 📺 4. 详情主体滚动布局
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 40) {
                    
                    // --- 顶部 Hero 区域 ---
                    VStack(alignment: .leading, spacing: 20) {
                        
                        // 用 GeometryReader 追踪滚动位移
                        GeometryReader { geo in
                            Color.clear
                                .onChange(of: geo.frame(in: .global).minY) { _, newValue in
                                    scrollY = newValue - 200 // 补偿初始安全区偏移
                                }
                        }
                        .frame(height: 0)
                        
                        // 预留高度，把文字推到屏幕左下侧
                        Spacer()
                            .frame(height: 480)
                        
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
                                .foregroundColor(.white)
                                .lineLimit(2)
                                .shadow(color: .black.opacity(0.5), radius: 10, x: 0, y: 5)
                        }
                        
                        // 2. 动态元数据 (标签)
                        HStack(spacing: 12) {
                            if let rating = viewModel.ratingText {
                                HStack(spacing: 2) {
                                    Text(rating).font(.title3).fontWeight(.bold).foregroundColor(.green)
                                    Text("分").font(.caption).foregroundColor(.white.opacity(0.8))
                                }
                            }
                            
                            if viewModel.feedItem.isDRMProtected {
                                BadgeLabel(title: "DRM", color: .purple)
                            }
                            
                            if let payment = viewModel.seasonDetail?.payment?.vipPromotion, !payment.isEmpty {
                                BadgeLabel(title: payment, color: .pink)
                            }
                            
                            if let styles = viewModel.stylesText {
                                Text(styles)
                                    .font(.subheadline)
                                    .foregroundColor(.white.opacity(0.8))
                            }
                            
                            if let year = viewModel.seasonDetail?.publish?.pubTimeShow {
                                Text(year)
                                    .font(.subheadline)
                                    .foregroundColor(.white.opacity(0.8))
                            }
                        }
                        
                        // 3. 剧情简介 (简短)
                        if let desc = viewModel.description {
                            Text(desc)
                                .font(.title3)
                                .foregroundColor(.white.opacity(0.9))
                                .lineSpacing(8)
                                .lineLimit(4)
                                .frame(maxWidth: 900, alignment: .leading)
                        }
                        
                        // 4. 交互按钮
                        HStack(spacing: 30) {
                            Button(action: {
                                print("▶️ [MovieDetailView] 播放: \(viewModel.title)")
                                // 默认播放第一集或上次观看的集数
                                selectedEpisode = viewModel.episodes.first
                                isPlaying = true
                            }) {
                                HStack(spacing: 12) {
                                    Image(systemName: "play.fill")
                                        .font(.title2)
                                    Text("立即播放")
                                        .font(.headline)
                                }
                                .padding(.horizontal, 32)
                                .padding(.vertical, 14)
                            }
                            .buttonStyle(.card)
                            .focused($isPlayFocused)
                            
                            Button(action: {
                                isBookmarked.toggle()
                            }) {
                                HStack(spacing: 10) {
                                    Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                                        .foregroundColor(isBookmarked ? .yellow : .white)
                                    Text(isBookmarked ? "已追剧" : "追剧")
                                }
                                .padding(.horizontal, 24)
                                .padding(.vertical, 14)
                            }
                            .buttonStyle(.card)
                        }
                        .padding(.top, 10)
                    }
                    .padding(.leading, 90)
                    .padding(.bottom, 40)
                    
                    // --- 底部内容区域 (需向下滚动) ---
                    
                    // 选集列表
                    if !viewModel.episodes.isEmpty {
                        VStack(alignment: .leading, spacing: 20) {
                            Text("选集")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .padding(.leading, 90)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 30) {
                                    ForEach(viewModel.episodes) { ep in
                                        EpisodeCardView(episode: ep, selectedEpisode: $selectedEpisode)
                                    }
                                }
                                .padding(.horizontal, 90)
                                .padding(.vertical, 20)
                            }
                        }
                    }
                    
                    // 演职人员
                    if let actors = viewModel.seasonDetail?.actors {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("演职人员")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                            
                            Text(actors)
                                .font(.body)
                                .foregroundColor(.white.opacity(0.7))
                        }
                        .padding(.leading, 90)
                        .padding(.top, 20)
                    }
                    
                    Spacer().frame(height: 100)
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
            // 目前依然复用 BiliPlayerContainerView，可后续迭代为真实的视频播放器
            BiliPlayerContainerView(item: viewModel.feedItem)
        }
        .onChange(of: selectedEpisode) { _, newEp in
            if newEp != nil {
                isPlaying = true
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
            .foregroundColor(color)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(color.opacity(0.5), lineWidth: 1)
            )
            .cornerRadius(6)
    }
}

#Preview {
    MovieDetailView(item: FeedItem(
        title: "夏洛特烦恼", subtitle: "马冬梅的排列组合", cover: "https://i0.hdslb.com/bfs/bangumi/image/4276bcae64678156b596c4bba2e98876ed74e65d.png@3840w_2160h_1e.webp", rating: "9.5", badge: "DRM", link: "", episodeId: 320665, seasonId: 33354, stat: FeedStat(view: 34320099, danmaku: 0), rank: 1, indexShow: nil, rankTag: nil, brief: "昔日校花秋雅（王智 饰）的婚礼正在隆重举行，学生时代暗恋秋雅的男主角夏洛（沈腾 饰）看着周围事业成功的老同学，心中泛起酸味，借着七分醉意大闹婚礼现场，甚至惹得妻子马冬梅（马丽 饰）现场发飙，而他发泄过后却在马桶上睡着了。梦里他重回校园，追求到他心爱的女孩、让失望的母亲重展笑颜、甚至成为无所不能的流行乐坛巨星……\n醉生梦死中，他发现身边人都在利用自己，只有马冬梅是最值得珍惜的……", overlayImg: nil, logo: nil, ogvFusionInfo: nil, newEp: nil, desc: "DESC..........."
    ))
}
