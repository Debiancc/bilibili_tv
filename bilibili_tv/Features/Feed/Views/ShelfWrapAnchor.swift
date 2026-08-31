import SwiftUI

/// 横向 shelf 行尾的不可见「→ 回绕承接锚点」。
///
/// 行末卡片按 → 时,焦点引擎自然移到此处(卡片右方唯一候选),获焦后经
/// onGainedFocus 由行宿主把焦点写回首卡,完成「行尾 → 回行首」。
///
/// 复用 FeedContentScrollView「↑ 承接锚点」验证过的承接机制:按键由引擎
/// 自行消费完成移动,应用只在焦点落定后重锚,避免 onMoveCommand 非消费型
/// hook 与引擎同帧双写焦点的竞态(轮播回绕 0918af4 引入、1af423b 回退的
/// 历史回归)。
///
/// 布局中性:锚点自身宽度 + 行间距恰好被宿主行的
/// `.padding(.trailing, ShelfWrapAnchor.layoutCompensation)` 抵消,
/// 卡片绝对位置不变,不扰动快照基线。宿主行必须使用非懒 HStack ——
/// LazyHStack 回收离屏首卡后没有可写入焦点的节点。
struct ShelfWrapAnchor: View {
    /// 行间距约定:宿主 HStack 必须使用同一值,layoutCompensation 才能精确抵消
    static let rowSpacing: CGFloat = 25
    /// 锚点宽度:窄条即可承接行尾 →,同时保证有真实可命中矩形
    static let anchorWidth: CGFloat = 10
    /// 宿主行需要的负 trailing 补偿:-(锚点宽 + 行间距)
    static var layoutCompensation: CGFloat {
        -(anchorWidth + rowSpacing)
    }

    /// 与卡片等高,保证与卡片的水平方向检索带重合
    let height: CGFloat
    /// 关闭焦点注册时(快照渲染)锚点保留在层级中但不可聚焦
    var isFocusEnabled: Bool = true
    let onGainedFocus: () -> Void

    @FocusState private var isFocused: Bool

    /// 行回绕总开关:≥2 卡才有回绕语义;快照渲染禁用
    /// (与 hero/upAnchor 一致,不可见锚点会抢占 drawHierarchy 的确定性初始焦点)
    static func isRowWrapEnabled(itemCount: Int) -> Bool {
        #if DEBUG
        return itemCount > 1 && !ContentView.isSnapshotTesting
        #else
        return itemCount > 1
        #endif
    }

    var body: some View {
        Color.clear
            .frame(width: Self.anchorWidth, height: height)
            .focusable(isFocusEnabled)
            .focused($isFocused)
            .onChange(of: isFocused) { _, focused in
                guard focused else { return }
                onGainedFocus()
            }
            .accessibilityHidden(true)
    }
}
