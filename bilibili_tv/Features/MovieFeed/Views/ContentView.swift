import SwiftUI
import SwiftData
import Combine

struct ContentView: View {
    @State private var viewModel: FeedViewModel
    @State private var selectedMovie: FeedItem?
    @State private var isShowingPulseConsole: Bool = false
    @State private var currentBannerIndex: Int = 0
    let bannerTimer = Timer.publish(every: 8, on: .main, in: .common).autoconnect()
    
    @MainActor
    init(viewModel: FeedViewModel? = nil) {
        _viewModel = State(initialValue: viewModel ?? FeedViewModel())
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background Color
                Color.black.ignoresSafeArea()
                
                if viewModel.isLoading && viewModel.rankMovies.isEmpty {
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
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 60) {
                            // Hero Carousel
                            if !viewModel.bannerMovies.isEmpty {
                                HeroCarouselView(
                                    items: viewModel.bannerMovies,
                                    selectedIndex: $currentBannerIndex,
                                    selectedMovie: $selectedMovie
                                )
                                .frame(height: 800)
                                // Only top and horizontal need to bleed
                                .onReceive(bannerTimer) { _ in
                                    withAnimation {
                                        currentBannerIndex = (currentBannerIndex + 1) % viewModel.bannerMovies.count
                                    }
                                }
                            }
                            
                            // Shelves
                            if !viewModel.rankMovies.isEmpty {
                                MovieShelfView(title: "电影热播榜", items: viewModel.rankMovies, selectedMovie: $selectedMovie)
                            }
                            
                            if !viewModel.exclusiveMovies.isEmpty {
                                MovieShelfView(title: "海量热播", items: viewModel.exclusiveMovies, selectedMovie: $selectedMovie)
                            }
                            
                            if !viewModel.comingSoonMovies.isEmpty {
                                MovieShelfView(title: "即将上线", items: viewModel.comingSoonMovies, selectedMovie: $selectedMovie)
                            }
                            
                            Spacer(minLength: 100)
                        }
                    }
                    .edgesIgnoringSafeArea([.horizontal, .top])
                }
            }
            .navigationDestination(item: $selectedMovie) { movie in
                MovieDetailView(item: movie)
            }
            .fullScreenCover(isPresented: $isShowingPulseConsole) {
                PulseConsoleContainerView()
            }
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

// MARK: - Hero Carousel View
struct HeroCarouselView: View {
    let items: [FeedItem]
    @Binding var selectedIndex: Int
    @Binding var selectedMovie: FeedItem?
    
    var body: some View {
        TabView(selection: $selectedIndex) {
            ForEach(items.indices, id: \.self) { index in
                Button(action: {
                    selectedMovie = items[index]
                }) {
                    HeroBannerView(item: items[index])
                }
                .buttonStyle(.plain) // Use plain to prevent card scaling on full-bleed images
                .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
    }
}

// MARK: - Hero Banner View
struct HeroBannerView: View {
    let item: FeedItem
    
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Background Image
            CachedAsyncImage(url: item.highResCoverURL ?? item.secureCoverURL) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: 800)
                    .clipped()
            } placeholder: {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(maxWidth: .infinity, maxHeight: 800)
            }
            
            // Gradient Overlay
            LinearGradient(
                gradient: Gradient(colors: [.clear, .black.opacity(0.9)]),
                startPoint: .center,
                endPoint: .bottom
            )
            .frame(height: 800)
            
            // Content
            VStack(alignment: .leading, spacing: 12) {
                if let badge = item.badge, !badge.isEmpty {
                    Text(badge)
                        .font(.caption)
                        .bold()
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.2))
                        .cornerRadius(8)
                }
                
                Text(item.title ?? "未知影片")
                    .font(.system(size: 64, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                if let subtitle = item.displaySubtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.title3)
                        .foregroundColor(.white.opacity(0.8))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 90)
            .padding(.bottom, 60) // Keep text above the page indicator
        }
        .frame(maxWidth: .infinity, maxHeight: 800)
    }
}

// MARK: - Movie Shelf View
struct MovieShelfView: View {
    let title: String
    let items: [FeedItem]
    @Binding var selectedMovie: FeedItem?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(title)
                .font(.title2)
                .bold()
                .padding(.horizontal, 90)
            
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 40) {
                    ForEach(items) { item in
                        Button(action: {
                            selectedMovie = item
                        }) {
                            MovieCardView(item: item)
                        }
                        .buttonStyle(.card)
                    }
                }
                .padding(.horizontal, 90)
                .padding(.vertical, 20) // Padding for focus scaling
            }
            .scrollClipDisabled() // Allow cards to scale outside scroll view bounds on tvOS 17+
        }
    }
}

// MARK: - Movie Card View
struct MovieCardView: View {
    let item: FeedItem
    
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
                .frame(width: 250, height: 375) // Standard 2:3 poster ratio
                .clipped()
                
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
            .frame(width: 250, height: 375)
            .cornerRadius(12)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title ?? "未知电影")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                if let subtitle = item.displaySubtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(1)
                }
            }
            .frame(width: 250, alignment: .leading)
        }
        .frame(width: 250)
    }
    
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
