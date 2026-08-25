import SwiftUI

/// 侧边栏账号入口 label:
/// 使用标准 Label { 昵称 } icon: { 头像 } 结构,
/// 侧边栏展开时显示头像+昵称,收起为药丸时显示小号圆形头像。
/// 未登录/信息未就绪时回退为人形图标(+ 「账号」)。
/// 与账号页共用 AccountViewModel;用户信息在 BilibiliService 层做会话级缓存,
/// 两个入口不会产生重复网络请求。
struct AccountSidebarLabel: View {
    @State private var viewModel = AccountViewModel()

    var body: some View {
        Label {
            nameText
        } icon: {
            avatar
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
        } else {
            Text("账号")
        }
    }
}
