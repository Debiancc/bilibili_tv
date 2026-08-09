import Foundation
import Testing

@testable import bilibili_tv

/// QRCodeDisplayContentFactory 映射的穷尽测试：
/// 覆盖 QRCodeState 全部 case，锁定"状态 → 卡片展示内容"的渲染决策，
/// 确保 LoginView 重构为穷尽 switch 后行为与重构前一致。
@MainActor
struct QRCodeDisplayContentFactoryTests {
    private let sampleURL = "https://passport.bilibili.com/x/passport-login/web/qrcode/test?qrcode_key=abc"

    @Test func initialState_rendersExpiredOverlay() {
        #expect(QRCodeDisplayContentFactory.make(for: .initial) == .expired)
    }

    @Test func loadingState_rendersProgress() {
        #expect(QRCodeDisplayContentFactory.make(for: .loading) == .progress)
    }

    @Test func readyState_rendersAwaitingScanWithURL() {
        let state = QRCodeState.ready(qrURL: sampleURL, qrcodeKey: "abc")
        #expect(QRCodeDisplayContentFactory.make(for: state) == .awaitingScan(url: sampleURL))
    }

    @Test func scannedState_rendersScannedWithURL() {
        let state = QRCodeState.scanned(qrURL: sampleURL)
        #expect(QRCodeDisplayContentFactory.make(for: state) == .scanned(url: sampleURL))
    }

    @Test func expiredState_rendersExpiredOverlay() {
        #expect(QRCodeDisplayContentFactory.make(for: .expired) == .expired)
    }

    @Test func successState_rendersExpiredOverlay() {
        // 保留重构前语义：success 在旧实现中同样落入"已失效"遮罩分支
        #expect(QRCodeDisplayContentFactory.make(for: .success) == .expired)
    }

    @Test func errorState_rendersExpiredOverlay() {
        #expect(QRCodeDisplayContentFactory.make(for: .error(message: "boom")) == .expired)
    }
}
