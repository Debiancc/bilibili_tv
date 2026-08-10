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
