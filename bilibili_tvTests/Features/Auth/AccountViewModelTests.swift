import Foundation
import Testing

@testable import bilibili_tv

@MainActor
struct AccountViewModelTests {
    @Test func userAccountInfo_decodesFromJson() throws {
        let json = Data(
            """
            {
                "code": 0,
                "message": "0",
                "data": {
                    "mid": 12345678,
                    "uname": "测试用户",
                    "face": "https://i0.hdslb.com/bfs/face/test.jpg",
                    "vipStatus": 1,
                    "level_info": {
                        "current_level": 6
                    }
                }
            }
            """.utf8)

        let response = try JSONDecoder().decode(UserAccountNavResponse.self, from: json)
        #expect(response.code == 0)
        let data = try #require(response.data)
        #expect(data.mid == 12_345_678)
        #expect(data.uname == "测试用户")
        #expect(data.face == "https://i0.hdslb.com/bfs/face/test.jpg")
        #expect(data.vipStatus == 1)
        #expect(data.level == 6)
    }

    @Test func accountViewModel_initialState_isLoading() {
        let vm = AccountViewModel()
        if case .loading = vm.state {
            #expect(true)
        } else {
            Issue.record("Initial state must be loading")
        }
    }
}
