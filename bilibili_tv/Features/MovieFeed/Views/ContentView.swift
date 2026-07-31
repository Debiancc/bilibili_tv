import SwiftUI
import SwiftData
import Combine
import Kingfisher
struct ContentView: View {
    @State private var viewModel: FeedViewModel
    @State private var selectedMovie: FeedItem?
    @State private var isShowingPulseConsole: Bool = false
    @State private var currentBannerIndex: Int = 0
    @State private var shelfOverlap: CGFloat = -200
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
                        VStack(spacing: 0) {
                            // Hero Carousel
                            if !viewModel.bannerMovies.isEmpty {
                                HeroCarouselView(
                                    items: viewModel.bannerMovies,
                                    selectedIndex: $currentBannerIndex,
                                    selectedMovie: $selectedMovie
                                )
                                .frame(height: 1080)
                                .background(
                                    GeometryReader { geo in
                                        Color.clear
                                            .onChange(of: geo.frame(in: .named("feedScroll")).minY) { _, newValue in
                                                let target: CGFloat = newValue < -100 ? 0 : -200
                                                if shelfOverlap != target {
                                                    withAnimation(.easeOut(duration: 0.2)) {
                                                        shelfOverlap = target
                                                    }
                                                }
                                            }
                                    }
                                )
                                .onReceive(bannerTimer) { _ in
                                    withAnimation {
                                        currentBannerIndex = (currentBannerIndex + 1) % viewModel.bannerMovies.count
                                    }
                                }
                            }
                            
                            // Shelves
                            VStack(spacing: 60) {
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
                            .padding(.top, shelfOverlap)
                        }
                    }
                    .coordinateSpace(name: "feedScroll")
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
                .padding(.trailing, 300) // Keep the right side of the screen clean
                .mask(
                    LinearGradient(
                        gradient: Gradient(colors: [.clear, .black]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
            
            // Content
            VStack(alignment: .leading, spacing: 10) {
                if let logoURL = item.secureLogoURL {
                    KFImage(logoURL)
                        .setProcessor(LogoTrimmingProcessor())
                        .placeholder {
                            Text(item.title ?? "未知影片")
                                .font(.system(size: 38, weight: .bold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                        }
                        .onFailureView {
                            Text(item.title ?? "未知影片")
                                .font(.system(size: 38, weight: .bold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                        }
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 500, maxHeight: 240, alignment: .leading)
                } else {
                    Text(item.title ?? "未知影片")
                        .font(.system(size: 38, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
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
                            .foregroundColor(.white.opacity(0.7))
                            .lineLimit(1)
                    }
                }
                
                // Description
                if let desc = item.desc, !desc.isEmpty {
                    Text(desc)
                        .font(.system(size: 22, weight: .regular))
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(2)
                        .lineSpacing(4)
                        .frame(maxWidth: 700, alignment: .leading)
                }
            }
            .padding(.horizontal, 90)
            .padding(.bottom, 280) // Push content well above the overlapping shelf
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            let bgURL = item.secureOverlayURL ?? item.highResCoverURL ?? item.secureCoverURL
            print("🚀 [HeroBanner] Loading background image: \(bgURL?.absoluteString ?? "nil") for title: \(item.title ?? "Unknown")")
        }
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
                .font(.subheadline)
                .padding(.horizontal, 50)
            
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 15) {
                    ForEach(items) { item in
                        Button(action: {
                            selectedMovie = item
                        }) {
                            MovieCardView(item: item)
                        }
                        .buttonStyle(.card)
                    }
                }
                .padding(.horizontal, 50)
                .padding(.vertical, 0) // Padding for focus scaling
            }
            .scrollClipDisabled() // Allow cards to scale outside scroll view bounds on tvOS 17+
        }
    }
}

// MARK: - Movie Card View
struct MovieCardView: View {
    let item: FeedItem
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            KFImage(item.secureCoverURL)
                .placeholder {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .overlay(
                            Image(systemName: "film")
                                .font(.system(size: 40))
                                .foregroundColor(.white.opacity(0.4))
                        )
                }
                .fade(duration: 0.25)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 250, height: 375)
                .clipped()
            
            if let rating = item.rating, !rating.isEmpty {
                Text(rating)
                    .font(.caption)
                    .bold()
                    .padding(6)
                    .background(Color.orange)
                    .foregroundColor(.white)
                    .cornerRadius(4)
                    .padding(10)
            }
        }
        .frame(width: 250, height: 375)
        .cornerRadius(8)
    }
}

#Preview {
    ContentView(viewModel: FeedViewModel.mock)
}
