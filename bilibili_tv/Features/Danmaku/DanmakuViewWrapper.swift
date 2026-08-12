import SwiftUI

/// SwiftUI 包装 DanmakuView (渲染层直接叠在播放器视频之上)
struct DanmakuViewWrapper: UIViewRepresentable {
    let viewModel: DanmakuViewModel

    func makeUIView(context: Context) -> DanmakuView {
        let view = DanmakuView(frame: .zero)
        view.isUserInteractionEnabled = false
        viewModel.attach(view: view)
        return view
    }

    func updateUIView(_ uiView: DanmakuView, context: Context) {}

    static func dismantleUIView(_ uiView: DanmakuView, coordinator: ()) {
        uiView.stop()
        uiView.clean()
    }
}
