import Foundation

/// 🌟 特性 3：Swift 6 线程安全网络配置与共享凭证中枢
final class BilibiliNetworkConfig: @unchecked Sendable {
    static let shared = BilibiliNetworkConfig()

    private init() {}

    /// 用户登录后保存的临时 Cookie 缓存
    var customUserCookie: String? {
        get { UserDefaults.standard.string(forKey: "bilibili_user_cookie") }
        set { UserDefaults.standard.setValue(newValue, forKey: "bilibili_user_cookie") }
    }

    /// 便捷提取或存取 SESSDATA
    var sessData: String? {
        get { UserDefaults.standard.string(forKey: "bilibili_sessdata") }
        set { UserDefaults.standard.setValue(newValue, forKey: "bilibili_sessdata") }
    }

    /// 便捷提取或存取 DedeUserID
    var dedeUserId: String? {
        get { UserDefaults.standard.string(forKey: "bilibili_dede_userid") }
        set { UserDefaults.standard.setValue(newValue, forKey: "bilibili_dede_userid") }
    }

    /// 全局统一共享的 Bilibili 鉴权 Cookie
    var cookie: String {
        if let url = URL(string: "https://bilibili.com"),
            let cookies = HTTPCookieStorage.shared.cookies(for: url),
            !cookies.isEmpty
        {
            let cookieStr = cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
            if cookieStr.contains("SESSDATA=") {
                return cookieStr
            }
        }
        return customUserCookie ?? defaultVisitorCookie
    }

    /// 游客/未登录基础 Cookie
    private var defaultVisitorCookie: String {
        // swiftlint:disable:next line_length
        "buvid3=54A2ED24-678A-E5A2-DA75-D296A223F20244795infoc; b_nut=1759035444; buvid_fp=66f2836d5d23746cd021921a65519570; LIVE_BUVID=AUTO7417590354461792; PVID=1"
    }

    /// 保存登录成功后的 Cookie
    func saveUserCookie(_ newCookie: String) {
        self.customUserCookie = newCookie
    }

    /// 清理用户登录 Cookie
    func clearUserCookie() {
        self.customUserCookie = nil
        self.sessData = nil
        self.dedeUserId = nil
        UserDefaults.standard.removeObject(forKey: "bilibili_user_cookie")
        UserDefaults.standard.removeObject(forKey: "bilibili_sessdata")
        UserDefaults.standard.removeObject(forKey: "bilibili_dede_userid")
    }

    /// 统一通用 Request Headers
    var commonHeaders: [String: String] {
        [
            "accept": "application/json, text/plain, */*",
            "accept-language": "en,zh-CN;q=0.9,zh;q=0.8,ko;q=0.7,zh-TW;q=0.6,ja;q=0.5,de;q=0.4",
            "origin": "https://www.bilibili.com",
            "referer": "https://www.bilibili.com/",
            "user-agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/146.0.0.0 Safari/537.36",
            "cookie": cookie
        ]
    }
}
