import UIKit

@MainActor
public final class SVGAExporter {

    public var videoItem: SVGAVideoEntity?

    public init() {}

    public func toImages() -> [UIImage] {
        guard let item = videoItem,
              item.videoSize.width > 0, item.videoSize.height > 0 else { return [] }
        let (dl, layers) = buildDrawLayer(item: item)
        var images: [UIImage] = []
        for i in 0..<item.frames {
            stepLayers(layers, toFrame: i)
            let renderer = UIGraphicsImageRenderer(size: dl.frame.size)
            let image = renderer.image { ctx in
                dl.render(in: ctx.cgContext)
            }
            images.append(image)
        }
        return images
    }

    public func saveImages(to path: String, filePrefix: String = "") {
        guard let item = videoItem,
              item.videoSize.width > 0, item.videoSize.height > 0 else { return }
        try? FileManager.default.createDirectory(atPath: path,
                                                 withIntermediateDirectories: true)
        let (dl, layers) = buildDrawLayer(item: item)
        let renderer = UIGraphicsImageRenderer(size: dl.frame.size)
        for i in 0..<item.frames {
            stepLayers(layers, toFrame: i)
            let image = renderer.image { ctx in
                dl.render(in: ctx.cgContext)
            }
            if let data = image.pngData() {
                let filePath = "\(path)/\(filePrefix)\(i).png"
                try? data.write(to: URL(fileURLWithPath: filePath))
            }
        }
    }

    // MARK: Private

    private func buildDrawLayer(item: SVGAVideoEntity) -> (CALayer, [SVGAContentLayer]) {
        let dl = CALayer()
        dl.frame = CGRect(origin: .zero, size: item.videoSize)
        dl.masksToBounds = true
        var layers: [SVGAContentLayer] = []
        for sprite in item.sprites {
            let bitmapKey = (sprite.imageKey as NSString).deletingPathExtension
            let bitmap = item.images[bitmapKey]
            let contentLayer = sprite.requestLayer(bitmap: bitmap)
            dl.addSublayer(contentLayer)
            layers.append(contentLayer)
        }
        return (dl, layers)
    }

    private func stepLayers(_ layers: [SVGAContentLayer], toFrame frame: Int) {
        for layer in layers {
            layer.stepToFrame(frame)
        }
    }
}
