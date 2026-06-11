import UIKit

extension SVGA {
    /// sprite 在单个动画帧中的状态。
    ///
    /// 该类型保存布局、透明度、变换、裁剪路径和矢量形状等渲染所需信息。
    final class VideoSpriteFrameEntity: @unchecked Sendable {
        /// 当前帧的不透明度。
        let alpha: CGFloat
        /// 当前帧在动画画布中的布局。
        let layout: CGRect
        /// 当前帧应用的仿射变换。
        let transform: CGAffineTransform
        /// 变换后边界框的最小 x 坐标。
        let nx: CGFloat
        /// 变换后边界框的最小 y 坐标。
        let ny: CGFloat
        /// 当前帧的裁剪路径。
        let clipPath: String?
        /// 当前帧的矢量形状。
        let shapes: [SVGA.ShapeEntity]

        @MainActor private var _maskLayer: CALayer?

        /// 根据裁剪路径懒加载生成的遮罩 layer。
        @MainActor
        var maskLayer: CALayer? {
            if _maskLayer == nil, let path = clipPath, !path.isEmpty {
                let bezier = SVGABezierPath()
                bezier.setValues(path)
                _maskLayer = bezier.createLayer()
            }
            return _maskLayer
        }

        // MARK: Proto init

        /// 使用 SVGA 2.x Proto frame 创建帧数据。
        ///
        /// - Parameter protoObject: 反序列化后的 Proto frame 对象。
        init(protoObject: SVGAProto.Frame) {
            alpha = CGFloat(protoObject.alpha)
            let l = protoObject.layout
            layout = CGRect(
                x: CGFloat(l.x), y: CGFloat(l.y),
                width: CGFloat(l.width), height: CGFloat(l.height))
            let t = protoObject.transform
            // Proto3 未设置 transform 时所有字段均为 0，这会形成退化的零缩放矩阵。
            // 这里将其视为 identity，避免 layer 被压缩到零尺寸。
            if t.a == 0 && t.b == 0 && t.c == 0 && t.d == 0 {
                transform = .identity
            } else {
                transform = CGAffineTransform(
                    a: CGFloat(t.a), b: CGFloat(t.b),
                    c: CGFloat(t.c), d: CGFloat(t.d),
                    tx: CGFloat(t.tx), ty: CGFloat(t.ty))
            }
            clipPath = protoObject.clipPath.isEmpty ? nil : protoObject.clipPath
            shapes = protoObject.shapes.map { SVGA.ShapeEntity(protoObject: $0) }
            (nx, ny) = Self.computeNXNY(transform: transform, layout: layout)
        }

        // MARK: JSON init (1.x)

        /// 使用 SVGA 1.x JSON 对象创建帧数据。
        ///
        /// - Parameter jsonObject: 解码后的 JSON 对象。
        init(jsonObject: SVGAJSONObject) {
            alpha = jsonObject.cgFloat("alpha")

            if let l = jsonObject.object("layout"),
                let x = l.number("x"), let y = l.number("y"),
                let w = l.number("width"), let h = l.number("height")
            {
                layout = CGRect(
                    x: CGFloat(x), y: CGFloat(y),
                    width: CGFloat(w), height: CGFloat(h))
            } else {
                layout = .zero
            }

            if let t = jsonObject.object("transform"),
                let a = t.number("a"), let b = t.number("b"),
                let c = t.number("c"), let d = t.number("d"),
                let tx = t.number("tx"), let ty = t.number("ty")
            {
                transform = CGAffineTransform(
                    a: CGFloat(a), b: CGFloat(b),
                    c: CGFloat(c), d: CGFloat(d),
                    tx: CGFloat(tx), ty: CGFloat(ty))
            } else {
                transform = .identity
            }

            let cp = jsonObject.string("clipPath")
            clipPath = (cp?.isEmpty == false) ? cp : nil
            shapes = jsonObject.objects("shapes").compactMap { SVGA.ShapeEntity(jsonObject: $0) }
            (nx, ny) = Self.computeNXNY(transform: transform, layout: layout)
        }

        // MARK: Helpers

        private static func computeNXNY(transform t: CGAffineTransform, layout r: CGRect) -> (
            CGFloat, CGFloat
        ) {
            let x0 = r.origin.x
            let y0 = r.origin.y
            let x1 = r.origin.x + r.size.width
            let y1 = r.origin.y + r.size.height
            let llx = t.a * x0 + t.c * y0 + t.tx
            let lrx = t.a * x1 + t.c * y0 + t.tx
            let lbx = t.a * x0 + t.c * y1 + t.tx
            let rbx = t.a * x1 + t.c * y1 + t.tx
            let lly = t.b * x0 + t.d * y0 + t.ty
            let lry = t.b * x1 + t.d * y0 + t.ty
            let lby = t.b * x0 + t.d * y1 + t.ty
            let rby = t.b * x1 + t.d * y1 + t.ty
            return (
                min(min(lbx, rbx), min(llx, lrx)),
                min(min(lby, rby), min(lly, lry))
            )
        }
    }
}
