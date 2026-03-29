import UIKit

public final class SVGAVideoEntity: @unchecked Sendable {
    public let videoSize: CGSize
    public let fps: Int
    public let frames: Int
    public let images: [String: UIImage]
    public let audiosData: [String: Data]
    public let sprites: [SVGAVideoSpriteEntity]
    public let audios: [SVGAAudioEntity]

    // MARK: Proto init (2.x)

    init(protoObject: Svga_MovieEntity, cacheDir: String) {
        if protoObject.hasParams {
            videoSize = CGSize(width: CGFloat(protoObject.params.viewBoxWidth),
                               height: CGFloat(protoObject.params.viewBoxHeight))
            fps = max(1, min(Int(protoObject.params.fps), 120))
            frames = max(0, min(Int(protoObject.params.frames), 100_000))
        } else {
            videoSize = CGSize(width: 100, height: 100)
            fps = 20
            frames = 0
        }
        sprites = protoObject.sprites.map { SVGAVideoSpriteEntity(protoObject: $0) }
        audios = protoObject.audios.map { SVGAAudioEntity(protoObject: $0) }
        (images, audiosData) = Self.loadImages(from: protoObject.images, cacheDir: cacheDir)
    }

    // MARK: JSON init (1.x)

    init(jsonObject: [String: Any], cacheDir: String) {
        if let movie = jsonObject["movie"] as? [String: Any] {
            if let viewBox = movie["viewBox"] as? [String: Any],
               let w = viewBox["width"] as? NSNumber,
               let h = viewBox["height"] as? NSNumber {
                videoSize = CGSize(width: CGFloat(w.floatValue), height: CGFloat(h.floatValue))
            } else {
                videoSize = CGSize(width: 100, height: 100)
            }
            fps = max(1, min((movie["fps"] as? NSNumber).map { Int($0.intValue) } ?? 20, 120))
            frames = max(0, min((movie["frames"] as? NSNumber).map { Int($0.intValue) } ?? 0, 100_000))
        } else {
            videoSize = CGSize(width: 100, height: 100)
            fps = 20
            frames = 0
        }
        if let jsonImages = jsonObject["images"] as? [String: String] {
            var imgs: [String: UIImage] = [:]
            for (key, fileName) in jsonImages {
                guard Self.isSafeFileName(fileName) else { continue }
                let filePath = cacheDir + "/\(fileName)"
                if let data = try? Data(contentsOf: URL(fileURLWithPath: filePath)),
                   let image = UIImage(data: data, scale: 2.0) {
                    let cleanKey = (key as NSString).deletingPathExtension
                    imgs[cleanKey] = image
                }
            }
            images = imgs
        } else {
            images = [:]
        }
        audiosData = [:]
        if let jsonSprites = jsonObject["sprites"] as? [[String: Any]] {
            sprites = jsonSprites.compactMap { SVGAVideoSpriteEntity(jsonObject: $0) }
        } else {
            sprites = []
        }
        audios = []
    }

    // MARK: Private helpers

    private static func isSafeFileName(_ name: String) -> Bool {
        !name.contains("..") && !name.contains("/") && !name.contains("\\") && !name.isEmpty
    }

    private static let mp3Magic: [UInt8] = [0x49, 0x44, 0x33] // "ID3"

    private static func isMP3(_ data: Data) -> Bool {
        guard data.count >= 3 else { return false }
        return data[0] == mp3Magic[0] && data[1] == mp3Magic[1] && data[2] == mp3Magic[2]
    }

    private static func loadImages(
        from protoImages: [String: Data],
        cacheDir: String
    ) -> ([String: UIImage], [String: Data]) {
        var imgs: [String: UIImage] = [:]
        var auds: [String: Data] = [:]
        for (key, value) in protoImages {
            let cleanKey = (key as NSString).deletingPathExtension
            if let fileName = String(data: value, encoding: .utf8) {
                guard isSafeFileName(fileName) else { continue }
                var filePath = cacheDir + "/\(fileName).png"
                if !FileManager.default.fileExists(atPath: filePath) {
                    filePath = cacheDir + "/\(fileName)"
                }
                if let data = try? Data(contentsOf: URL(fileURLWithPath: filePath),
                                        options: .mappedIfSafe),
                   let image = UIImage(data: data, scale: 2.0) {
                    imgs[cleanKey] = image
                }
            } else {
                if isMP3(value) {
                    auds[cleanKey] = value
                } else if let image = UIImage(data: value, scale: 2.0) {
                    imgs[cleanKey] = image
                }
            }
        }
        return (imgs, auds)
    }
}
