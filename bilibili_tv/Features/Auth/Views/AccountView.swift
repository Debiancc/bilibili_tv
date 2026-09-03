import Kingfisher
import SwiftUI

/// 用户圆形头像（侧边栏 Tab label 与账号页共用）
/// - Parameter size: 渲染尺寸（pt）；侧边栏 label 内由系统缩放，账号页显式指定
struct UserAvatarView: View {
    let urlString: String?
    var size: CGFloat = 40

    var body: some View {
        KFImage(urlString.flatMap(ImageURL.secure).flatMap(URL.init(string:)))
            .placeholder {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .foregroundStyle(.white.opacity(0.6))
            }
            .fade(duration: 0.25)
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(Circle())
    }
}

/// 账号页：登录用户资料 + 退出登录
struct AccountView: View {
    @State private var viewModel = AccountViewModel()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch viewModel.state {
            case .idle, .loading:
                ProgressView()
            case .loaded(let info):
                AccountProfileSection(info: info)
            case .failed(let message):
                AccountErrorSection(message: message, onRetry: { Task { await viewModel.loadUserInfo() } })
            }
        }
        .task { await viewModel.loadUserInfo() }
    }
}

// MARK: - 资料区

private struct AccountProfileSection: View {
    let info: UserAccountInfo

    var body: some View {
        VStack(spacing: 24) {
            UserAvatarView(urlString: info.face, size: 160)

            Text(info.uname)
                .font(.title3)

            HStack(spacing: 12) {
                Text("Lv.\(info.level)")
                    .font(.callout)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.8), in: Capsule())

                if info.vipStatus == 1 {
                    Text("大会员")
                        .font(.callout)
                        .foregroundStyle(.black)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(Color.pink, in: Capsule())
                }
            }

            Button("退出登录") {
                // 清除 Cookie 后根视图（bilibili_tvApp）自动切回登录页
                AuthManager.shared.logout()
            }
            .buttonStyle(.glassProminent)
        }
    }
}

// MARK: - 错误区

private struct AccountErrorSection: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.yellow)
            Text(message)
                .font(.body)
            Button("重试", action: onRetry)
                .buttonStyle(.glass)
        }
    }
}
