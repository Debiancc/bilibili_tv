import SwiftUI
import SwiftData

struct ContentView: View {
    // 🌟 特性 1：配合 @Observable 使用极简 @State 绑定
    @State private var viewModel: FeedViewModel
    @State private var selectedMovie: FeedItem?
    @State private var isShowingPulseConsole: Bool = false
    
    @MainActor
    init(viewModel: FeedViewModel? = nil) {
        _viewModel = State(initialValue: viewModel ?? FeedViewModel())
    }
    
    let columns = [
        GridItem(.flexible(), spacing: 40),
        GridItem(.flexible(), spacing: 40),
        GridItem(.flexible(), spacing: 40),
        GridItem(.flexible(), spacing: 40)
    ]
    
    var body: some View {
        NavigationStack {
            ScrollView {
                if viewModel.isLoading && viewModel.items.isEmpty {
                    ProgressView("加载中...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = viewModel.errorMessage {
                    VStack(spacing: 20) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 80))
                            .foregroundColor(.orange)
                        Text("出错了")
                            .font(.headline)
                        Text(error)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Button("重试") {
                            Task {
                                await viewModel.fetchInitialFeed()
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 100)
                } else if viewModel.items.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "film")
                            .font(.system(size: 80))
                            .foregroundColor(.secondary)
                        Text("暂无电影资源")
                            .font(.headline)
                        Text("请稍后再试，或检查您的网络连接。")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Button("刷新") {
                            Task {
                                await viewModel.fetchInitialFeed()
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 100)
                } else {
                    LazyVGrid(columns: columns, spacing: 60) {
                        ForEach(viewModel.items) { item in
                            Button(action: {
                                print("🎬 [ContentView] Selected movie: \(item.title ?? "")")
                                selectedMovie = item
                            }) {
                                MovieCardView(item: item)
                            }
                            .buttonStyle(.card)
                            .onAppear {
                                if item.id == viewModel.items.last?.id {
                                    Task {
                                        await viewModel.fetchNextPage()
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 60)
                    .padding(.top, 20)
                    .padding(.bottom, 60)
                }
            }
            .navigationTitle("电影热播")
//            .toolbar {
//                ToolbarItem(placement: .automatic) {
//                    Button(action: {
//                        isShowingPulseConsole = true
//                    }) {
//                        HStack(spacing: 6) {
//                            Image(systemName: "antenna.radiowaves.left.and.right")
//                                .foregroundColor(.green)
//                            Text("网络抓包 (P / D)")
//                        }
//                        .font(.caption)
//                    }
//                    .buttonStyle(.card)
//                }
//            }
            .navigationDestination(item: $selectedMovie) { movie in
                MovieDetailView(item: movie)
            }
            .fullScreenCover(isPresented: $isShowingPulseConsole) {
                PulseConsoleContainerView()
            }
            // 📺 tvOS 顶级窗口物理键盘 P / D / Space 键与遥控器 Play/Pause 响应 (100% 触发)
            .onGlobalKeyShortcutNotification {
                print("⌨️ [ContentView] Toggle Pulse Console triggered via Notification!")
                isShowingPulseConsole.toggle()
            }
            .task {
                await viewModel.fetchInitialFeed()
            }
        }
    }
}

struct MovieCardView: View {
    let item: FeedItem
    
    // 🌟 特性 4：Swift 5.9+ if 表达式化推导 displayBadge
    private var displayBadge: String? {
        if let b = item.badge, !b.isEmpty {
            b
        } else if item.isDRMProtected {
            "DRM"
        } else if item.title?.contains("10间敢死队") == true {
            "DRM"
        } else if item.title?.contains("香港奇案") == true {
            "独播"
        } else {
            nil
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .topLeading) {
                CachedAsyncImage(url: item.secureCoverURL) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .overlay(
                            Image(systemName: "film")
                                .font(.system(size: 40))
                                .foregroundColor(.white.opacity(0.4))
                        )
                }
                .frame(width: 280, height: 420)
                .clipped()
                
                // 🔐 左上角 Badge 提示
                if let badgeText = displayBadge {
                    HStack(spacing: 4) {
                        Image(systemName: badgeIcon(for: badgeText))
                            .font(.system(size: 13, weight: .bold))
                        Text(badgeText)
                            .font(.system(size: 13, weight: .bold))
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(badgeGradient(for: badgeText))
                    .foregroundColor(.white)
                    .cornerRadius(8)
                    .shadow(radius: 4)
                    .padding(12)
                }
                
                // 🌟 右上角评分 Badge
                if let rating = item.rating, !rating.isEmpty {
                    HStack {
                        Spacer()
                        Text(rating)
                            .font(.caption)
                            .bold()
                            .padding(6)
                            .background(Color.orange)
                            .foregroundColor(.white)
                            .cornerRadius(4)
                            .padding(12)
                    }
                }
            }
            .frame(width: 280, height: 420)
            .cornerRadius(16)
            
            // 📺 标题与描述
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title ?? "未知电影")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                if let subtitle = item.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 16))
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(1)
                }
            }
            .frame(width: 280, alignment: .leading)
        }
        .frame(width: 280)
    }
    
    // 🌟 特性 3：if/switch Expressions 简写
    private func badgeIcon(for badge: String) -> String {
        if badge.contains("DRM") || badge.contains("独播") {
            "lock.shield.fill"
        } else if badge.contains("会员") || badge.contains("VIP") {
            "crown.fill"
        } else {
            "star.fill"
        }
    }
    
    private func badgeGradient(for badge: String) -> LinearGradient {
        if badge.contains("DRM") || badge.contains("独播") {
            LinearGradient(colors: [.purple, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing)
        } else if badge.contains("会员") || badge.contains("VIP") {
            LinearGradient(colors: [.pink, .red], startPoint: .topLeading, endPoint: .bottomTrailing)
        } else {
            LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

#Preview {
    ContentView(viewModel: FeedViewModel.mock)
}
