import UIKit

/// 渲染 SVGA sprite 矢量形状的 layer。
///
/// 每次帧变化时，`SVGAVectorLayer` 会根据当前帧的 `ShapeEntity`
/// 生成对应的 `CAShapeLayer` 子层。
@MainActor
final class SVGAVectorLayer: CALayer {
    private let frames: [SVGA.VideoSpriteFrameEntity]
    private var drawnFrame: Int = -1
    private var keepFrameCache: [Int: Int] = [:]

    init(frames: [SVGA.VideoSpriteFrameEntity]) {
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

    /// 构建 keep 帧到最近非 keep 帧的映射。
    ///
    /// SVGA 的 keep 帧表示复用上一帧矢量内容。缓存映射可以避免重复构建
    /// 相同的矢量 layer。
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

    /// 更新矢量内容到指定帧。
    ///
    /// - Parameter frame: 目标帧索引。
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

    /// 创建给定形状对应的 shape layer。
    ///
    /// - Parameter shape: 要渲染的形状。
    /// - Returns: 配置完成的 shape layer。keep 帧返回 `nil`。
    private func makeShapeLayer(_ shape: SVGA.ShapeEntity) -> CAShapeLayer? {
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

    private func makeCurveLayer(_ shape: SVGA.ShapeEntity) -> CAShapeLayer {
        let bezier = SVGABezierPath()
        if case .shape(let d) = shape.args {
            bezier.setValues(d)
        }
        let sl = bezier.createLayer()
        applyStyles(sl, styles: shape.styles)
        applyTransform(sl, transform: shape.transform)
        return sl
    }

    private func makeEllipseLayer(_ shape: SVGA.ShapeEntity) -> CAShapeLayer {
        let sl = CAShapeLayer()
        if case .ellipse(let cx, let cy, let rx, let ry) = shape.args {
            sl.path = UIBezierPath(ovalIn: CGRect(x: cx - rx, y: cy - ry,
                                                   width: rx * 2, height: ry * 2)).cgPath
        }
        applyStyles(sl, styles: shape.styles)
        applyTransform(sl, transform: shape.transform)
        return sl
    }

    private func makeRectLayer(_ shape: SVGA.ShapeEntity) -> CAShapeLayer {
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

    /// 应用填充、描边和线条样式。
    private func applyStyles(_ sl: CAShapeLayer, styles: SVGA.ShapeEntity.Styles?) {
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

    /// 应用形状自身的仿射变换。
    private func applyTransform(_ sl: CAShapeLayer, transform: CGAffineTransform?) {
        guard let t = transform else { return }
        sl.transform = CATransform3DMakeAffineTransform(t)
    }
}
