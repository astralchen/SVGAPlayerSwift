import UIKit

@MainActor
final class SVGAVectorLayer: CALayer {
    private let frames: [SVGAVideoSpriteFrameEntity]
    private var drawnFrame: Int = -1
    private var keepFrameCache: [Int: Int] = [:]

    init(frames: [SVGAVideoSpriteFrameEntity]) {
        self.frames = frames
        super.init()
        backgroundColor = UIColor.clear.cgColor
        masksToBounds = false
        buildKeepFrameCache()
        stepToFrame(0)
    }

    override init(layer: Any) {
        self.frames = []
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) {
        self.frames = []
        super.init(coder: coder)
    }

    // MARK: - Keep-frame cache

    private func buildKeepFrameCache() {
        var lastNonKeepFrame = 0
        var cache: [Int: Int] = [:]
        for (idx, frameItem) in frames.enumerated() {
            if frameItem.shapes.first?.type != .keep {
                lastNonKeepFrame = idx
            } else {
                cache[idx] = lastNonKeepFrame
            }
        }
        keepFrameCache = cache
    }

    // MARK: - Step

    func stepToFrame(_ frame: Int) {
        guard frame >= 0, frame < frames.count else { return }
        let frameItem = frames[frame]
        if frameItem.shapes.first?.type == .keep {
            let target = keepFrameCache[frame] ?? frame
            if drawnFrame == target { return }
        }
        sublayers?.forEach { $0.removeFromSuperlayer() }
        for shape in frameItem.shapes {
            if let layer = makeShapeLayer(shape) {
                addSublayer(layer)
            }
        }
        drawnFrame = frame
    }

    // MARK: - Shape rendering

    private func makeShapeLayer(_ shape: SVGAShapeEntity) -> CAShapeLayer? {
        switch shape.type {
        case .keep:
            return nil
        case .shape:
            return makeCurveLayer(shape)
        case .ellipse:
            return makeEllipseLayer(shape)
        case .rect:
            return makeRectLayer(shape)
        }
    }

    private func makeCurveLayer(_ shape: SVGAShapeEntity) -> CAShapeLayer {
        let bezier = SVGABezierPath()
        if case .shape(let d) = shape.args {
            bezier.setValues(d)
        }
        let sl = bezier.createLayer()
        applyStyles(sl, styles: shape.styles)
        applyTransform(sl, transform: shape.transform)
        return sl
    }

    private func makeEllipseLayer(_ shape: SVGAShapeEntity) -> CAShapeLayer {
        let sl = CAShapeLayer()
        if case .ellipse(let cx, let cy, let rx, let ry) = shape.args {
            sl.path = UIBezierPath(ovalIn: CGRect(x: cx - rx, y: cy - ry,
                                                   width: rx * 2, height: ry * 2)).cgPath
        }
        applyStyles(sl, styles: shape.styles)
        applyTransform(sl, transform: shape.transform)
        return sl
    }

    private func makeRectLayer(_ shape: SVGAShapeEntity) -> CAShapeLayer {
        let sl = CAShapeLayer()
        if case .rect(let x, let y, let w, let h, let cr) = shape.args {
            let rect = CGRect(x: x, y: y, width: w, height: h)
            sl.path = (cr > 0 ? UIBezierPath(roundedRect: rect, cornerRadius: cr)
                               : UIBezierPath(rect: rect)).cgPath
        }
        applyStyles(sl, styles: shape.styles)
        applyTransform(sl, transform: shape.transform)
        return sl
    }

    // MARK: - Styles & Transform

    private func applyStyles(_ sl: CAShapeLayer, styles: SVGAShapeEntity.Styles?) {
        sl.masksToBounds = false
        sl.backgroundColor = UIColor.clear.cgColor
        guard let s = styles else {
            sl.fillColor = UIColor.clear.cgColor
            return
        }
        sl.fillColor = s.fill?.cgColor ?? UIColor.clear.cgColor
        sl.strokeColor = s.stroke?.cgColor
        sl.lineWidth = s.strokeWidth
        sl.lineCap = s.lineCap
        sl.lineJoin = s.lineJoin
        sl.miterLimit = s.miterLimit
        if let ld = s.lineDash {
            sl.lineDashPhase = ld.phase
            sl.lineDashPattern = [NSNumber(value: Double(ld.dash)),
                                  NSNumber(value: Double(ld.gap))]
        }
    }

    private func applyTransform(_ sl: CAShapeLayer, transform: CGAffineTransform?) {
        guard let t = transform else { return }
        sl.transform = CATransform3DMakeAffineTransform(t)
    }
}
