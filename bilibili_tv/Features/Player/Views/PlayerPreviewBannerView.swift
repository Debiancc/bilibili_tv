import SwiftUI

/// 🎬 试看片段提示横幅:未购买时仅能看预览,文案按大会员状态区分
/// 显示条件(viewModel.isPreviewOnly && purchaseHintText != nil)由宿主 View 判断,本视图只渲染文案
struct PlayerPreviewBannerView: View {
    let hint: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.fill")
                .font(.caption)
            VStack(alignment: .leading, spacing: 2) {
                Text("当前为试看片段")
                    .font(.caption)
                    .bold()
                Text(hint)
                    .font(.caption2)
                    .opacity(0.8)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.65))
        .cornerRadius(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 30)
        .padding(.top, 30)
        .allowsHitTesting(false)
    }
}
