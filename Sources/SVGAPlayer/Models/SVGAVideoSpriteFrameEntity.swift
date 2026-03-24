import UIKit

public final class SVGAVideoSpriteFrameEntity: @unchecked Sendable {
    public let alpha: CGFloat
    public let layout: CGRect
    public let transform: CGAffineTransform
    public let nx: CGFloat
    public let ny: CGFloat
    public let clipPath: String?
    public let shapes: [Any]

    private var _maskLayer: CALayer?
    private let maskLock = NSLock()

    public var maskLayer: CALayer? {
        maskLock.lock()
        defer { maskLock.unlock() }
        if _maskLayer == nil, let path = clipPath, !path.isEmpty {
            let bezier = SVGABezierPath()
            bezier.setValues(path)
            _maskLayer = bezier.createLayer()
        }
        return _maskLayer
    }

    // MARK: Proto init

    init(protoObject: Svga_FrameEntity) {
        alpha = CGFloat(protoObject.alpha)
        let l = protoObject.layout
        layout = CGRect(x: CGFloat(l.x), y: CGFloat(l.y),
                        width: CGFloat(l.width), height: CGFloat(l.height))
        let t = protoObject.transform
        // Proto3 default: unset transform has all fields = 0, which is a degenerate (zero-scale)
        // matrix — treat it as identity to avoid collapsing the layer to zero size.
        if t.a == 0 && t.b == 0 && t.c == 0 && t.d == 0 {
            transform = .identity
        } else {
            transform = CGAffineTransform(a: CGFloat(t.a), b: CGFloat(t.b),
                                          c: CGFloat(t.c), d: CGFloat(t.d),
                                          tx: CGFloat(t.tx), ty: CGFloat(t.ty))
        }
        clipPath = protoObject.clipPath.isEmpty ? nil : protoObject.clipPath
        shapes = protoObject.shapes
        (nx, ny) = Self.computeNXNY(transform: transform, layout: layout)
    }

    // MARK: JSON init (1.x)

    init(jsonObject: [String: Any]) {
        alpha = (jsonObject["alpha"] as? NSNumber).map { CGFloat($0.floatValue) } ?? 0

        if let l = jsonObject["layout"] as? [String: Any],
           let x = l["x"] as? NSNumber, let y = l["y"] as? NSNumber,
           let w = l["width"] as? NSNumber, let h = l["height"] as? NSNumber {
            layout = CGRect(x: CGFloat(x.floatValue), y: CGFloat(y.floatValue),
                            width: CGFloat(w.floatValue), height: CGFloat(h.floatValue))
        } else {
            layout = .zero
        }

        if let t = jsonObject["transform"] as? [String: Any],
           let a = t["a"] as? NSNumber, let b = t["b"] as? NSNumber,
           let c = t["c"] as? NSNumber, let d = t["d"] as? NSNumber,
           let tx = t["tx"] as? NSNumber, let ty = t["ty"] as? NSNumber {
            transform = CGAffineTransform(a: CGFloat(a.floatValue), b: CGFloat(b.floatValue),
                                          c: CGFloat(c.floatValue), d: CGFloat(d.floatValue),
                                          tx: CGFloat(tx.floatValue), ty: CGFloat(ty.floatValue))
        } else {
            transform = .identity
        }

        let cp = jsonObject["clipPath"] as? String
        clipPath = (cp?.isEmpty == false) ? cp : nil
        shapes = (jsonObject["shapes"] as? [Any]) ?? []
        (nx, ny) = Self.computeNXNY(transform: transform, layout: layout)
    }

    // MARK: Helpers

    private static func computeNXNY(transform t: CGAffineTransform, layout r: CGRect) -> (CGFloat, CGFloat) {
        let x0 = r.origin.x, y0 = r.origin.y
        let x1 = r.origin.x + r.size.width, y1 = r.origin.y + r.size.height
        let llx = t.a * x0 + t.c * y0 + t.tx
        let lrx = t.a * x1 + t.c * y0 + t.tx
        let lbx = t.a * x0 + t.c * y1 + t.tx
        let rbx = t.a * x1 + t.c * y1 + t.tx
        let lly = t.b * x0 + t.d * y0 + t.ty
        let lry = t.b * x1 + t.d * y0 + t.ty
        let lby = t.b * x0 + t.d * y1 + t.ty
        let rby = t.b * x1 + t.d * y1 + t.ty
        return (min(min(lbx, rbx), min(llx, lrx)),
                min(min(lby, rby), min(lly, lry)))
    }
}
