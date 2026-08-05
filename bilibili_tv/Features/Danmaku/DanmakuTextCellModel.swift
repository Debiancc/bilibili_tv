import UIKit

/// 文字弹幕数据模型 (参照 ATV-Bilibili-demo 实现,去除 Settings 全局依赖,样式参数由外部注入)
final class DanmakuTextCellModel: DanmakuCellModel, Equatable {
    var identifier: String = ""

    var text = ""
    var color: UIColor = .white
    var font = UIFont.systemFont(ofSize: 25)
    /// 弹幕整体透明度 0.3~1.0
    var opacity: CGFloat = 1.0
    /// 描边宽度
    var strokeWidth: CGFloat = 3.0

    var cellClass: DanmakuCell.Type {
        return DanmakuTextCell.self
    }

    var size: CGSize = .zero

    var track: UInt?

    var displayTime: Double = 6.0

    var type: DanmakuCellType = .floating

    var isPause = false

    func calculateSize() {
        size = NSString(string: text)
            .boundingRect(
                with: CGSize(width: CGFloat(Float.infinity), height: 40),
                options: [.usesFontLeading, .usesLineFragmentOrigin],
                attributes: [.font: font],
                context: nil
            ).size
    }

    static func == (lhs: DanmakuTextCellModel, rhs: DanmakuTextCellModel) -> Bool {
        return lhs.identifier == rhs.identifier
    }

    func isEqual(to cellModel: DanmakuCellModel) -> Bool {
        return identifier == cellModel.identifier
    }

    /// 根据弹幕 mode 映射轨道类型:4=底部,5=顶部,其余=滚动
    init(text: String, mode: Int32, color: UInt32, fontSize: CGFloat, displayTime: Double, opacity: CGFloat) {
        self.text = text
        self.color = UIColor(hex: color)
        self.font = UIFont.systemFont(ofSize: fontSize)
        self.opacity = opacity
        self.displayTime = displayTime
        self.identifier = "\(text)-\(color)-\(mode)"

        switch mode {
        case 4:
            type = .bottom
        case 5:
            type = .top
        default:
            type = .floating
        }

        calculateSize()
    }
}

extension UIColor {
    /// 从 B 站弹幕 ARGB 色值解析颜色 (0xFFFFFF = 白)
    convenience init(hex: UInt32) {
        let red = CGFloat((hex >> 16) & 0xFF) / 255.0
        let green = CGFloat((hex >> 8) & 0xFF) / 255.0
        let blue = CGFloat(hex & 0xFF) / 255.0
        self.init(red: red, green: green, blue: blue, alpha: 1.0)
    }
}
