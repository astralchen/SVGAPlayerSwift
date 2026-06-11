import UIKit

/// 渲染 SVGA sprite 位图内容的 layer。
///
/// 位图资源本身不随帧变化；逐帧布局由父级 `SVGAContentLayer` 负责。
@MainActor
final class SVGABitmapLayer: CALayer {
    private let frames: [SVGA.VideoSpriteFrameEntity]

    init(frames: [SVGA.VideoSpriteFrameEntity]) {
        self.frames = frames
        super.init()
        backgroundColor = UIColor.clear.cgColor
        masksToBounds = false
        contentsGravity = .resizeAspect
    }

    override init(layer: Any) {
        self.frames = []
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) {
        self.frames = []
        super.init(coder: coder)
    }

    /// 更新位图 layer 到指定帧。
    ///
    /// 当前实现中位图内容是静态的，因此该方法不执行额外操作。
    ///
    /// - Parameter frame: 目标帧索引。
    func stepToFrame(_ frame: Int) {
        // 位图内容是静态的，逐帧布局由父级内容 layer 处理。
    }
}
