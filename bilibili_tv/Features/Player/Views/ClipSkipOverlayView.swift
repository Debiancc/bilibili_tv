import SwiftUI

/// ⏭️ 跳过片头/片尾提示层：播放进入剪辑区间（clip_info_list）时显示
/// - 按钮标题来自服务端 toastText（如「跳过片头」），缺省按片段类型回退
/// - 倒计时每秒递减显示，归零或点击按钮均触发跳过（seek 到片段终点）
/// - 显隐与倒计时由 VM.clipSkipPrompt 驱动；整颗胶囊即一个焦点元素（tvOS Select 可触发）
struct ClipSkipOverlayView: View {
    let presentation: ClipSkipPresentation
    let onSkip: () -> Void

    var body: some View {
        Button(action: onSkip) {
            HStack(spacing: 14) {
                Image(systemName: "forward.end.fill")
                    .font(.headline)
                Text(presentation.clip.skipButtonTitle)
                    .font(.callout)
                    .bold()
                Text("\(presentation.secondsRemaining)s")
                    .font(.headline)
                    .monospacedDigit()
                    .opacity(0.85)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 14)
        }
        .buttonStyle(.glass)
        .padding(.trailing, 40)
        .padding(.bottom, 100)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
    }
}
