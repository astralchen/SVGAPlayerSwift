import UIKit

@MainActor
final class SVGAVectorLayer: CALayer {
    private let frames: [SVGAVideoSpriteFrameEntity]
    private var drawedFrame: Int = -1
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

    // MARK: Keep-frame cache

    private func buildKeepFrameCache() {
        var lastKeep = 0
        var cache: [Int: Int] = [:]
        for (idx, frameItem) in frames.enumerated() {
            if !isKeepFrame(frameItem) {
                lastKeep = idx
            } else {
                cache[idx] = lastKeep
            }
        }
        keepFrameCache = cache
    }

    private func isKeepFrame(_ frameItem: SVGAVideoSpriteFrameEntity) -> Bool {
        guard !frameItem.shapes.isEmpty else { return false }
        if let dict = frameItem.shapes.first as? [String: Any] {
            return (dict["type"] as? String) == "keep"
        }
        if let shape = frameItem.shapes.first as? Svga_ShapeEntity {
            return shape.type == .keep
        }
        return false
    }

    // MARK: Step

    func stepToFrame(_ frame: Int) {
        guard frame < frames.count else { return }
        drawFrame(frame)
    }

    private func drawFrame(_ frame: Int) {
        let frameItem = frames[frame]
        if isKeepFrame(frameItem) {
            let target = keepFrameCache[frame] ?? frame
            if drawedFrame == target { return }
        }
        sublayers?.forEach { $0.removeFromSuperlayer() }
        for shape in frameItem.shapes {
            if let dict = shape as? [String: Any] {
                drawJSONShape(dict)
            } else if let proto = shape as? Svga_ShapeEntity {
                drawProtoShape(proto)
            }
        }
        drawedFrame = frame
    }

    // MARK: JSON shape drawing

    private func drawJSONShape(_ shape: [String: Any]) {
        guard let type = shape["type"] as? String else { return }
        switch type {
        case "shape":
            let layer = makeJSONCurveLayer(shape)
            addSublayer(layer)
        case "ellipse":
            let layer = makeJSONEllipseLayer(shape)
            addSublayer(layer)
        case "rect":
            let layer = makeJSONRectLayer(shape)
            addSublayer(layer)
        default: break
        }
    }

    private func makeJSONCurveLayer(_ shape: [String: Any]) -> CAShapeLayer {
        let bezier = SVGABezierPath()
        if let args = shape["args"] as? [String: Any], let d = args["d"] as? String {
            bezier.setValues(d)
        }
        let sl = bezier.createLayer()
        applyJSONStyles(sl, shape: shape)
        applyJSONTransform(sl, shape: shape)
        return sl
    }

    private func makeJSONEllipseLayer(_ shape: [String: Any]) -> CAShapeLayer {
        var path: UIBezierPath?
        if let args = shape["args"] as? [String: Any],
           let x = args["x"] as? NSNumber, let y = args["y"] as? NSNumber,
           let rx = args["radiusX"] as? NSNumber, let ry = args["radiusY"] as? NSNumber {
            let cx = CGFloat(x.floatValue), cy = CGFloat(y.floatValue)
            let rxv = CGFloat(rx.floatValue), ryv = CGFloat(ry.floatValue)
            path = UIBezierPath(ovalIn: CGRect(x: cx - rxv, y: cy - ryv,
                                               width: rxv * 2, height: ryv * 2))
        }
        let sl = CAShapeLayer()
        sl.path = path?.cgPath
        applyJSONStyles(sl, shape: shape)
        applyJSONTransform(sl, shape: shape)
        return sl
    }

    private func makeJSONRectLayer(_ shape: [String: Any]) -> CAShapeLayer {
        var path: UIBezierPath?
        if let args = shape["args"] as? [String: Any],
           let x = args["x"] as? NSNumber, let y = args["y"] as? NSNumber,
           let w = args["width"] as? NSNumber, let h = args["height"] as? NSNumber {
            let cr = (args["cornerRadius"] as? NSNumber).map { CGFloat($0.floatValue) } ?? 0
            let rect = CGRect(x: CGFloat(x.floatValue), y: CGFloat(y.floatValue),
                              width: CGFloat(w.floatValue), height: CGFloat(h.floatValue))
            path = cr > 0 ? UIBezierPath(roundedRect: rect, cornerRadius: cr)
                          : UIBezierPath(rect: rect)
        }
        let sl = CAShapeLayer()
        sl.path = path?.cgPath
        applyJSONStyles(sl, shape: shape)
        applyJSONTransform(sl, shape: shape)
        return sl
    }

    private func applyJSONStyles(_ sl: CAShapeLayer, shape: [String: Any]) {
        sl.masksToBounds = false
        sl.backgroundColor = UIColor.clear.cgColor
        guard let styles = shape["styles"] as? [String: Any] else {
            sl.fillColor = UIColor.clear.cgColor; return
        }
        if let fill = styles["fill"] as? [NSNumber], fill.count == 4 {
            sl.fillColor = UIColor(red: CGFloat(fill[0].floatValue), green: CGFloat(fill[1].floatValue),
                                   blue: CGFloat(fill[2].floatValue), alpha: CGFloat(fill[3].floatValue)).cgColor
        } else {
            sl.fillColor = UIColor.clear.cgColor
        }
        if let stroke = styles["stroke"] as? [NSNumber], stroke.count == 4 {
            sl.strokeColor = UIColor(red: CGFloat(stroke[0].floatValue), green: CGFloat(stroke[1].floatValue),
                                     blue: CGFloat(stroke[2].floatValue), alpha: CGFloat(stroke[3].floatValue)).cgColor
        }
        if let sw = styles["strokeWidth"] as? NSNumber { sl.lineWidth = CGFloat(sw.floatValue) }
        if let lc = styles["lineCap"] as? String { sl.lineCap = CAShapeLayerLineCap(rawValue: lc) }
        if let lj = styles["lineJoin"] as? String { sl.lineJoin = CAShapeLayerLineJoin(rawValue: lj) }
        if let ml = styles["miterLimit"] as? NSNumber { sl.miterLimit = CGFloat(ml.floatValue) }
        if let ld = styles["lineDash"] as? [NSNumber], ld.count == 3 {
            sl.lineDashPhase = CGFloat(ld[2].floatValue)
            let d0 = CGFloat(ld[0].floatValue) < 1.0 ? 1.0 : CGFloat(ld[0].floatValue)
            let d1 = CGFloat(ld[1].floatValue) < 0.1 ? 0.1 : CGFloat(ld[1].floatValue)
            sl.lineDashPattern = [NSNumber(value: d0), NSNumber(value: d1)]
        }
    }

    private func applyJSONTransform(_ sl: CAShapeLayer, shape: [String: Any]) {
        guard let t = shape["transform"] as? [String: Any],
              let a = t["a"] as? NSNumber, let b = t["b"] as? NSNumber,
              let c = t["c"] as? NSNumber, let d = t["d"] as? NSNumber,
              let tx = t["tx"] as? NSNumber, let ty = t["ty"] as? NSNumber else { return }
        sl.transform = CATransform3DMakeAffineTransform(
            CGAffineTransform(a: CGFloat(a.floatValue), b: CGFloat(b.floatValue),
                              c: CGFloat(c.floatValue), d: CGFloat(d.floatValue),
                              tx: CGFloat(tx.floatValue), ty: CGFloat(ty.floatValue)))
    }

    // MARK: Proto shape drawing

    private func drawProtoShape(_ shape: Svga_ShapeEntity) {
        switch shape.type {
        case .shape:
            addSublayer(makeProtoCurveLayer(shape))
        case .ellipse:
            addSublayer(makeProtoEllipseLayer(shape))
        case .rect:
            addSublayer(makeProtoRectLayer(shape))
        default: break
        }
    }

    private func makeProtoCurveLayer(_ shape: Svga_ShapeEntity) -> CAShapeLayer {
        let bezier = SVGABezierPath()
        if case .shape(let v)? = shape.args, !v.d.isEmpty {
            bezier.setValues(v.d)
        }
        let sl = bezier.createLayer()
        applyProtoStyles(sl, shape: shape)
        applyProtoTransform(sl, shape: shape)
        return sl
    }

    private func makeProtoEllipseLayer(_ shape: Svga_ShapeEntity) -> CAShapeLayer {
        var path: UIBezierPath?
        if case .ellipse(let e)? = shape.args {
            let cx = CGFloat(e.cx), cy = CGFloat(e.cy)
            let rx = CGFloat(e.rx), ry = CGFloat(e.ry)
            path = UIBezierPath(ovalIn: CGRect(x: cx - rx, y: cy - ry,
                                               width: rx * 2, height: ry * 2))
        }
        let sl = CAShapeLayer()
        sl.path = path?.cgPath
        applyProtoStyles(sl, shape: shape)
        applyProtoTransform(sl, shape: shape)
        return sl
    }

    private func makeProtoRectLayer(_ shape: Svga_ShapeEntity) -> CAShapeLayer {
        var path: UIBezierPath?
        if case .rect(let r)? = shape.args {
            let rect = CGRect(x: CGFloat(r.x), y: CGFloat(r.y),
                              width: CGFloat(r.width), height: CGFloat(r.height))
            let cr = CGFloat(r.cornerRadius)
            path = cr > 0 ? UIBezierPath(roundedRect: rect, cornerRadius: cr)
                          : UIBezierPath(rect: rect)
        }
        let sl = CAShapeLayer()
        sl.path = path?.cgPath
        applyProtoStyles(sl, shape: shape)
        applyProtoTransform(sl, shape: shape)
        return sl
    }

    private func applyProtoStyles(_ sl: CAShapeLayer, shape: Svga_ShapeEntity) {
        sl.masksToBounds = false
        sl.backgroundColor = UIColor.clear.cgColor
        guard shape.hasStyle else { sl.fillColor = UIColor.clear.cgColor; return }
        let s = shape.style
        if s.hasFill {
            sl.fillColor = UIColor(red: CGFloat(s.fill.r), green: CGFloat(s.fill.g),
                                   blue: CGFloat(s.fill.b), alpha: CGFloat(s.fill.a)).cgColor
        } else {
            sl.fillColor = UIColor.clear.cgColor
        }
        if s.hasStroke {
            sl.strokeColor = UIColor(red: CGFloat(s.stroke.r), green: CGFloat(s.stroke.g),
                                     blue: CGFloat(s.stroke.b), alpha: CGFloat(s.stroke.a)).cgColor
        }
        sl.lineWidth = CGFloat(s.strokeWidth)
        switch s.lineCap {
        case .round:  sl.lineCap = .round
        case .square: sl.lineCap = .square
        default:      sl.lineCap = .butt
        }
        switch s.lineJoin {
        case .round: sl.lineJoin = .round
        case .bevel: sl.lineJoin = .bevel
        default:     sl.lineJoin = .miter
        }
        sl.miterLimit = CGFloat(s.miterLimit)
        // Only apply dash pattern when the encoder explicitly set lineDashI > 0.
        // Proto3 defaults lineDashI/II to 0 ("no dash"); clamping then checking
        // the clamped value would always be true and apply dashes to every shape.
        if s.lineDashI > 0 {
            let d0 = s.lineDashI < 1.0 ? Float(1.0) : s.lineDashI
            let d1 = s.lineDashIi < 0.1 ? Float(0.1) : s.lineDashIi
            sl.lineDashPhase = CGFloat(s.lineDashIii)
            sl.lineDashPattern = [NSNumber(value: d0), NSNumber(value: d1)]
        }
    }

    private func applyProtoTransform(_ sl: CAShapeLayer, shape: Svga_ShapeEntity) {
        guard shape.hasTransform else { return }
        let t = shape.transform
        sl.transform = CATransform3DMakeAffineTransform(
            CGAffineTransform(a: CGFloat(t.a), b: CGFloat(t.b),
                              c: CGFloat(t.c), d: CGFloat(t.d),
                              tx: CGFloat(t.tx), ty: CGFloat(t.ty)))
    }
}
