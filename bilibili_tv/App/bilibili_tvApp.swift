import SwiftData
import SwiftUI

@main
struct bilibili_tvApp: App {
    private var authManager = AuthManager.shared

    init() {
        #if DEBUG
        PulseHelper.shared.startRemoteLogging()
        #endif
    }

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            Group {
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-uitestMockFeed") {
                    // 焦点导航 UI 测试注入：跳过登录直达 .loaded 态的 feed
                    ContentView(viewModel: .mock)
                } else if ProcessInfo.processInfo.arguments.contains("-uitestMockDetail") {
                    // 详情页焦点导航 UI 测试注入：直达 .loaded 态详情页（含选集列表）
                    let mockVM = MovieDetailViewModel.mock
                    MovieDetailView(item: mockVM.feedItem, viewModel: mockVM)
                } else if ProcessInfo.processInfo.arguments.contains("-uitestMockPlayer") {
                    // 播放器焦点导航 UI 测试注入：.ready 态 + 本地生成视频（无网络依赖）
                    BiliPlayerContainerView(
                        epId: 320_665,
                        seasonId: 33_354,
                        title: "夏洛特烦恼",
                        subtitle: "马冬梅的排列组合",
                        viewModel: UITestMockPlayerFactory.makeViewModel()
                    )
                } else if authManager.isLoggedIn {
                    ContentView()
                } else {
                    LoginView()
                }
                #else
                if authManager.isLoggedIn {
                    ContentView()
                } else {
                    LoginView()
                }
                #endif
            }
        }
        .modelContainer(sharedModelContainer)
    }
}
