//
//  DanmakuViewModelTests.swift
//  bilibili_tvTests
//
//  阶段六：DanmakuViewModel 从 ObservableObject+@Published 迁移到 @Observable 后的
//  行为等价性冒烟测试：
//  - applySettings 默认值/存储值读取（object(forKey:) == nil 显式判空）
//  - settingsDidChange 重新应用
//  - 会话状态 start/stop 切换（@Observable 无 @Published，断言直接读属性）
//

import AVFoundation
import Foundation
import Testing

@testable import bilibili_tv

@MainActor
struct DanmakuViewModelTests {
    /// 弹幕数据层 stub：无网络请求
    private struct StubProvider: DanmakuProviding {
        func initVideo(cid: Int, startPos: TimeInterval) async {}
        func playerTimeChange(time: TimeInterval) async -> [DanmakuProvider.Danmu] { [] }
    }

    private static let danmakuKeys = [
        DanmakuSettingsKeys.fontSize,
        DanmakuSettingsKeys.opacity,
        DanmakuSettingsKeys.displayTime,
        DanmakuSettingsKeys.displayArea
    ]

    private func clearSettings() {
        for key in Self.danmakuKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    // MARK: - applySettings 行为等价性

    @Test func attach_appliesDefaultsWhenKeysAbsent() {
        clearSettings()
        defer { clearSettings() }
        let vm = DanmakuViewModel(provider: StubProvider())
        let view = DanmakuView(frame: .zero)
        vm.attach(view: view)
        #expect(view.trackHeight == 25 * 1.3)
        #expect(view.displayArea == 0.75)
    }

    @Test func attach_appliesStoredValuesWhenPresent() {
        clearSettings()
        defer { clearSettings() }
        UserDefaults.standard.set(30.0, forKey: DanmakuSettingsKeys.fontSize)
        UserDefaults.standard.set(0.5, forKey: DanmakuSettingsKeys.opacity)
        UserDefaults.standard.set(5.0, forKey: DanmakuSettingsKeys.displayTime)
        UserDefaults.standard.set(0.5, forKey: DanmakuSettingsKeys.displayArea)
        let vm = DanmakuViewModel(provider: StubProvider())
        let view = DanmakuView(frame: .zero)
        vm.attach(view: view)
        #expect(view.trackHeight == 30 * 1.3)
        #expect(view.displayArea == 0.5)
    }

    @Test func settingsDidChange_reappliesSettings() {
        clearSettings()
        defer { clearSettings() }
        let vm = DanmakuViewModel(provider: StubProvider())
        let view = DanmakuView(frame: .zero)
        vm.attach(view: view)
        UserDefaults.standard.set(40.0, forKey: DanmakuSettingsKeys.fontSize)
        vm.settingsDidChange()
        #expect(view.trackHeight == 40 * 1.3)
    }

    // MARK: - 会话状态（@Observable 直接读取）

    @Test func startAndStop_toggleSessionState() {
        let vm = DanmakuViewModel(provider: StubProvider())
        #expect(vm.sessionState == .idle)
        vm.start(cid: 123_456, player: AVPlayer(), startTime: 0)
        #expect(vm.sessionState == .active)
        vm.stop()
        #expect(vm.sessionState == .idle)
    }
}
