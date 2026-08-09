//
//  SnapshotInfrastructureTests.swift
//  bilibili_tvTests
//
//  阶段 0.1：验证 swift-snapshot-testing 基础设施在 tvOS + Swift Testing 下可用。
//  后续各阶段（阶段一/二/三）的 snapshot 基准测试都以本文件为模板：
//  - @Suite(.snapshots) 启用 Swift Testing 兼容模式
//  - assertSnapshot(of:as:) 生成/比对 __Snapshots__/<TestSuite> 下的基准图
//  - 重构前先生成基准，重构后重新生成，diff 必须为空
//

import SnapshotTesting
import SwiftUI
import Testing

@testable import bilibili_tv

@Suite(.snapshots)
@MainActor
struct SnapshotInfrastructureTests {
    @Test func snapshotLibraryRendersSwiftUIViewToImage() async {
        let view = ZStack {
            Color.black
            Text("Snapshot Infra OK")
                .foregroundStyle(.white)
        }
        .frame(width: 320, height: 180)
        assertSnapshot(of: view, as: .image(precision: 0.95, layout: .fixed(width: 320, height: 180)))
    }
}
