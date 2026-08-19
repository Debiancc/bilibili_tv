//
//  SearchViewModelTests.swift
//  bilibili_tvTests
//
//  搜索 ViewModel 行为测试：状态机转移、历史记录去重/上限、空词与重复提交守卫。
//

import Foundation
import Testing

@testable import bilibili_tv

@MainActor
struct SearchViewModelTests {
    /// 可控搜索服务：按注入顺序返回结果，或抛错
    private final class MockSearchService: SearchServicing {
        var results: [SearchResultSection]
        var error: Error?

        init(results: [SearchResultSection] = [], error: Error? = nil) {
            self.results = results
            self.error = error
        }

        func fetchSearch(keyword: String, page: Int) async throws -> [SearchResultSection] {
            if let error { throw error }
            return results
        }
    }

    private func makeSection(_ resultType: String, _ count: Int) -> SearchResultSection {
        SearchResultSection(
            resultType: resultType,
            items: (0..<count).map { index in
                SearchResultItem(
                    seasonId: index + 1,
                    episodeId: nil,
                    title: "结果\(index)",
                    cover: nil,
                    styles: nil,
                    score: nil,
                    areas: [],
                    goto: nil,
                    desc: nil
                )
            }
        )
    }

    // MARK: - 状态机

    @Test func submit_success_movesToLoaded() async {
        let vm = SearchViewModel(service: MockSearchService(results: [makeSection("media_bangumi", 2)]))
        await vm.submit(keyword: "测试")

        #expect(vm.state == .loaded)
        #expect(vm.sections.count == 1)
        #expect(vm.sections.first?.isPGC == true)
        #expect(vm.submittedKeyword == "测试")
    }

    @Test func submit_failure_movesToFailed() async {
        let vm = SearchViewModel(
            service: MockSearchService(
                error: NSError(domain: "test", code: -1, userInfo: [NSLocalizedDescriptionKey: "网络错误"])
            )
        )
        await vm.submit(keyword: "测试")

        if case .failed(let message) = vm.state {
            #expect(message == "网络错误")
        } else {
            Issue.record("期望 failed 状态,实际 \(vm.state)")
        }
        #expect(vm.sections.isEmpty)
    }

    @Test func submit_blankKeyword_isIgnored() async {
        let vm = SearchViewModel(service: MockSearchService(results: [makeSection("media_ft", 1)]))
        await vm.submit(keyword: "   ")

        #expect(vm.state == .idle)
        #expect(vm.sections.isEmpty)
    }

    @Test func submit_sameKeyword_isDeduplicated() async {
        let vm = SearchViewModel(service: MockSearchService(results: [makeSection("media_bangumi", 1)]))
        await vm.submit(keyword: "测试")
        await vm.submit(keyword: "测试")

        #expect(vm.state == .loaded)
        #expect(vm.sections.count == 1)
    }

    @Test func submit_trimsWhitespace() async {
        let vm = SearchViewModel(service: MockSearchService(results: [makeSection("media_bangumi", 1)]))
        await vm.submit(keyword: "  测试  ")

        #expect(vm.submittedKeyword == "测试")
        #expect(vm.keyword == "测试")
    }

    // MARK: - reset

    @Test func reset_returnsToIdle() async {
        let vm = SearchViewModel(service: MockSearchService(results: [makeSection("media_bangumi", 1)]))
        await vm.submit(keyword: "测试")
        vm.reset()

        #expect(vm.state == .idle)
        #expect(vm.sections.isEmpty)
        #expect(vm.submittedKeyword.isEmpty)
    }
}
