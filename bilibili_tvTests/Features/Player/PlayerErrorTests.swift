//
//  PlayerErrorTests.swift
//  bilibili_tvTests
//
//  PlayerError 类型化错误测试：
//  - 每个 case 的 userMessage 与旧 UI 文案逐字一致（行为不变）
//  - normalize 归一化映射（URLError → .network，PlayerError 透传，未知 → .unknown）
//  - Equatable 基于底层 NSError domain+code 比较
//

import Foundation
import Testing

@testable import bilibili_tv

struct PlayerErrorTests {
    // MARK: - userMessage 与旧文案一致

    @Test func userMessage_matchesPreviousUIStrings() {
        #expect(PlayerError.missingIdentifiers.userMessage == "缺少剧集或季度 ID，无法播放")
        #expect(
            PlayerError.sourceUnavailable.userMessage
                == "无法解析播放流（可能需要大会员或 CDN 鉴权失败）")
        #expect(PlayerError.unsupportedFormat.userMessage == "无法创建合成轨道")
    }

    @Test func userMessage_networkAndUnknownPreserveUnderlyingDescription() {
        let timeout = URLError(.timedOut)
        #expect(PlayerError.network(timeout).userMessage == timeout.localizedDescription)

        let generic = NSError(
            domain: "TestDomain", code: 42, userInfo: [NSLocalizedDescriptionKey: "boom"])
        #expect(PlayerError.unknown(generic).userMessage == "boom")
    }

    // MARK: - normalize 归一化映射

    @Test func normalize_mapsURLErrorToNetwork() {
        let normalized = PlayerError.normalize(URLError(.notConnectedToInternet))
        #expect(normalized == .network(URLError(.notConnectedToInternet)))
    }

    @Test func normalize_passesThroughPlayerError() {
        #expect(PlayerError.normalize(PlayerError.sourceUnavailable) == .sourceUnavailable)
        #expect(PlayerError.normalize(PlayerError.missingIdentifiers) == .missingIdentifiers)
    }

    @Test func normalize_unknownPreservesDiagnostics() {
        let generic = NSError(
            domain: "TestDomain", code: 7, userInfo: [NSLocalizedDescriptionKey: "something broke"])
        let normalized = PlayerError.normalize(generic)

        guard case .unknown(let underlying) = normalized else {
            Issue.record("expected .unknown, got \(normalized)")
            return
        }
        #expect((underlying as NSError).domain == "TestDomain")
        #expect((underlying as NSError).code == 7)
        #expect(normalized.userMessage == "something broke")
    }

    // MARK: - Equatable 语义

    @Test func equality_comparesUnderlyingErrorByDomainAndCode() {
        let errorA = NSError(domain: "D", code: 1)
        let errorB = NSError(domain: "D", code: 1)
        let errorC = NSError(domain: "D", code: 2)
        #expect(PlayerError.unknown(errorA) == PlayerError.unknown(errorB))
        #expect(PlayerError.unknown(errorA) != PlayerError.unknown(errorC))
        #expect(PlayerError.network(URLError(.timedOut)) != PlayerError.network(URLError(.cancelled)))
        #expect(PlayerError.sourceUnavailable != PlayerError.missingIdentifiers)
    }
}
