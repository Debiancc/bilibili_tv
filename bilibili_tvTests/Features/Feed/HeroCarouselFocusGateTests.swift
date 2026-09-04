//
//  HeroCarouselFocusGateTests.swift
//  bilibili_tvTests
//
//  Issue #52:轮播背景视频「焦点离开即暂停」的焦点局部性纯函数契约。
//  判定逻辑提取为 HeroCarouselView.isFocusWithin(buttonFocus:wrapAnchorFocused:)
//  纯函数,可在焦点引擎外单测;@FocusState 的接线由 UI 测试覆盖。
//

import Foundation
import Testing

@testable import bilibili_tv

@MainActor
struct HeroCarouselFocusGateTests {
    @Test("给定 nil 按钮焦点且锚点未聚焦 → 焦点不在轮播内(应暂停背景视频)")
    func focusOutsideCarouselPausesVideo() {
        #expect(!HeroCarouselView.isFocusWithin(buttonFocus: nil, wrapAnchorFocused: false))
    }

    @Test("给定任一页的任一按钮焦点 → 焦点在轮播内")
    func buttonFocusOnAnyPageCountsAsInside() {
        for page in 0...2 {
            #expect(HeroCarouselView.isFocusWithin(buttonFocus: .play(page), wrapAnchorFocused: false))
            #expect(HeroCarouselView.isFocusWithin(buttonFocus: .detail(page), wrapAnchorFocused: false))
            #expect(HeroCarouselView.isFocusWithin(buttonFocus: .bookmark(page), wrapAnchorFocused: false))
            #expect(HeroCarouselView.isFocusWithin(buttonFocus: .next(page), wrapAnchorFocused: false))
        }
    }

    /// 回归:末页按钮→回绕锚点交接瞬间,button 焦点已变 nil 而锚点尚未落定
    /// (HeroCarouselView.isWrapAnchorEnabled 注释记录的交接期)。
    /// 若此时误判「焦点已离开」,背景视频会经历一次无谓的 pause→resume 顿挫。
    @Test("给定锚点聚焦(即使按钮焦点为 nil) → 焦点仍在轮播内(交接期不得误暂停)")
    func wrapAnchorHandoffCountsAsInside() {
        #expect(HeroCarouselView.isFocusWithin(buttonFocus: nil, wrapAnchorFocused: true))
        #expect(HeroCarouselView.isFocusWithin(buttonFocus: .play(1), wrapAnchorFocused: true))
    }

    // MARK: - 程序性轮播重锚重试判定(issue #57)

    /// 回归:CI 慢机上焦点引擎在滚动/重锚过渡中丢弃程序性 FocusState 写入,
    /// 焦点原封停在「翻页前的那一个按钮」——这是引擎回吐写入的签名,应重写。
    @Test("给定焦点仍停在翻页前的同一按钮 → 应重写重锚(引擎回吐签名)")
    func focusStillOnSourceButtonReissuesRotationFocus() {
        #expect(HeroCarouselView.shouldReissueRotationFocus(current: .play(0), source: .play(0)))
        #expect(HeroCarouselView.shouldReissueRotationFocus(current: .detail(1), source: .detail(1)))
        #expect(HeroCarouselView.shouldReissueRotationFocus(current: .bookmark(2), source: .bookmark(2)))
    }

    @Test("给定焦点已落定到目标页 → 不重写")
    func focusLandedOnTargetPageSkipsRewrite() {
        #expect(!HeroCarouselView.shouldReissueRotationFocus(current: .play(1), source: .play(0)))
        #expect(!HeroCarouselView.shouldReissueRotationFocus(current: .detail(1), source: .play(0)))
    }

    /// 焦点被移出轮播(nil)或在宽限窗内被用户挪到其他元素:不抢焦点。
    /// (nil 是自动翻页的 selectedIndex 直写路径的常态,也须放行)
    @Test("给定焦点为 nil 或已落到其他元素 → 不重写(用户权威)")
    func focusMovedElsewhereSkipsRewrite() {
        #expect(!HeroCarouselView.shouldReissueRotationFocus(current: nil, source: .play(0)))
        #expect(!HeroCarouselView.shouldReissueRotationFocus(current: .detail(0), source: .play(0)))
        #expect(!HeroCarouselView.shouldReissueRotationFocus(current: .bookmark(1), source: .play(0)))
        #expect(!HeroCarouselView.shouldReissueRotationFocus(current: .next(0), source: .play(0)))
    }
}
