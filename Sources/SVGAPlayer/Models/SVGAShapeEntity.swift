import UIKit

/// SVGA 矢量形状的统一模型，在解析阶段从 Proto 或 JSON 转换而来。
///
/// 消除了 SVGAVectorLayer 中对 JSON 字典 / Proto 对象的运行时类型分支，
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

    init(protoObject shape: ShapeEntity) {
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

    init?(jsonObject dict: SVGAJSONObject) {
        guard let typeStr = dict.string("type") else { return nil }
        switch typeStr {
        case "shape":   type = .shape
        case "rect":    type = .rect
        case "ellipse": type = .ellipse
        case "keep":    type = .keep
        default:        return nil
        }

        if let a = dict.object("args") {
            switch type {
            case .shape:
                args = .shape(d: a.string("d") ?? "")
            case .rect:
                args = .rect(
                    x: a.cgFloat("x"), y: a.cgFloat("y"),
                    width: a.cgFloat("width"), height: a.cgFloat("height"),
                    cornerRadius: a.cgFloat("cornerRadius"))
            case .ellipse:
                args = .ellipse(
                    cx: a.cgFloat("x"), cy: a.cgFloat("y"),
                    rx: a.cgFloat("radiusX"), ry: a.cgFloat("radiusY"))
            case .keep:
                args = nil
            }
        } else {
            args = nil
        }

        if let s = dict.object("styles") {
            var st = Styles()
            if let fill = s.numbers("fill"), fill.count == 4 {
                st.fill = UIColor(red: CGFloat(fill[0]), green: CGFloat(fill[1]),
                                  blue: CGFloat(fill[2]), alpha: CGFloat(fill[3]))
            }
            if let stroke = s.numbers("stroke"), stroke.count == 4 {
                st.stroke = UIColor(red: CGFloat(stroke[0]), green: CGFloat(stroke[1]),
                                    blue: CGFloat(stroke[2]), alpha: CGFloat(stroke[3]))
            }
            st.strokeWidth = s.cgFloat("strokeWidth")
            if let lc = s.string("lineCap") { st.lineCap = CAShapeLayerLineCap(rawValue: lc) }
            if let lj = s.string("lineJoin") { st.lineJoin = CAShapeLayerLineJoin(rawValue: lj) }
            st.miterLimit = s.cgFloat("miterLimit")
            if let ld = s.numbers("lineDash"), ld.count == 3 {
                let d0 = max(CGFloat(ld[0]), 1.0)
                let d1 = max(CGFloat(ld[1]), 0.1)
                st.lineDash = (d0, d1, CGFloat(ld[2]))
            }
            styles = st
        } else {
            styles = nil
        }

        if let t = dict.object("transform"),
           let a = t.number("a"), let b = t.number("b"),
           let c = t.number("c"), let d = t.number("d"),
           let tx = t.number("tx"), let ty = t.number("ty") {
            transform = CGAffineTransform(a: CGFloat(a), b: CGFloat(b),
                                          c: CGFloat(c), d: CGFloat(d),
                                          tx: CGFloat(tx), ty: CGFloat(ty))
        } else {
            transform = nil
        }
    }
}
