import UIKit

public final class SVGAVideoSpriteFrameEntity: @unchecked Sendable {
    public let alpha: CGFloat
    public let layout: CGRect
    public let transform: CGAffineTransform
    public let nx: CGFloat
    public let ny: CGFloat
    public let clipPath: String?
    let shapes: [SVGAShapeEntity]

    @MainActor private var _maskLayer: CALayer?

    @MainActor
    public var maskLayer: CALayer? {
        if _maskLayer == nil, let path = clipPath, !path.isEmpty {
            let bezier = SVGABezierPath()
            bezier.setValues(path)
            _maskLayer = bezier.createLayer()
        }
        return _maskLayer
    }

    // MARK: Proto init

    init(protoObject: FrameEntity) {
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
        shapes = protoObject.shapes.map { SVGAShapeEntity(protoObject: $0) }
        (nx, ny) = Self.computeNXNY(transform: transform, layout: layout)
    }

    // MARK: JSON init (1.x)

    init(jsonObject: SVGAJSONObject) {
        alpha = jsonObject.cgFloat("alpha")

        if let l = jsonObject.object("layout"),
           let x = l.number("x"), let y = l.number("y"),
           let w = l.number("width"), let h = l.number("height") {
            layout = CGRect(x: CGFloat(x), y: CGFloat(y),
                            width: CGFloat(w), height: CGFloat(h))
        } else {
            layout = .zero
        }

        if let t = jsonObject.object("transform"),
           let a = t.number("a"), let b = t.number("b"),
           let c = t.number("c"), let d = t.number("d"),
           let tx = t.number("tx"), let ty = t.number("ty") {
            transform = CGAffineTransform(a: CGFloat(a), b: CGFloat(b),
                                          c: CGFloat(c), d: CGFloat(d),
                                          tx: CGFloat(tx), ty: CGFloat(ty))
        } else {
            transform = .identity
        }

        let cp = jsonObject.string("clipPath")
        clipPath = (cp?.isEmpty == false) ? cp : nil
        shapes = jsonObject.objects("shapes").compactMap { SVGAShapeEntity(jsonObject: $0) }
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
