import UIKit

// MARK: - 💬 AVKit transport bar 自定义项(与字幕/空间音频同排)
// 使用公开 API AVPlayerViewController.transportBarCustomMenuItems (tvOS 15+):
// UIAction 渲染为按钮行图标按钮(弹幕开关),UIMenu 渲染为带子菜单的按钮(弹幕设置)。
// 3c 起状态收敛直连 PlayerViewModel:开关/网络诊断不再写 UserDefaults 等 @AppStorage 转发,
// 而是直接调用 viewModel.setDanmakuEnabled / statsViewModel.isVisible。
// 弹幕设置子菜单(时长/透明度/字号/区域)仍走 UserDefaults + danmakuSettingsDidChange 通知
// (设置是跨播放会话的全局偏好,与会话级开关不同)。

enum DanmakuTransportBarItems {
    @MainActor
    static func makeItems(viewModel: PlayerViewModel) -> [UIMenuElement] {
        let onImage = UIImage(systemName: "list.bullet.rectangle.fill")
        let offImage = UIImage(systemName: "list.bullet.rectangle")

        // 💬 弹幕开关:点击直接收敛到 VM(启停弹幕会话 + 持久化)
        let isOn = viewModel.danmakuEnabled
        let toggleAction = UIAction(title: "显示弹幕", image: isOn ? onImage : offImage, state: isOn ? .on : .off) { [weak viewModel] action in
            guard let viewModel else { return }
            let enabled = !viewModel.danmakuEnabled
            viewModel.setDanmakuEnabled(enabled)
            action.image = enabled ? onImage : offImage
            action.state = enabled ? .on : .off
            print("💬 [Player] Danmaku toggled via transport bar: \(enabled)")
        }

        // ⚙️ 弹幕设置子菜单
        let settingsMenu = UIMenu(
            title: "弹幕设置",
            image: UIImage(systemName: "gearshape"),
            children: [
                durationMenu(),
                opacityMenu(),
                fontSizeMenu(),
                displayAreaMenu()
            ]
        )

        // 📊 网络诊断开关:控制 StatsOverlayView 小窗显示
        // ⏸️ 暂时下线:统计面板入口集成已注释(功能代码保留),不再挂载到 transport bar
        // let statsAction = UIAction(
        //     title: "网络诊断",
        //     image: UIImage(systemName: viewModel.statsViewModel.isVisible ? "chart.bar.fill" : "chart.bar"),
        //     state: viewModel.statsViewModel.isVisible ? .on : .off
        // ) { [weak viewModel] action in
        //     guard let viewModel else { return }
        //     viewModel.statsViewModel.isVisible.toggle()
        //     action.image = UIImage(systemName: viewModel.statsViewModel.isVisible ? "chart.bar.fill" : "chart.bar")
        //     action.state = viewModel.statsViewModel.isVisible ? .on : .off
        //     print("📊 [Player] Stats overlay toggled via transport bar: \(viewModel.statsViewModel.isVisible)")
        // }

        // 🎯 统一入口:一个弹幕控制菜单,内含开关 + 设置 + 网络诊断
        let danmakuMenu = UIMenu(
            title: "弹幕控制",
            image: isOn ? onImage : offImage,
            // 网络诊断入口暂时下线(与统计面板集成一并注释)
            children: [toggleAction, settingsMenu]  // , statsAction
        )
        return [danmakuMenu]
    }

    private static func doubleValue(_ key: String, default def: Double) -> Double {
        let d = UserDefaults.standard
        return d.object(forKey: key) == nil ? def : d.double(forKey: key)
    }

    @MainActor
    private static func durationMenu() -> UIMenu {
        let current = doubleValue(DanmakuSettingsKeys.displayTime, default: 8.0)
        return UIMenu(
            title: "弹幕展示时长",
            options: [.displayInline, .singleSelection],
            children: [4, 6, 8].map { dur in
                UIAction(title: "\(dur) 秒", state: dur == Int(current) ? .on : .off) { _ in
                    UserDefaults.standard.set(Double(dur), forKey: DanmakuSettingsKeys.displayTime)
                    danmakuSettingsDidChange()
                }
            }
        )
    }

    /// 弹幕透明度:50% / 75% / 100%
    @MainActor
    private static func opacityMenu() -> UIMenu {
        let current = doubleValue(DanmakuSettingsKeys.opacity, default: 1.0)
        return UIMenu(
            title: "透明度",
            options: [.displayInline, .singleSelection],
            children: [0.5, 0.75, 1.0].map { value in
                UIAction(title: "\(Int(value * 100))%", state: value == current ? .on : .off) { _ in
                    UserDefaults.standard.set(value, forKey: DanmakuSettingsKeys.opacity)
                    danmakuSettingsDidChange()
                }
            }
        )
    }

    /// 弹幕字号
    @MainActor
    private static func fontSizeMenu() -> UIMenu {
        let current = doubleValue(DanmakuSettingsKeys.fontSize, default: 25.0)
        return UIMenu(
            title: "字号",
            options: [.displayInline, .singleSelection],
            children: [25.0, 33.0, 41.0, 49.0, 57.0].map { value in
                UIAction(title: "\(Int(value))", state: value == current ? .on : .off) { _ in
                    UserDefaults.standard.set(value, forKey: DanmakuSettingsKeys.fontSize)
                    danmakuSettingsDidChange()
                }
            }
        )
    }

    /// 弹幕显示区域:全屏 3/4 / 半屏 1/2 / 小区域 1/4
    @MainActor
    private static func displayAreaMenu() -> UIMenu {
        let current = doubleValue(DanmakuSettingsKeys.displayArea, default: 0.75)
        let options: [(value: Double, title: String)] = [
            (0.75, "全屏 (3/4)"),
            (0.5, "半屏 (1/2)"),
            (0.25, "小区域 (1/4)")
        ]
        return UIMenu(
            title: "显示区域",
            options: [.displayInline, .singleSelection],
            children: options.map { option in
                UIAction(title: option.title, state: option.value == current ? .on : .off) { _ in
                    UserDefaults.standard.set(option.value, forKey: DanmakuSettingsKeys.displayArea)
                    danmakuSettingsDidChange()
                }
            }
        )
    }

    /// 设置变化后通知 DanmakuViewModel 刷新弹幕样式
    private static func danmakuSettingsDidChange() {
        NotificationCenter.default.post(name: .danmakuSettingsDidChange, object: nil)
    }
}
