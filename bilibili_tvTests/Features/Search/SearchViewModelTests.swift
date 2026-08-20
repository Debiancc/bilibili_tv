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

    /// 可门控的服务：每次请求挂起,由测试按序 resume,用于模拟加载中/乱序完成的请求
    private final class GatedSearchService: SearchServicing {
        private var pending: [(keyword: String, resume: (Result<[SearchResultSection], Error>) -> Void)] = []
        private let lock = NSLock()

        var pendingCount: Int {
            lock.lock()
            defer { lock.unlock() }
            return pending.count
        }

        func fetchSearch(keyword: String, page: Int) async throws -> [SearchResultSection] {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                pending.append(
                    (
                        keyword,
                        { result in
                            continuation.resume(with: result)
                        }
                    ))
                lock.unlock()
            }
        }

        /// 按发起顺序逐个完成所有挂起请求
        func resumeAll(_ result: [SearchResultSection]) {
            for (_, resume) in drainPending() {
                resume(.success(result))
            }
        }

        private func drainPending() -> [(String, (Result<[SearchResultSection], Error>) -> Void)] {
            lock.lock()
            defer { lock.unlock() }
            let batch = pending
            pending = []
            return batch
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

    @Test func submit_retryAfterFailure_allowed() async {
        // 先成功 A 词,再失败 B 词(旧结果保留),同词重试 B 应真正发起请求
        let service = MockSearchService(results: [makeSection("media_bangumi", 2)])
        let vm = SearchViewModel(service: service)
        await vm.submit(keyword: "A")
        #expect(vm.state == .loaded)

        service.error = NSError(domain: "test", code: -1, userInfo: [NSLocalizedDescriptionKey: "网络错误"])
        await vm.submit(keyword: "B")
        #expect(vm.sections.count == 1)

        service.error = nil
        service.results = [makeSection("media_ft", 3)]
        await vm.submit(keyword: "B")
        #expect(vm.state == .loaded)
        #expect(vm.sections.first?.resultType == "media_ft")
        #expect(vm.sections.first?.items.count == 3)
    }

    @Test func submit_duringLoading_isIgnored() async {
        let service = GatedSearchService()
        let vm = SearchViewModel(service: service)
        let first = Task { await vm.submit(keyword: "A") }
        while service.pendingCount == 0 { await Task.yield() }
        #expect(vm.state == .loading)

        await vm.submit(keyword: "B")
        #expect(vm.submittedKeyword == "A")

        service.resumeAll([makeSection("media_bangumi", 1)])
        await first.value
        #expect(vm.state == .loaded)
    }

    @Test func submit_reset_invalidatesPendingRequest() async {
        let service = GatedSearchService()
        let vm = SearchViewModel(service: service)
        let pending = Task { await vm.submit(keyword: "A") }
        while service.pendingCount == 0 { await Task.yield() }
        #expect(vm.state == .loading)

        vm.reset()
        #expect(vm.state == .idle)

        service.resumeAll([makeSection("media_bangumi", 9)])
        await pending.value
        // reset 后过期请求完成,不得复活结果
        #expect(vm.state == .idle)
        #expect(vm.sections.isEmpty)
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
