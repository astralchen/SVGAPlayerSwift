import UIKit

/// 渲染单个 SVGA sprite 的容器 layer。
///
/// `SVGAContentLayer` 负责按帧应用布局、透明度、变换和裁剪，并承载
/// 位图 layer、矢量 layer、文本 layer 以及自定义绘制回调。
@MainActor
final class SVGAContentLayer: CALayer {
    /// sprite 引用的图片资源 key。
    let imageKey: String

    /// 一个布尔值，指示动态内容是否隐藏该 sprite。
    var dynamicHidden: Bool = false {
        didSet { isHidden = dynamicHidden }
    }

    /// 当前帧布局完成后执行的自定义绘制回调。
    var dynamicDrawingBlock: SVGADynamicDrawingBlock?

    /// 渲染 sprite 位图内容的子 layer。
    var bitmapLayer: SVGABitmapLayer? {
        didSet {
            oldValue?.removeFromSuperlayer()
            if let l = bitmapLayer { addSublayer(l) }
        }
    }

    /// 渲染 sprite 矢量内容的子 layer。
    var vectorLayer: SVGAVectorLayer? {
        didSet {
            oldValue?.removeFromSuperlayer()
            if let l = vectorLayer { addSublayer(l) }
        }
    }

    /// 叠加显示动态富文本的子 layer。
    var textLayer: CATextLayer?

    private let frames: [SVGA.VideoSpriteFrameEntity]
    private var textLayerAlignment: NSTextAlignment = .center
    private var lastClipPath: CGPath?

    init(frames: [SVGA.VideoSpriteFrameEntity], imageKey: String = "") {
        self.frames = frames
        self.imageKey = imageKey
        super.init()
        backgroundColor = UIColor.clear.cgColor
        masksToBounds = false
        stepToFrame(0)
    }

    override init(layer: Any) {
        self.frames = []
        self.imageKey = ""
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) {
        self.frames = []
        self.imageKey = ""
        super.init(coder: coder)
    }

    // MARK: Step

    /// 更新 layer 到指定帧。
    ///
    /// - Parameter frame: 目标帧索引。
    func stepToFrame(_ frame: Int) {
        guard !dynamicHidden, frame >= 0, frame < frames.count else { return }
        let frameItem = frames[frame]
        if frameItem.alpha > 0 {
            isHidden = false
            opacity = Float(frameItem.alpha)
            position = .zero
            transform = CATransform3DIdentity
            self.frame = frameItem.layout
            transform = CATransform3DMakeAffineTransform(frameItem.transform)
            let offsetX = self.frame.origin.x - frameItem.nx
            let offsetY = self.frame.origin.y - frameItem.ny
            position = CGPoint(x: position.x - offsetX, y: position.y - offsetY)
            if let maskSrc = frameItem.maskLayer as? CAShapeLayer {
                if lastClipPath != maskSrc.path {
                    let clone = CAShapeLayer()
                    clone.path = maskSrc.path
                    clone.fillColor = maskSrc.fillColor
                    mask = clone
                    lastClipPath = maskSrc.path
                }
            } else if mask != nil {
                mask = nil
                lastClipPath = nil
            }
            bitmapLayer?.frame = bounds
            vectorLayer?.frame = bounds
            layoutTextLayer()
            bitmapLayer?.stepToFrame(frame)
            vectorLayer?.stepToFrame(frame)
        } else {
            isHidden = true
        }
        dynamicDrawingBlock?(self, frame)
    }

    // MARK: Text layout

    /// 根据当前内容 bounds 和段落对齐方式更新文本 layer 位置。
    private func layoutTextLayer() {
        guard let tl = textLayer else { return }
        var f = tl.frame
        switch textLayerAlignment {
        case .left:   f.origin.x = 0
        case .right:  f.origin.x = frame.size.width - tl.frame.size.width
        default:      f.origin.x = (frame.size.width - tl.frame.size.width) / 2
        }
        f.origin.y = (frame.size.height - tl.frame.size.height) / 2
        tl.frame = f
    }

    // MARK: Text layer

    /// 设置或移除动态位图图片。
    ///
    /// - Parameter image: 要显示的图片。传入 `nil` 时移除位图 layer。
    func setBitmapImage(_ image: UIImage?) {
        guard let image else {
            bitmapLayer = nil
            return
        }
        if let bitmapLayer {
            bitmapLayer.contents = image.cgImage
            bitmapLayer.frame = bounds
        } else {
            let layer = SVGABitmapLayer(frames: frames)
            layer.contents = image.cgImage
            layer.frame = bounds
            bitmapLayer = layer
        }
    }

    /// 重建动态文本 layer。
    ///
    /// - Parameter attributedString: 要叠加显示的富文本。
    func resetTextLayer(_ attributedString: NSAttributedString) {
        textLayer?.removeFromSuperlayer()
        let tl = CATextLayer()
        tl.contentsScale = UIScreen.main.scale
        tl.string = attributedString
        tl.frame = CGRect(origin: .zero, size: attributedString.boundingRect(
            with: CGSize(width: CGFloat.greatestFiniteMagnitude,
                         height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil).size)
        applyTextLayerProperties(tl, attributedString: attributedString)
        addSublayer(tl)
        textLayer = tl
        layoutTextLayer()
    }

    /// 移除动态文本 layer。
    func removeTextLayer() {
        textLayer?.removeFromSuperlayer()
        textLayer = nil
    }

    private func applyTextLayerProperties(_ tl: CATextLayer, attributedString: NSAttributedString) {
        guard attributedString.length > 0 else { return }
        let attrs = attributedString.attributes(at: 0, effectiveRange: nil)
        guard let para = attrs[.paragraphStyle] as? NSParagraphStyle else { return }
        switch para.lineBreakMode {
        case .byTruncatingTail:
            tl.truncationMode = .end; tl.isWrapped = false
        case .byTruncatingMiddle:
            tl.truncationMode = .middle; tl.isWrapped = false
        case .byTruncatingHead:
            tl.truncationMode = .start; tl.isWrapped = false
        default:
            tl.truncationMode = .none; tl.isWrapped = true
        }
        textLayerAlignment = para.alignment == .natural ? .center : para.alignment
    }
}
