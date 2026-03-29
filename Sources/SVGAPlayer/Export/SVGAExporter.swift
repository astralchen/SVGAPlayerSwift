import UIKit

/// 将 SVGA 动画逐帧导出为 UIImage 数组或 PNG 文件序列。
///
/// ```swift
/// let entity = try await SVGAParser.shared.parse(named: "animation")
/// let exporter = SVGAExporter()
/// exporter.videoItem = entity
///
/// // 导出为 UIImage 数组
/// let images = exporter.toImages()
///
/// // 导出为 PNG 文件
/// exporter.saveImages(to: "/path/to/output", filePrefix: "frame_")
/// ```
@MainActor
public final class SVGAExporter {

    /// 要导出的动画数据。
    public var videoItem: SVGAVideoEntity?

    public init() {}

    /// 将所有帧导出为 UIImage 数组。
    ///
    /// - Returns: 按帧顺序排列的图片数组，videoItem 为 nil 或尺寸无效时返回空数组。
    public func toImages() -> [UIImage] {
        guard let item = videoItem,
              item.videoSize.width > 0, item.videoSize.height > 0 else { return [] }
        guard let (dl, layers) = buildDrawLayer(item: item) else { return [] }
        var images: [UIImage] = []
        let renderer = UIGraphicsImageRenderer(size: dl.frame.size)
        for i in 0..<item.frames {
            stepLayers(layers, toFrame: i)
            images.append(renderer.image { ctx in dl.render(in: ctx.cgContext) })
        }
        return images
    }

    /// 将所有帧导出为 PNG 文件，文件名格式为 `{filePrefix}{frameIndex}.png`。
    ///
    /// - Parameters:
    ///   - path: 输出目录路径，不存在时自动创建。
    ///   - filePrefix: 文件名前缀，默认为空。
    public func saveImages(to path: String, filePrefix: String = "") {
        guard let item = videoItem,
              item.videoSize.width > 0, item.videoSize.height > 0 else { return }
        try? FileManager.default.createDirectory(atPath: path,
                                                 withIntermediateDirectories: true)
        guard let (dl, layers) = buildDrawLayer(item: item) else { return }
        let renderer = UIGraphicsImageRenderer(size: dl.frame.size)
        for i in 0..<item.frames {
            stepLayers(layers, toFrame: i)
            let image = renderer.image { ctx in dl.render(in: ctx.cgContext) }
            if let data = image.pngData() {
                let filePath = "\(path)/\(filePrefix)\(i).png"
                try? data.write(to: URL(fileURLWithPath: filePath))
            }
        }
    }

    // MARK: - Private

    private func buildDrawLayer(item: SVGAVideoEntity) -> (CALayer, [SVGAContentLayer])? {
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
        CATransaction.setDisableActions(true)
        for layer in layers { layer.stepToFrame(frame) }
        CATransaction.setDisableActions(false)
    }
}
