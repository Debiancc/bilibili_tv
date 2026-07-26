import SwiftUI
import UIKit
import GameController

extension Notification.Name {
    static let togglePulseConsole = Notification.Name("togglePulseConsoleNotification")
}

/// 🎮 GameController 框架全局物理键盘监听单例 (完全绕过 UIKit 与 tvOS Focus Engine，100% 捕获 P / D / Space 键)
@MainActor
final class GameControllerKeyMonitor {
    static let shared = GameControllerKeyMonitor()
    private var isMonitoring = false
    
    private init() {}
    
    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        
        print("🎮 [GameControllerKeyMonitor] Initializing GCKeyboard monitoring...")
        
        NotificationCenter.default.addObserver(
            forName: .GCKeyboardDidConnect,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                GameControllerKeyMonitor.shared.bindCoalescedKeyboard()
            }
        }
        
        bindCoalescedKeyboard()
    }
    
    private func bindCoalescedKeyboard() {
        guard let keyboard = GCKeyboard.coalesced else {
            print("🎮 [GameControllerKeyMonitor] No coalesced keyboard connected yet.")
            return
        }
        
        print("🎮 [GameControllerKeyMonitor] Bound coalesced GCKeyboard! Listening for keys...")
        keyboard.keyboardInput?.keyChangedHandler = { _, _, keyCode, pressed in
            if pressed {
//                print("🎮 [GameControllerKeyMonitor] KeyPressed: \(keyCode)")
                if keyCode == .keyP || keyCode == .keyD {
//                    print("🎯 [GameControllerKeyMonitor] Matched P/D/Space key! Dispatching Notification...")
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name: .togglePulseConsole, object: nil)
                    }
                }
            }
        }
    }
}

/// 📺 tvOS 顶级窗口全量按键拦截组件 (UIKit 备用与 GameController 自动双绑)
struct WindowKeyMonitorRepresentable: UIViewRepresentable {
    func makeUIView(context: Context) -> WindowKeyMonitorUIView {
        GameControllerKeyMonitor.shared.startMonitoring()
        let view = WindowKeyMonitorUIView()
        return view
    }
    
    func updateUIView(_ uiView: WindowKeyMonitorUIView, context: Context) {}
    
    class WindowKeyMonitorUIView: UIView {
        override var canBecomeFirstResponder: Bool {
            true
        }
        
        override func didMoveToWindow() {
            super.didMoveToWindow()
            DispatchQueue.main.async {
                self.becomeFirstResponder()
            }
        }
        
        override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            var handled = false
            for press in presses {
                if let key = press.key {
                    let chars = key.characters.lowercased()
                    print("⌨️ [WindowKeyMonitor] Keypress captured: '\(chars)'")
                    if chars == "p" || chars == "d" {
                        NotificationCenter.default.post(name: .togglePulseConsole, object: nil)
                        handled = true
                    }
                }
                
                if press.type == .playPause {
                    print("📺 [WindowKeyMonitor] Remote Play/Pause captured!")
                    NotificationCenter.default.post(name: .togglePulseConsole, object: nil)
                    handled = true
                }
            }
            if !handled {
                super.pressesBegan(presses, with: event)
            }
        }
    }
}

extension View {
    /// 全局物理键盘与遥控器快捷键通知监听器
    func onGlobalKeyShortcutNotification(perform action: @escaping () -> Void) -> some View {
        background(
            WindowKeyMonitorRepresentable()
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
        )
        .onReceive(NotificationCenter.default.publisher(for: .togglePulseConsole)) { _ in
            action()
        }
    }
}
