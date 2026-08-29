import SwiftUI

/// 侧边栏账号入口 label:
/// - showsName=false(tvOS <27 的首条 item):仅渲染小号圆形头像(无昵称文字)；
/// - showsName=true(tvOS 27+ 的 sidebar header):大头像 + 昵称 + 副标题竖排,
///   同时抬升 header 高度 → 系统 sidebar 总高度 = header + 条目,随之变高
///   (header 非 tab item,不影响条目行高)。
/// 未登录/信息未就绪时回退为人形图标(+ 「账号」)。
/// ⚠️ 系统 TabView label 会重新包装内容(拉伸尺寸、忽略部分修饰)，
/// 故 item 形态用 fixedSize + 固定 frame 抑制拉伸,clipShape(Circle()) 保证圆形渲染。
/// 与账号页共用 AccountViewModel;用户信息在 BilibiliService 层做会话级缓存,
/// 缓存首次成功拉取后生效(避免此后两个入口的重复请求;首次并发仍可能各发一次,幂等无害)。
struct AccountSidebarLabel: View {
    @State private var viewModel = AccountViewModel()
    /// header 形态显示昵称;item 形态仅头像
    var showsName: Bool = false

    var body: some View {
        Group {
            if showsName {
                headerContent
            } else {
                avatar(size: 32)
                    .frame(width: 32, height: 32)
                    .fixedSize()
            }
        }
        .task { await viewModel.loadUserInfo() }
    }

    /// header 形态:大头像 + 昵称 + 副标题(等级/大会员),抬高 sidebar 高度
    private var headerContent: some View {
        HStack(spacing: 16) {
            avatar(size: 56)
            VStack(alignment: .leading, spacing: 4) {
                nameText
                subtitleText
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
    }

    @ViewBuilder
    private func avatar(size: CGFloat) -> some View {
        if case .loaded(let info) = viewModel.state {
            UserAvatarView(urlString: info.face, size: size)
        } else {
            Image(systemName: "person.crop.circle")
                .font(.system(size: size))
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

    @ViewBuilder
    private var subtitleText: some View {
        if case .loaded(let info) = viewModel.state {
            let badge = info.vipStatus == 1 ? "大会员" : nil
            Text(badge.map { "Lv.\(info.level) · \($0)" } ?? "Lv.\(info.level)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        } else {
            Text("点击进入账号")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
