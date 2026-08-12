//
//  ImageURLTests.swift
//  bilibili_tvTests
//
//  阶段五：URL 规范化共享工具（ImageURL）冒烟测试。
//  覆盖 `//` 协议相对地址、`http://` 升级、空串/nil 边界、CDN 切片参数幂等、webp→jpg 转换。
//

import Foundation
import Testing

@testable import bilibili_tv

struct ImageURLTests {
    // MARK: - secure

    @Test func secure_prependsSchemeToProtocolRelativeURL() {
        #expect(ImageURL.secure("//i0.hdslb.com/bfs/x.png") == "https://i0.hdslb.com/bfs/x.png")
    }

    @Test func secure_upgradesHttpToHttps() {
        #expect(ImageURL.secure("http://example.com/cover.png") == "https://example.com/cover.png")
    }

    @Test func secure_passesThroughHttps() {
        #expect(ImageURL.secure("https://example.com/cover.png") == "https://example.com/cover.png")
    }

    @Test func secure_returnsNilForEmptyOrNilInput() {
        #expect(ImageURL.secure(nil) == nil)
        #expect(ImageURL.secure("") == nil)
        #expect(ImageURL.secure("   ") == "   ")
    }

    // MARK: - cdn

    @Test func cdn_appendsSuffixWhenNoSliceParameter() {
        #expect(
            ImageURL.cdn("https://example.com/cover.png", suffix: "@300w_450h_1c.webp")
                == "https://example.com/cover.png@300w_450h_1c.webp"
        )
    }

    @Test func cdn_keepsExistingSliceParameter() {
        #expect(
            ImageURL.cdn("https://example.com/cover.png@640w_960h_1c.webp", suffix: "@300w_450h_1c.webp")
                == "https://example.com/cover.png@640w_960h_1c.webp"
        )
    }

    // MARK: - webpToJpg

    @Test func webpToJpg_convertsWebpSuffixOnly() {
        #expect(ImageURL.webpToJpg("https://example.com/cover.webp") == "https://example.com/cover.jpg")
        #expect(ImageURL.webpToJpg("https://example.com/cover.png") == "https://example.com/cover.png")
        #expect(
            ImageURL.webpToJpg("https://example.com/cover.webp@400w_225h_1c.webp")
                == "https://example.com/cover.jpg@400w_225h_1c.jpg")
    }
}
