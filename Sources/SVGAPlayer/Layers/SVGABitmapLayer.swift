import UIKit

@MainActor
final class SVGABitmapLayer: CALayer {
    private let frames: [SVGAVideoSpriteFrameEntity]

    init(frames: [SVGAVideoSpriteFrameEntity]) {
        self.frames = frames
        super.init()
        backgroundColor = UIColor.clear.cgColor
        masksToBounds = false
        contentsGravity = .resizeAspect
    }

    override init(layer: Any) {
        self.frames = []
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) {
        self.frames = []
        super.init(coder: coder)
    }

    func stepToFrame(_ frame: Int) {
        // bitmap content is static; frame stepping is a no-op
    }
}
