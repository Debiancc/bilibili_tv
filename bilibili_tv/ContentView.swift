import SwiftUI
import SwiftData
import Combine

struct ContentView: View {
    @StateObject private var viewModel = FeedViewModel()
    
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
                            MovieCard(item: item)
                                .onAppear {
                                    if item.id == viewModel.items.last?.id {
                                        Task {
                                            await viewModel.fetchNextPage()
                                        }
                                    }
                                }
                        }
                    }
                    .padding(60)
                }
            }
            .navigationTitle("电影热播")
            .task {
                await viewModel.fetchInitialFeed()
            }
        }
    }
}

struct MovieCard: View {
    let item: FeedItem
    
    var body: some View {
        Button(action: {
            // Handle click - open link or detail view
            if let url = URL(string: item.link) {
                print("Opening link: \(url)")
            }
        }) {
            VStack(alignment: .leading, spacing: 10) {
                ZStack(alignment: .topTrailing) {
                    AsyncImage(url: URL(string: item.cover)) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                    }
                    .frame(width: 300, height: 450)
                    .cornerRadius(12)
                    
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
                
                Text(item.title)
                    .font(.headline)
                    .lineLimit(1)
                    .padding(.horizontal, 4)
                
                Text(item.subtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .padding(.horizontal, 4)
            }
        }
        .buttonStyle(.card) // This handles focus scaling and shadow automatically on tvOS
    }
}

#Preview {
    ContentView()
}
