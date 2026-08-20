import Foundation
import Observation

/// 搜索服务协议：便于测试注入 mock（沿用 Feed/Detail 的协议注入模式）
@MainActor
protocol SearchServicing: Sendable {
    func fetchSearch(keyword: String, page: Int) async throws -> [SearchResultSection]
}

extension BilibiliService: SearchServicing {}

@Observable
@MainActor
final class SearchViewModel {
    /// 输入框文本（搜索词）
    var keyword: String = ""
    /// 已执行的搜索词（区别于输入框实时文本，用于结果标题/去重）
    private(set) var submittedKeyword: String = ""
    /// PGC 搜索结果分组
    private(set) var sections: [SearchResultSection] = []

    /// 合并全部分组为单一结果列表（搜索结果页不区分番剧/影视）
    var allResults: [FeedItem] {
        sections.flatMap(\.items).map(\.feedItem)
    }
    /// 互斥状态
    var state: SearchState = .idle

    private let service: any SearchServicing
    /// 当前在途请求标识：只接受最后一次提交的结果，防止过期请求覆盖新结果/reset
    private var activeRequestID = UUID()

    init(service: any SearchServicing = BilibiliService.shared) {
        self.service = service
    }

    /// 提交搜索：
    /// - 空词/加载中忽略；仅当「词未变 且 上次已成功」才去重(允许失败后重试)
    /// - 每次提交生成新请求 ID,过期请求完成后丢弃其结果
    func submit(keyword raw: String) async {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard state != .loading else { return }
        guard trimmed != submittedKeyword || state != .loaded else { return }

        let requestID = UUID()
        activeRequestID = requestID
        keyword = trimmed
        submittedKeyword = trimmed
        state = .loading
        do {
            let result = try await service.fetchSearch(keyword: trimmed, page: 1)
            guard activeRequestID == requestID else { return }
            sections = result
            state = .loaded
        } catch {
            guard activeRequestID == requestID else { return }
            state = .failed(message: error.localizedDescription)
        }
    }

    /// 清空结果回到 idle（用于删除关键词后恢复初始页）
    func reset() {
        // 使在途请求失效,防止其完成后覆盖 reset 后的初始态
        activeRequestID = UUID()
        sections = []
        submittedKeyword = ""
        state = .idle
    }
}

// MARK: - Mock 工厂（UI 测试 / 快照注入）

extension SearchViewModel {
    static var mock: SearchViewModel {
        let vm = SearchViewModel(service: MockSearchService())
        vm.sections = [
            SearchResultSection(
                resultType: "media_bangumi",
                items: [
                    SearchResultItem(
                        seasonId: 40_307,
                        episodeId: nil,
                        title: "测试番剧",
                        cover: "//i0.hdslb.com/bfs/bangumi/image/test.jpg",
                        styles: "悬疑/剧情",
                        score: 9.6,
                        areas: ["日本"],
                        goto: "bangumi",
                        desc: nil
                    )
                ]
            )
        ]
        vm.submittedKeyword = "测试"
        vm.state = .loaded
        return vm
    }
}

/// 测试用空实现：mock 工厂不触发网络
private struct MockSearchService: SearchServicing {
    func fetchSearch(keyword: String, page: Int) async throws -> [SearchResultSection] {
        []
    }
}
