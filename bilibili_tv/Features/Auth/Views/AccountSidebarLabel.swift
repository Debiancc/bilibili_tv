import SwiftUI

/// 侧边栏账号入口 label:
/// - showsName=false(tvOS <27 的首条 item):仅渲染小号圆形头像(无昵称文字)；
/// - showsName=true(tvOS 27+ 的 sidebar header):头像 + 昵称横排。
/// 未登录/信息未就绪时回退为人形图标(+ 「账号」)。
/// ⚠️ 系统 TabView label 会重新包装内容(拉伸尺寸、忽略部分修饰)，
/// 故 item 形态用 fixedSize + 固定 frame 抑制拉伸,clipShape(Circle()) 保证圆形渲染。
/// 与账号页共用 AccountViewModel；用户信息在 BilibiliService 层做会话级缓存，
/// 两个入口不会产生重复网络请求。
struct AccountSidebarLabel: View {
    @State private var viewModel = AccountViewModel()
    /// header 形态显示昵称;item 形态仅头像
    var showsName: Bool = false

    var body: some View {
        Group {
            if showsName {
                HStack(spacing: 12) {
                    avatar
                    nameText
                }
            } else {
                avatar
                    .frame(width: 32, height: 32)
                    .fixedSize()
            }
        }
        .task { await viewModel.loadUserInfo() }
    }

    @ViewBuilder
    private var avatar: some View {
        if case .loaded(let info) = viewModel.state {
            UserAvatarView(urlString: info.face, size: 32)
        } else {
            Image(systemName: "person.crop.circle")
                .font(.system(size: 32))
        }
    }

    @ViewBuilder
    private var nameText: some View {
        if case .loaded(let info) = viewModel.state {
            Text(info.uname)
                .font(.callout)
        } else {
            Text("账号")
                .font(.callout)
        }
    }
}
