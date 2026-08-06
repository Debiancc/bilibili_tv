import SwiftUI

struct LoginView: View {
    @State private var viewModel = QRCodeViewModel()
    @FocusState private var isRefreshFocused: Bool
    
    var body: some View {
        ZStack {
            // 深色沉浸背景
            Color.black.ignoresSafeArea()
            
            // 暗纹极光渐变
            RadialGradient(
                gradient: Gradient(colors: [Color.pink.opacity(0.18), Color.blue.opacity(0.12), Color.black]),
                center: .center,
                startRadius: 100,
                endRadius: 700
            )
            .ignoresSafeArea()
            
            HStack(spacing: 100) {
                // 左侧品牌标语与扫码指导
                VStack(alignment: .leading, spacing: 28) {
                    HStack(spacing: 16) {
                        Image(systemName: "tv.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.pink)
                        
                        Text("哔哩哔哩 TV")
                            .font(.system(size: 44, weight: .bold))
                            .foregroundColor(.white)
                    }
                    
                    Text("登录解锁 4K 极清画质与大会员权益")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundColor(.pink.opacity(0.9))
                    
                    VStack(alignment: .leading, spacing: 18) {
                        InstructionRow(number: "1", text: "打开手机 哔哩哔哩 App")
                        InstructionRow(number: "2", text: "点击右上角「扫一扫」图标")
                        InstructionRow(number: "3", text: "对准右侧二维码，并在手机上确认登录")
                    }
                    .padding(.top, 10)
                    
                    Text("提示：本项目已开启强制登录认证，不提供匿名访问。")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.5))
                        .padding(.top, 10)
                }
                .frame(width: 520)
                
                // 右侧二维码展示区
                VStack(spacing: 24) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 24)
                            .fill(Color.white)
                            .frame(width: 320, height: 320)
                            .shadow(color: .pink.opacity(0.3), radius: 20, x: 0, y: 10)
                        
                        if viewModel.isLoading {
                            ProgressView()
                                .scaleEffect(1.8)
                        } else if let qrURL = viewModel.qrCodeURL, !viewModel.isExpired {
                            QRCodeView(urlString: qrURL)
                                .frame(width: 270, height: 270)
                                .opacity(viewModel.isScanned ? 0.3 : 1.0)
                            
                            // 已扫码遮罩
                            if viewModel.isScanned {
                                VStack(spacing: 12) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 60))
                                        .foregroundColor(.green)
                                    Text("已扫码")
                                        .font(.title2)
                                        .bold()
                                        .foregroundColor(.black)
                                }
                            }
                        } else {
                            // 过期遮罩
                            VStack(spacing: 14) {
                                Image(systemName: "exclamationmark.arrow.triangle.2.circlepath")
                                    .font(.system(size: 50))
                                    .foregroundColor(.orange)
                                Text("二维码已失效")
                                    .font(.headline)
                                    .foregroundColor(.black)
                            }
                        }
                    }
                    
                    // 状态提示文本
                    Text(viewModel.statusText)
                        .font(.headline)
                        .foregroundColor(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                    
                    // 刷新按钮 (绑定 tvOS 遥控器焦点)
                    Button(action: {
                        Task {
                            await viewModel.generateQRCode()
                        }
                    }) {
                        HStack(spacing: 10) {
                            Image(systemName: "arrow.clockwise")
                            Text("刷新二维码")
                        }
                        .font(.headline)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.glass)
                    .focused($isRefreshFocused)
                }
            }
            .padding(60)
        }
        .task {
            await viewModel.generateQRCode()
            isRefreshFocused = true
        }
        .onDisappear {
            viewModel.stopPolling()
        }
    }
}

struct InstructionRow: View {
    let number: String
    let text: String
    
    var body: some View {
        HStack(spacing: 16) {
            Text(number)
                .font(.system(size: 23, weight: .bold))
                .foregroundColor(.black)
                .frame(width: 38, height: 38)
                .background(Color.pink)
                .clipShape(Circle())
            
            Text(text)
                .font(.system(size: 23, weight: .medium))
                .foregroundColor(.white.opacity(0.9))
        }
    }
}

#Preview {
    LoginView()
}
