import UIKit

extension SVGA {
    /// SVGA 动画中的一个 sprite。
    ///
    /// 每个 sprite 包含一个图片 key、可选的 matte key，以及逐帧布局和
    /// 变换信息。渲染时会转换为一个 `SVGAContentLayer`。
    final class VideoSpriteEntity: @unchecked Sendable {
        /// sprite 引用的图片资源 key。
        let imageKey: String
        /// 用作遮罩的 matte sprite key。
        let matteKey: String?
        /// sprite 的逐帧状态。
        let frames: [SVGA.VideoSpriteFrameEntity]

        // MARK: Proto init

        /// 使用 SVGA 2.x Proto sprite 创建 sprite 数据。
        ///
        /// - Parameter protoObject: 反序列化后的 Proto sprite 对象。
        init(protoObject: SVGAProto.Sprite) {
            imageKey = protoObject.imageKey
            matteKey = protoObject.matteKey.isEmpty ? nil : protoObject.matteKey
            frames = protoObject.frames.map { SVGA.VideoSpriteFrameEntity(protoObject: $0) }
        }

        // MARK: JSON init (1.x)

        /// 使用 SVGA 1.x JSON 对象创建 sprite 数据。
        ///
        /// - Parameter jsonObject: 解码后的 JSON 对象。
        init?(jsonObject: SVGAJSONObject) {
            guard let key = jsonObject.string("imageKey"),
                let jsonFrames = jsonObject.objectArray("frames")
            else { return nil }
            imageKey = key
            matteKey = jsonObject.string("matteKey")
            frames = jsonFrames.map { SVGA.VideoSpriteFrameEntity(jsonObject: $0) }
        }

        // MARK: Layer factory

        /// 创建用于渲染该 sprite 的内容 layer。
        ///
        /// - Parameter bitmap: sprite 使用的位图。传入 `nil` 时只创建矢量 layer。
        /// - Returns: 配置完成的内容 layer。
        @MainActor
        func requestLayer(bitmap: UIImage?) -> SVGAContentLayer {
            let layer = SVGAContentLayer(frames: frames, imageKey: imageKey)
            if let bitmap {
                let bitmapLayer = SVGABitmapLayer(frames: frames)
                bitmapLayer.contents = bitmap.cgImage
                layer.bitmapLayer = bitmapLayer
            }
            layer.vectorLayer = SVGAVectorLayer(frames: frames)
            return layer
        }
    }
}
