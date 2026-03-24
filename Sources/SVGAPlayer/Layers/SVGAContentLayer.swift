import UIKit

@MainActor
final class SVGAContentLayer: CALayer {
    let imageKey: String
    var dynamicHidden: Bool = false {
        didSet { isHidden = dynamicHidden }
    }
    var dynamicDrawingBlock: SVGAPlayerDynamicDrawingBlock?

    nonisolated(unsafe) var bitmapLayer: SVGABitmapLayer? {
        didSet {
            oldValue?.removeFromSuperlayer()
            if let l = bitmapLayer { addSublayer(l) }
        }
    }
    nonisolated(unsafe) var vectorLayer: SVGAVectorLayer? {
        didSet {
            oldValue?.removeFromSuperlayer()
            if let l = vectorLayer { addSublayer(l) }
        }
    }
    nonisolated(unsafe) var textLayer: CATextLayer?

    private let frames: [SVGAVideoSpriteFrameEntity]
    nonisolated(unsafe) private var textLayerAlignment: NSTextAlignment = .center

    init(frames: [SVGAVideoSpriteFrameEntity], imageKey: String = "") {
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

    private var _firstVisible = true

    func stepToFrame(_ frame: Int) {
        guard !dynamicHidden, frame < frames.count else { return }
        let frameItem = frames[frame]
        if frameItem.alpha > 0 {
            if _firstVisible {
                _firstVisible = false
                print("[SVGAStep] first visible frame=\(frame) imageKey=\(imageKey) layout=\(frameItem.layout) alpha=\(frameItem.alpha) transform=\(frameItem.transform) nx=\(frameItem.nx) ny=\(frameItem.ny) bitmapLayer=\(bitmapLayer != nil)")
            }
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
                let clone = CAShapeLayer()
                clone.path = maskSrc.path
                clone.fillColor = maskSrc.fillColor
                mask = clone
            } else {
                mask = nil
            }
            bitmapLayer?.stepToFrame(frame)
            vectorLayer?.stepToFrame(frame)
        } else {
            isHidden = true
        }
        dynamicDrawingBlock?(self, frame)
    }

    // MARK: Frame override (text layer alignment)

    override var frame: CGRect {
        didSet {
            bitmapLayer?.frame = bounds
            vectorLayer?.frame = bounds
            layoutTextLayer()
        }
    }

    nonisolated private func layoutTextLayer() {
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
