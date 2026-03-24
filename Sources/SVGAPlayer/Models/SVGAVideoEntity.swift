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
            fps = Int(protoObject.params.fps)
            frames = Int(protoObject.params.frames)
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
            fps = (movie["fps"] as? NSNumber).map { Int($0.intValue) } ?? 20
            frames = (movie["frames"] as? NSNumber).map { Int($0.intValue) } ?? 0
        } else {
            videoSize = CGSize(width: 100, height: 100)
            fps = 20
            frames = 0
        }
        if let jsonImages = jsonObject["images"] as? [String: String] {
            var imgs: [String: UIImage] = [:]
            for (key, fileName) in jsonImages {
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

    private static let mp3Magic: [UInt8] = [0x49, 0x44, 0x33] // "ID3"

    private static func isMP3(_ data: Data) -> Bool {
        guard data.count >= 3 else { return false }
        return data[0] == mp3Magic[0] && data[1] == mp3Magic[1] && data[2] == mp3Magic[2]
    }

    private static func loadImages(
        from protoImages: [String: Data],
        cacheDir: String
    ) -> ([String: UIImage], [String: Data]) {
        print("[SVGAImages] loadImages input keys=\(protoImages.keys.sorted()) cacheDir=\(cacheDir)")
        var imgs: [String: UIImage] = [:]
        var auds: [String: Data] = [:]
        for (key, value) in protoImages {
            let cleanKey = (key as NSString).deletingPathExtension
            if let fileName = String(data: value, encoding: .utf8) {
                // value is a filename — load from cacheDir
                var filePath = cacheDir + "/\(fileName).png"
                let pngExists = FileManager.default.fileExists(atPath: filePath)
                if !pngExists {
                    filePath = cacheDir + "/\(fileName)"
                }
                let fileExists = FileManager.default.fileExists(atPath: filePath)
                print("[SVGAImages] key=\(key) cleanKey=\(cleanKey) fileName=\(fileName) pngExists=\(pngExists) filePath=\(filePath) fileExists=\(fileExists)")
                if fileExists,
                   let data = try? Data(contentsOf: URL(fileURLWithPath: filePath),
                                        options: .mappedIfSafe),
                   let image = UIImage(data: data, scale: 2.0) {
                    imgs[cleanKey] = image
                    print("[SVGAImages] ✅ loaded image for cleanKey=\(cleanKey) size=\(image.size)")
                } else if fileExists {
                    print("[SVGAImages] ❌ file exists but UIImage failed for cleanKey=\(cleanKey)")
                } else {
                    print("[SVGAImages] ❌ file not found for cleanKey=\(cleanKey)")
                }
            } else {
                // value is raw binary data
                print("[SVGAImages] key=\(key) cleanKey=\(cleanKey) raw binary size=\(value.count)")
                if isMP3(value) {
                    auds[cleanKey] = value
                    print("[SVGAImages] ✅ stored audio for cleanKey=\(cleanKey)")
                } else if let image = UIImage(data: value, scale: 2.0) {
                    imgs[cleanKey] = image
                    print("[SVGAImages] ✅ loaded inline image for cleanKey=\(cleanKey) size=\(image.size)")
                } else {
                    print("[SVGAImages] ❌ raw binary not MP3 and not UIImage for cleanKey=\(cleanKey)")
                }
            }
        }
        print("[SVGAImages] loadImages done: imgs.keys=\(imgs.keys.sorted()) auds.keys=\(auds.keys.sorted())")
        return (imgs, auds)
    }
}
