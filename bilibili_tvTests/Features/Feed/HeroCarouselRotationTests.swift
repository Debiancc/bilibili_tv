import Testing

@testable import bilibili_tv

@MainActor
struct HeroCarouselRotationTests {
    @Test("空轮播没有下一页")
    func emptyCarouselHasNoNextPage() {
        #expect(HeroCarouselView.nextPageIndex(after: 0, pageCount: 0) == nil)
    }

    @Test("轮播从中间页推进到下一页")
    func advancesToNextPage() {
        #expect(HeroCarouselView.nextPageIndex(after: 0, pageCount: 3) == 1)
        #expect(HeroCarouselView.nextPageIndex(after: 1, pageCount: 3) == 2)
    }

    @Test("轮播从末页回绕到第一页")
    func wrapsFromLastPage() {
        #expect(HeroCarouselView.nextPageIndex(after: 2, pageCount: 3) == 0)
    }
}
