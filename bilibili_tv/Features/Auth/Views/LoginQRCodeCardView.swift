import SwiftUI

/// 登录页二维码卡片：仅根据 `QRCodeDisplayContent` 渲染，不含任何状态判断逻辑
struct LoginQRCodeCardView: View {
    let content: QRCodeDisplayContent

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.white)
                .frame(width: 320, height: 320)
                .shadow(color: .pink.opacity(0.3), radius: 20, x: 0, y: 10)

            switch content {
            case .progress:
                ProgressView()
                    .scaleEffect(1.8)

            case .awaitingScan(let url):
                QRCodeView(urlString: url)
                    .frame(width: 270, height: 270)

            case .scanned(let url):
                QRCodeView(urlString: url)
                    .frame(width: 270, height: 270)
                    .opacity(0.3)
                ScannedOverlayView()

            case .expired:
                ExpiredOverlayView()
            }
        }
    }
}

/// 已扫码遮罩
private struct ScannedOverlayView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.green)
            Text("已扫码")
                .font(.title2)
                .bold()
                .foregroundStyle(.black)
        }
    }
}

/// 二维码已失效遮罩
private struct ExpiredOverlayView: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.arrow.triangle.2.circlepath")
                .font(.system(size: 50))
                .foregroundStyle(.orange)
            Text("二维码已失效")
                .font(.headline)
                .foregroundStyle(.black)
        }
    }
}
