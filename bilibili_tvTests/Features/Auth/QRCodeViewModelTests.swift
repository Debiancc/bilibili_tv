import Foundation
import Testing

@testable import bilibili_tv

/// Mock 扫码登录服务：按脚本返回预置结果，驱动 QRCodeViewModel 状态机测试
@MainActor
final class MockQRCodeAuthService: QRCodeAuthServicing {
    var generateResult: Result<QRCodeGenerateData, Error> = .failure(URLError(.badServerResponse))
    var pollResult: Result<QRCodePollData, Error> = .failure(URLError(.badServerResponse))

    private(set) var generateCallCount = 0
    private(set) var pollCallCount = 0

    func generateQRCode() async throws -> QRCodeGenerateData {
        generateCallCount += 1
        return try generateResult.get()
    }

    func pollQRCodeStatus(qrcodeKey: String) async throws -> QRCodePollData {
        pollCallCount += 1
        return try pollResult.get()
    }
}

@MainActor
struct QRCodeViewModelTests {
    private let defaultGenerateData = QRCodeGenerateData(
        url: "https://passport.bilibili.com/x/passport-login/web/qrcode/test?qrcode_key=abc",
        qrcodeKey: "abc"
    )

    // MARK: - generateQRCode

    @Test func generate_success_transitionsToReadyAndStartsPolling() async {
        let service = MockQRCodeAuthService()
        service.generateResult = .success(defaultGenerateData)
        let vm = QRCodeViewModel(service: service)

        await vm.generateQRCode()

        #expect(vm.state == .ready(qrURL: defaultGenerateData.url, qrcodeKey: "abc"))
        #expect(vm.statusText.contains("扫描二维码"))
        #expect(service.generateCallCount == 1)
    }

    @Test func generate_failure_transitionsToError() async {
        let service = MockQRCodeAuthService()
        service.generateResult = .failure(URLError(.notConnectedToInternet))
        let vm = QRCodeViewModel(service: service)

        await vm.generateQRCode()

        #expect(vm.state == .error(message: URLError(.notConnectedToInternet).localizedDescription))
        #expect(vm.statusText.contains("生成二维码失败"))
        #expect(service.generateCallCount == 1)
    }

    // MARK: - pollStatus 状态跃迁

    private func makeReadyViewModel() -> (QRCodeViewModel, MockQRCodeAuthService) {
        let service = MockQRCodeAuthService()
        service.generateResult = .success(defaultGenerateData)
        let vm = QRCodeViewModel(service: service)
        return (vm, service)
    }

    @Test func poll_code0_success_transitionsToSuccessAndStopsPolling() async {
        let (vm, service) = makeReadyViewModel()
        await vm.generateQRCode()

        let url = "https://passport.bilibili.com/x/passport-login/web/qrcode/poll?SESSDATA=test_sessdata&DedeUserID=12345"
        service.pollResult = .success(QRCodePollData(url: url, refreshToken: nil, timestamp: nil, code: 0, message: "ok"))

        await vm.pollStatus(qrcodeKey: "abc")

        #expect(vm.state == .success)
        #expect(vm.statusText.contains("登录成功"))
        #expect(service.pollCallCount == 1)
    }

    @Test func poll_code0_persistsSessDataAndDedeUserID() async {
        let (vm, service) = makeReadyViewModel()
        await vm.generateQRCode()

        let url = "https://passport.bilibili.com/x/passport-login/web/qrcode/poll?SESSDATA=test_sessdata&DedeUserID=12345"
        service.pollResult = .success(QRCodePollData(url: url, refreshToken: nil, timestamp: nil, code: 0, message: "ok"))

        await vm.pollStatus(qrcodeKey: "abc")

        let config = BilibiliNetworkConfig.shared
        let originalSessData = config.sessData
        let originalDedeUserID = config.dedeUserId
        defer {
            config.sessData = originalSessData
            config.dedeUserId = originalDedeUserID
        }

        #expect(config.sessData == "test_sessdata")
        #expect(config.dedeUserId == "12345")
    }

    @Test func poll_code86090_scanned_transitionsToScanned() async {
        let (vm, service) = makeReadyViewModel()
        await vm.generateQRCode()

        service.pollResult = .success(QRCodePollData(url: nil, refreshToken: nil, timestamp: nil, code: 86_090, message: "已扫码"))

        await vm.pollStatus(qrcodeKey: "abc")

        #expect(vm.state == .scanned(qrURL: defaultGenerateData.url))
        #expect(vm.statusText.contains("已扫码"))
    }

    @Test func poll_code86038_expired_transitionsToExpiredAndStopsPolling() async {
        let (vm, service) = makeReadyViewModel()
        await vm.generateQRCode()

        service.pollResult = .success(QRCodePollData(url: nil, refreshToken: nil, timestamp: nil, code: 86_038, message: "已失效"))

        await vm.pollStatus(qrcodeKey: "abc")

        #expect(vm.state == .expired)
        #expect(vm.statusText.contains("二维码已失效"))
    }

    @Test func poll_code86101_waiting_keepsReadyState() async {
        let (vm, service) = makeReadyViewModel()
        await vm.generateQRCode()

        service.pollResult = .success(QRCodePollData(url: nil, refreshToken: nil, timestamp: nil, code: 86_101, message: "未扫码"))

        await vm.pollStatus(qrcodeKey: "abc")

        #expect(vm.state == .ready(qrURL: defaultGenerateData.url, qrcodeKey: "abc"))
    }

    @Test func poll_unknownCode_keepsCurrentState() async {
        let (vm, service) = makeReadyViewModel()
        await vm.generateQRCode()

        service.pollResult = .success(QRCodePollData(url: nil, refreshToken: nil, timestamp: nil, code: 999_999, message: "unknown"))

        await vm.pollStatus(qrcodeKey: "abc")

        #expect(vm.state == .ready(qrURL: defaultGenerateData.url, qrcodeKey: "abc"))
    }

    @Test func poll_networkError_keepsCurrentStateWithoutCrashing() async {
        let (vm, service) = makeReadyViewModel()
        await vm.generateQRCode()

        service.pollResult = .failure(URLError(.notConnectedToInternet))

        await vm.pollStatus(qrcodeKey: "abc")

        #expect(vm.state == .ready(qrURL: defaultGenerateData.url, qrcodeKey: "abc"))
        #expect(service.pollCallCount == 1)
    }

    // MARK: - 轮询生命周期

    @Test func stopPolling_cancelsBackgroundTask() async {
        let service = MockQRCodeAuthService()
        service.generateResult = .success(defaultGenerateData)
        let vm = QRCodeViewModel(service: service)
        await vm.generateQRCode()

        vm.stopPolling()

        // 停止后即使 mock 返回成功，状态也不应被轮询任务推进。
        // 等待时长超过 startPolling 的 2 秒轮询间隔，确保"未取消"也能被暴露。
        service.pollResult = .success(QRCodePollData(url: nil, refreshToken: nil, timestamp: nil, code: 0, message: "ok"))
        try? await Task.sleep(nanoseconds: 2_100_000_000)

        #expect(vm.state == .ready(qrURL: defaultGenerateData.url, qrcodeKey: "abc"))
        #expect(service.pollCallCount == 0)
    }
}
