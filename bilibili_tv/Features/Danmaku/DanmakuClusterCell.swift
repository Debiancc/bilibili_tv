import UIKit

/// Cluster(合并)弹幕渲染 cell:仿 DanmakuTextCell 的黑描边 + 实色填充两遍绘制,
/// 但内容为属性串(主文本缩放字号 + 计数固定字号)。
final class DanmakuClusterCell: DanmakuCell {
    required init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func willDisplay() {}

    override func displaying(_ context: CGContext, _ size: CGSize, _ isCancelled: Bool) {
        guard let model = model as? DanmakuClusterCellModel else { return }

        context.setAlpha(model.opacity)
        context.setLineWidth(model.strokeWidth)
        context.setLineJoin(.round)

        // 透明度已通过 context.setAlpha 统一应用,描边颜色保持不透明,避免轮廓比填充更淡
        let strokeColor = #colorLiteral(red: 0.2, green: 0.2, blue: 0.2, alpha: 1.0)

        // 描边绘制:属性串副本替换前景色为描边色
        context.saveGState()
        context.setTextDrawingMode(.stroke)
        context.setStrokeColor(strokeColor.cgColor)
        let strokeAttributed = model.attributedText.mutableCopy() as? NSMutableAttributedString
        strokeAttributed?.addAttribute(
            .foregroundColor,
            value: strokeColor,
            range: NSRange(location: 0, length: model.attributedText.length)
        )
        (strokeAttributed ?? model.attributedText).draw(at: .zero)
        context.restoreGState()

        // 实色填充
        context.setTextDrawingMode(.fill)
        model.attributedText.draw(at: .zero)
    }

    override func didDisplay(_ finished: Bool) {}
}
