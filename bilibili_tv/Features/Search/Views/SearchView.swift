import SwiftUI

/// 搜索页：顶部搜索框 + 状态分发（历史 / 加载 / 结果 / 失败）。
/// 结果合并为单一列表复用 ShelfView 横向卡片布局，点击经环境 coordinator 直达详情页。
struct SearchView: View {
    @State private var viewModel = SearchViewModel()
    /// 搜索框焦点（初始聚焦，tvOS 自动弹系统键盘）
    @FocusState private var isSearchFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 40) {
            searchField

            switch viewModel.state {
            case .idle:
                emptyHint
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 80)
            case .loaded:
                resultSections
            case .failed(let message):
                SearchErrorView(message: message) {
                    Task { await viewModel.submit(keyword: viewModel.keyword) }
                }
            }
        }
        .padding(.top, 60)
        .padding(.horizontal, 50)
        .onAppear {
            isSearchFieldFocused = true
        }
        .onChange(of: viewModel.keyword) { _, newValue in
            // 清空输入框 → 复位到初始态,避免残留上一次的结果
            if newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                viewModel.reset()
            }
        }
    }

    /// 搜索输入框（tvOS 系统键盘「下一步」/ Return 触发 onSubmit 搜索）
    /// 无方形背景：聚焦时由系统 TextField 自身提供圆角高亮
    private var searchField: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("搜索电影、番剧", text: $viewModel.keyword)
                .textFieldStyle(.plain)
                .font(.body)
                .focused($isSearchFieldFocused)
                .onSubmit {
                    Task { await viewModel.submit(keyword: viewModel.keyword) }
                }
        }
        .padding(.horizontal, 24)
        .frame(height: 64)
    }

    /// 初始态：空提示（无搜索历史/推荐词，直接引导输入）
    private var emptyHint: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("输入关键字搜索电影与番剧")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 120)
    }

    /// 结果态：全部分组合并为单一横向 shelf
    @ViewBuilder
    private var resultSections: some View {
        let results = viewModel.allResults
        if results.isEmpty {
            Text("未找到相关影视内容")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.top, 80)
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 60) {
                    ShelfView(title: "搜索结果", items: results, ownerTab: .search)
                }
                .padding(.vertical, 8)
            }
        }
    }
}

/// 搜索失败态：错误信息 + 重试
private struct SearchErrorView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 44))
                .foregroundStyle(.orange)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("重试", action: onRetry)
                .buttonStyle(.glass)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 100)
    }
}

#Preview {
    SearchView()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
}
