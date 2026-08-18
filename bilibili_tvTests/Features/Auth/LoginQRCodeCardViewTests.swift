import SwiftUI
import Testing

@testable import bilibili_tv

/// LoginQRCodeCardView 冒烟测试：每种展示内容都能构建 body 而不崩溃。
/// 纯展示层验证，与 DetailViewTests 的 `_ = view.body` 模式一致。
@MainActor
struct LoginQRCodeCardViewTests {
    private let sampleURL = "https://passport.bilibili.com/x/passport-login/web/qrcode/test?qrcode_key=abc"

    @Test func progressContent_buildsBodyWithoutCrashing() {
        let view = LoginQRCodeCardView(content: .progress)
        _ = view.body
    }

    @Test func awaitingScanContent_buildsBodyWithoutCrashing() {
        let view = LoginQRCodeCardView(content: .awaitingScan(url: sampleURL))
        _ = view.body
    }

    @Test func scannedContent_buildsBodyWithoutCrashing() {
        let view = LoginQRCodeCardView(content: .scanned(url: sampleURL))
        _ = view.body
    }

    @Test func expiredContent_buildsBodyWithoutCrashing() {
        let view = LoginQRCodeCardView(content: .expired)
        _ = view.body
    }

    @Test func successContent_buildsBodyWithoutCrashing() {
        let view = LoginQRCodeCardView(content: .success)
        _ = view.body
    }

    @Test func errorContent_buildsBodyWithoutCrashing() {
        let view = LoginQRCodeCardView(content: .error(message: "boom"))
        _ = view.body
    }

    @Test func loginView_buildsBodyWithoutCrashing() {
        let view = LoginView()
        _ = view.body
    }
}
