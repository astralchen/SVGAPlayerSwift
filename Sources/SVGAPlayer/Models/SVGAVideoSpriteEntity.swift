import UIKit

public final class SVGAVideoSpriteEntity: @unchecked Sendable {
    public let imageKey: String
    public let matteKey: String?
    public let frames: [SVGAVideoSpriteFrameEntity]

    // MARK: Proto init

    init(protoObject: SpriteEntity) {
        imageKey = protoObject.imageKey
        matteKey = protoObject.matteKey.isEmpty ? nil : protoObject.matteKey
        frames = protoObject.frames.map { SVGAVideoSpriteFrameEntity(protoObject: $0) }
    }

    // MARK: JSON init (1.x)

    init?(jsonObject: SVGAJSONObject) {
        guard let key = jsonObject.string("imageKey"),
              let jsonFrames = jsonObject.objectArray("frames") else { return nil }
        imageKey = key
        matteKey = jsonObject.string("matteKey")
        frames = jsonFrames.map { SVGAVideoSpriteFrameEntity(jsonObject: $0) }
    }

    // MARK: Layer factory

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
