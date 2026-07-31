import SwiftUI
import Kingfisher

struct MovieDetailView: View {
    let item: FeedItem
    @State private var isBookmarked = false
    @State private var isPlaying = false
    @FocusState private var isPlayFocused: Bool
    
    var body: some View {
        ZStack {
            // 🎬 1. 基础深色背景
            Color.black.ignoresSafeArea()
            
            // 背景高斯模糊封面
            GeometryReader { proxy in
                KFImage(item.highResCoverURL)
                    .placeholder { Color.black }
                    .fade(duration: 0.25)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .blur(radius: 80)
                    .opacity(0.3)
                    .clipped()
            }
            .ignoresSafeArea()
            
            // 暗色渐变罩层
            LinearGradient(
                colors: [
                    Color.black.opacity(0.85),
                    Color.black.opacity(0.6),
                    Color.black.opacity(0.95)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            // 📺 2. 详情主体布局
            ScrollView(.vertical, showsIndicators: true) {
                HStack(alignment: .top, spacing: 60) {
                    // 左侧大尺寸海报
                    ZStack(alignment: .topTrailing) {
                        KFImage(item.highResCoverURL)
                            .placeholder {
                                Rectangle()
                                    .fill(Color.gray.opacity(0.3))
                            }
                            .fade(duration: 0.25)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                        .frame(width: 360, height: 540)
                        .clipped()
                        .cornerRadius(20)
                        .shadow(color: .black.opacity(0.8), radius: 20, x: 0, y: 10)
                        
                        // 高分 Badge
                        if let rating = item.rating, !rating.isEmpty {
                            VStack(spacing: 2) {
                                Text(rating)
                                    .font(.system(size: 26, weight: .bold))
                                    .foregroundColor(.white)
                                Text("分")
                                    .font(.caption2)
                                    .foregroundColor(.white.opacity(0.8))
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 14)
                            .background(
                                LinearGradient(colors: [.orange, .pink], startPoint: .topLeading, endPoint: .bottomTrailing)
                            )
                            .cornerRadius(12)
                            .padding(16)
                            .shadow(radius: 8)
                        }
                    }
                    
                    // 右侧内容区
                    VStack(alignment: .leading, spacing: 24) {
                        // 标签栏
                        HStack(spacing: 12) {
                            if item.isDRMProtected || item.badge != nil {
                                BadgeLabel(title: item.badge ?? "DRM 保护片源", color: .purple)
                            }
                            BadgeLabel(title: "大会员专享", color: .pink)
                            BadgeLabel(title: "4K 超清", color: .blue)
                            
                            if let views = item.formattedViewCount {
                                HStack(spacing: 4) {
                                    Image(systemName: "play.fill")
                                        .font(.caption)
                                    Text("\(views)播放")
                                        .font(.subheadline)
                                }
                                .foregroundColor(.white.opacity(0.7))
                                .padding(.leading, 8)
                            }
                        }
                        
                        // 电影标题
                        Text(item.title ?? "未知电影")
                            .font(.system(size: 52, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(2)
                        
                        // 看点 / 描述
                        if let subtitle = item.subtitle, !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.title3)
                                .foregroundColor(.pink)
                                .fontWeight(.semibold)
                        }
                        
                        Rectangle()
                            .fill(Color.white.opacity(0.2))
                            .frame(height: 1)
                        
                        // 交互控制按钮区 (绑定 @FocusState 自动捕获 tvOS 焦点)
                        HStack(spacing: 30) {
                            // 播放按钮
                            Button(action: {
                                print("▶️ [MovieDetailView] 播放电影: \(item.title ?? "")")
                                isPlaying = true
                            }) {
                                HStack(spacing: 12) {
                                    Image(systemName: "play.fill")
                                        .font(.title2)
                                    Text("立即播放")
                                        .font(.headline)
                                }
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                            }
                            .buttonStyle(.card)
                            .focused($isPlayFocused)
                            
                            // 追剧 / 收藏按钮
                            Button(action: {
                                isBookmarked.toggle()
                            }) {
                                HStack(spacing: 10) {
                                    Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                                        .foregroundColor(isBookmarked ? .yellow : .white)
                                    Text(isBookmarked ? "已追剧" : "追剧 / 收藏")
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                            }
                            .buttonStyle(.card)
                        }
                        .padding(.top, 10)
                        
                        // 剧情简介
                        VStack(alignment: .leading, spacing: 12) {
                            Text("简介")
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                            
                            Text("\(item.title ?? "") 是 Bilibili 电影频道精选高清影视资源。支持 4K 极清画质与杜比全景声音效，畅享电视大屏沉浸式观影体验。")
                                .font(.body)
                                .foregroundColor(.white.opacity(0.85))
                                .lineSpacing(6)
                        }
                        .padding(.top, 10)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 80)
                .padding(.top, 40)
                .padding(.bottom, 60)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            print("🎬 [MovieDetailView] Entered detail page for: \(item.title ?? "")")
            isPlayFocused = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isPlayFocused = true
            }
        }
        .fullScreenCover(isPresented: $isPlaying) {
            BiliPlayerContainerView(item: item)
        }
    }
}

// 徽章组件
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
        title: "夏洛特烦恼", subtitle: "马冬梅的排列组合", cover: "https://i0.hdslb.com/bfs/bangumi/image/4276bcae64678156b596c4bba2e98876ed74e65d.png@3840w_2160h_1e.webp", rating: "9.5", badge: "DRM", link: "", episodeId: 320665, seasonId: 33354, stat: FeedStat(view: 34320099, danmaku: 0), rank: 1, indexShow: nil, rankTag: nil, brief: "昔日校花秋雅（王智 饰）的婚礼正在隆重举行，学生时代暗恋秋雅的男主角夏洛（沈腾 饰）看着周围事业成功的老同学，心中泛起酸味，借着七分醉意大闹婚礼现场，甚至惹得妻子马冬梅（马丽 饰）现场发飙，而他发泄过后却在马桶上睡着了。梦里他重回校园，追求到他心爱的女孩、让失望的母亲重展笑颜、甚至成为无所不能的流行乐坛巨星……\n醉生梦死中，他发现身边人都在利用自己，只有马冬梅是最值得珍惜的……", overlayImg: nil, logo: nil, ogvFusionInfo: nil
    ))
}
