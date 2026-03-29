import UIKit

/// SVGA 矢量形状的统一模型，在解析阶段从 Proto 或 JSON 转换而来。
///
/// 消除了 SVGAVectorLayer 中的运行时类型检查（`as? [String: Any]` / `as? Svga_ShapeEntity`），
/// 所有属性在编译期类型安全。
struct SVGAShapeEntity {

    /// 形状类型。
    enum ShapeType {
        /// SVG path 曲线。
        case shape
        /// 矩形（可带圆角）。
        case rect
        /// 椭圆。
        case ellipse
        /// 保持帧：复用上一个非 keep 帧的内容。
        case keep
    }

    /// 形状参数，按类型区分。
    enum Args {
        case shape(d: String)
        case rect(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, cornerRadius: CGFloat)
        case ellipse(cx: CGFloat, cy: CGFloat, rx: CGFloat, ry: CGFloat)
    }

    /// 形状样式（填充、描边、线条属性）。
    struct Styles {
        var fill: UIColor?
        var stroke: UIColor?
        var strokeWidth: CGFloat = 0
        var lineCap: CAShapeLayerLineCap = .butt
        var lineJoin: CAShapeLayerLineJoin = .miter
        var miterLimit: CGFloat = 0
        /// 虚线参数：(dash 长度, gap 长度, phase 偏移)，nil 表示实线。
        var lineDash: (dash: CGFloat, gap: CGFloat, phase: CGFloat)?
    }

    let type: ShapeType
    let args: Args?
    let styles: Styles?
    let transform: CGAffineTransform?

    // MARK: - Proto init (2.x)

    init(protoObject shape: Svga_ShapeEntity) {
        switch shape.type {
        case .shape:   type = .shape
        case .rect:    type = .rect
        case .ellipse: type = .ellipse
        case .keep:    type = .keep
        default:       type = .keep
        }

        switch shape.args {
        case .shape(let v):
            args = .shape(d: v.d)
        case .rect(let r):
            args = .rect(x: CGFloat(r.x), y: CGFloat(r.y),
                         width: CGFloat(r.width), height: CGFloat(r.height),
                         cornerRadius: CGFloat(r.cornerRadius))
        case .ellipse(let e):
            args = .ellipse(cx: CGFloat(e.cx), cy: CGFloat(e.cy),
                            rx: CGFloat(e.rx), ry: CGFloat(e.ry))
        case nil:
            args = nil
        }

        if shape.hasStyle {
            let s = shape.style
            var st = Styles()
            if s.hasFill {
                st.fill = UIColor(red: CGFloat(s.fill.r), green: CGFloat(s.fill.g),
                                  blue: CGFloat(s.fill.b), alpha: CGFloat(s.fill.a))
            }
            if s.hasStroke {
                st.stroke = UIColor(red: CGFloat(s.stroke.r), green: CGFloat(s.stroke.g),
                                    blue: CGFloat(s.stroke.b), alpha: CGFloat(s.stroke.a))
            }
            st.strokeWidth = CGFloat(s.strokeWidth)
            switch s.lineCap {
            case .round:  st.lineCap = .round
            case .square: st.lineCap = .square
            default:      st.lineCap = .butt
            }
            switch s.lineJoin {
            case .round: st.lineJoin = .round
            case .bevel: st.lineJoin = .bevel
            default:     st.lineJoin = .miter
            }
            st.miterLimit = CGFloat(s.miterLimit)
            if s.lineDashI > 0 {
                let d0 = CGFloat(max(s.lineDashI, 1.0))
                let d1 = CGFloat(max(s.lineDashIi, 0.1))
                st.lineDash = (d0, d1, CGFloat(s.lineDashIii))
            }
            styles = st
        } else {
            styles = nil
        }

        if shape.hasTransform {
            let t = shape.transform
            transform = CGAffineTransform(a: CGFloat(t.a), b: CGFloat(t.b),
                                          c: CGFloat(t.c), d: CGFloat(t.d),
                                          tx: CGFloat(t.tx), ty: CGFloat(t.ty))
        } else {
            transform = nil
        }
    }

    // MARK: - JSON init (1.x)

    init?(jsonObject dict: [String: Any]) {
        guard let typeStr = dict["type"] as? String else { return nil }
        switch typeStr {
        case "shape":   type = .shape
        case "rect":    type = .rect
        case "ellipse": type = .ellipse
        case "keep":    type = .keep
        default:        return nil
        }

        if let a = dict["args"] as? [String: Any] {
            switch type {
            case .shape:
                args = .shape(d: (a["d"] as? String) ?? "")
            case .rect:
                args = .rect(
                    x: Self.cgf(a["x"]), y: Self.cgf(a["y"]),
                    width: Self.cgf(a["width"]), height: Self.cgf(a["height"]),
                    cornerRadius: Self.cgf(a["cornerRadius"]))
            case .ellipse:
                args = .ellipse(
                    cx: Self.cgf(a["x"]), cy: Self.cgf(a["y"]),
                    rx: Self.cgf(a["radiusX"]), ry: Self.cgf(a["radiusY"]))
            case .keep:
                args = nil
            }
        } else {
            args = nil
        }

        if let s = dict["styles"] as? [String: Any] {
            var st = Styles()
            if let fill = s["fill"] as? [NSNumber], fill.count == 4 {
                st.fill = UIColor(red: CGFloat(fill[0].floatValue), green: CGFloat(fill[1].floatValue),
                                  blue: CGFloat(fill[2].floatValue), alpha: CGFloat(fill[3].floatValue))
            }
            if let stroke = s["stroke"] as? [NSNumber], stroke.count == 4 {
                st.stroke = UIColor(red: CGFloat(stroke[0].floatValue), green: CGFloat(stroke[1].floatValue),
                                    blue: CGFloat(stroke[2].floatValue), alpha: CGFloat(stroke[3].floatValue))
            }
            st.strokeWidth = Self.cgf(s["strokeWidth"])
            if let lc = s["lineCap"] as? String { st.lineCap = CAShapeLayerLineCap(rawValue: lc) }
            if let lj = s["lineJoin"] as? String { st.lineJoin = CAShapeLayerLineJoin(rawValue: lj) }
            st.miterLimit = Self.cgf(s["miterLimit"])
            if let ld = s["lineDash"] as? [NSNumber], ld.count == 3 {
                let d0 = max(CGFloat(ld[0].floatValue), 1.0)
                let d1 = max(CGFloat(ld[1].floatValue), 0.1)
                st.lineDash = (d0, d1, CGFloat(ld[2].floatValue))
            }
            styles = st
        } else {
            styles = nil
        }

        if let t = dict["transform"] as? [String: Any],
           let a = t["a"] as? NSNumber, let b = t["b"] as? NSNumber,
           let c = t["c"] as? NSNumber, let d = t["d"] as? NSNumber,
           let tx = t["tx"] as? NSNumber, let ty = t["ty"] as? NSNumber {
            transform = CGAffineTransform(a: CGFloat(a.floatValue), b: CGFloat(b.floatValue),
                                          c: CGFloat(c.floatValue), d: CGFloat(d.floatValue),
                                          tx: CGFloat(tx.floatValue), ty: CGFloat(ty.floatValue))
        } else {
            transform = nil
        }
    }

    // MARK: - Helpers

    private static func cgf(_ value: Any?) -> CGFloat {
        (value as? NSNumber).map { CGFloat($0.floatValue) } ?? 0
    }
}
