import UIKit

/// 文字弹幕渲染 cell (参照 ATV-Bilibili-demo 实现:黑色描边 + 实色填充)
final class DanmakuTextCell: DanmakuCell {
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
        guard let model = model as? DanmakuTextCellModel else { return }
        let text = NSString(string: model.text)

        context.setAlpha(model.opacity)
        context.setLineWidth(model.strokeWidth)
        context.setLineJoin(.round)

        // 透明度已通过 context.setAlpha 统一应用,描边颜色保持不透明,避免轮廓比填充更淡
        let strokeColor = #colorLiteral(red: 0.2, green: 0.2, blue: 0.2, alpha: 1.0)

        // 描边绘制
        context.saveGState()
        context.setTextDrawingMode(.stroke)
        context.setStrokeColor(strokeColor.cgColor)
        let strokeAttributes: [NSAttributedString.Key: Any] = [.font: model.font, .foregroundColor: strokeColor]
        text.draw(at: .zero, withAttributes: strokeAttributes)
        context.restoreGState()

        // 实色填充
        context.setTextDrawingMode(.fill)
        let fillAttributes: [NSAttributedString.Key: Any] = [.font: model.font, .foregroundColor: model.color]
        text.draw(at: .zero, withAttributes: fillAttributes)
    }

    override func didDisplay(_ finished: Bool) {}
}
