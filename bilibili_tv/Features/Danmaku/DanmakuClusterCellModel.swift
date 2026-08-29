import UIKit

/// Cluster(合并)弹幕数据模型:
/// - 主文本 `text(count)`:字号随计数缩放(cluster 语义,见 ClusterFontScaler)
/// - 计数部分 `(count)`:固定基础字号(不跟随缩放)
/// - 轨道类型固定 `.top`:水平居中显示,无左进右出滚动动画
final class DanmakuClusterCellModel: DanmakuCellModel, Equatable {
    var identifier: String = ""

    /// 主文本(原始内容)
    let text: String
    /// 窗口内弹幕总数
    let count: Int
    /// 主文本颜色(窗口首条颜色)
    let color: UIColor
    /// 主文本字号(缩放)
    let font: UIFont
    /// 计数部分字号(固定基础字号)
    let countFont: UIFont
    /// 弹幕整体透明度
    var opacity: CGFloat = 1.0
    /// 描边宽度
    var strokeWidth: CGFloat = 3.0

    /// 属性串缓存:主文本 run + 计数 run(同基线,计数不跟随缩放)
    lazy var attributedText: NSAttributedString = {
        let countText = "(\(count))"
        let attributed = NSMutableAttributedString(
            string: text + countText,
            attributes: [.font: font, .foregroundColor: color]
        )
        attributed.addAttributes(
            [.font: countFont],
            range: NSRange(location: text.count, length: countText.count)
        )
        return attributed
    }()

    var cellClass: DanmakuCell.Type {
        DanmakuClusterCell.self
    }

    var size: CGSize = .zero

    var track: UInt?

    var displayTime: Double = 6.0

    var type: DanmakuCellType = .top

    var isPause = false

    func calculateSize() {
        size =
            attributedText.boundingRect(
                with: CGSize(width: CGFloat(Float.infinity), height: 80),
                options: [.usesFontLeading, .usesLineFragmentOrigin],
                context: nil
            ).size
    }

    static func == (lhs: DanmakuClusterCellModel, rhs: DanmakuClusterCellModel) -> Bool {
        lhs.identifier == rhs.identifier
    }

    func isEqual(to cellModel: DanmakuCellModel) -> Bool {
        identifier == cellModel.identifier
    }

    /// - Parameters:
    ///   - fontSize: 主文本缩放字号
    ///   - countFontSize: 计数部分固定字号(基础字号)
    init(
        text: String,
        count: Int,
        color: UInt32,
        fontSize: CGFloat,
        countFontSize: CGFloat,
        displayTime: Double,
        opacity: CGFloat
    ) {
        self.text = text
        self.count = count
        self.color = UIColor(hex: color)
        self.font = UIFont.systemFont(ofSize: fontSize)
        self.countFont = UIFont.systemFont(ofSize: countFontSize)
        self.opacity = opacity
        self.displayTime = displayTime
        self.identifier = "cluster-\(text)-\(count)-\(color)"
        calculateSize()
    }
}
