import UIKit

extension SVGA {
    /// 解析后的 SVGA 动画数据。
    ///
    /// `VideoEntity` 是渲染层使用的统一模型，屏蔽 SVGA 2.x Proto 和
    /// SVGA 1.x JSON 两种源格式之间的差异。
    final class VideoEntity: @unchecked Sendable {
        /// 动画画布的原始尺寸。
        let videoSize: CGSize
        /// 动画帧率。
        let fps: Int
        /// 动画总帧数。
        let frames: Int
        /// 以归一化 key 索引的图片资源。
        let images: [String: UIImage]
        /// 以归一化 key 索引的音频数据。
        let audiosData: [String: Data]
        /// 按渲染顺序排列的 sprite 列表。
        let sprites: [SVGA.VideoSpriteEntity]
        /// 动画中的音频片段。
        let audios: [SVGA.AudioEntity]

        // MARK: Proto init (2.x)

        /// 使用 SVGA 2.x Proto 对象创建动画数据。
        ///
        /// - Parameters:
        ///   - protoObject: 反序列化后的 Proto movie 对象。
        ///   - cacheDir: 解压后的资源目录路径。
        init(protoObject: SVGAProto.Movie, cacheDir: String) {
            if protoObject.hasParams {
                videoSize = CGSize(
                    width: CGFloat(protoObject.params.viewBoxWidth),
                    height: CGFloat(protoObject.params.viewBoxHeight))
                fps = max(1, min(Int(protoObject.params.fps), 120))
                frames = max(0, min(Int(protoObject.params.frames), 100_000))
            } else {
                videoSize = CGSize(width: 100, height: 100)
                fps = 20
                frames = 0
            }
            sprites = protoObject.sprites.map { SVGA.VideoSpriteEntity(protoObject: $0) }
            audios = protoObject.audios.map { SVGA.AudioEntity(protoObject: $0) }
            (images, audiosData) = Self.loadImages(from: protoObject.images, cacheDir: cacheDir)
        }

        // MARK: JSON init (1.x)

        /// 使用 SVGA 1.x JSON 对象创建动画数据。
        ///
        /// - Parameters:
        ///   - jsonObject: 解码后的 JSON 对象。
        ///   - cacheDir: 解压后的资源目录路径。
        init(jsonObject: SVGAJSONObject, cacheDir: String) {
            if let movie = jsonObject.object("movie") {
                if let viewBox = movie.object("viewBox"),
                    let w = viewBox.number("width"),
                    let h = viewBox.number("height")
                {
                    videoSize = CGSize(width: CGFloat(w), height: CGFloat(h))
                } else {
                    videoSize = CGSize(width: 100, height: 100)
                }
                fps = max(1, min(movie.number("fps").map { Int($0) } ?? 20, 120))
                frames = max(0, min(movie.number("frames").map { Int($0) } ?? 0, 100_000))
            } else {
                videoSize = CGSize(width: 100, height: 100)
                fps = 20
                frames = 0
            }
            if let jsonImages = jsonObject.stringMap("images") {
                var imgs: [String: UIImage] = [:]
                for (key, fileName) in jsonImages {
                    guard Self.isSafeFileName(fileName) else { continue }
                    let filePath = cacheDir + "/\(fileName)"
                    if let data = try? Data(contentsOf: URL(fileURLWithPath: filePath)),
                        let image = UIImage(data: data, scale: 2.0)
                    {
                        let cleanKey = (key as NSString).deletingPathExtension
                        imgs[cleanKey] = image
                    }
                }
                images = imgs
            } else {
                images = [:]
            }
            audiosData = [:]
            sprites = jsonObject.objects("sprites").compactMap {
                SVGA.VideoSpriteEntity(jsonObject: $0)
            }
            audios = []
        }

        // MARK: Private helpers

        private static func isSafeFileName(_ name: String) -> Bool {
            !name.contains("..") && !name.contains("/") && !name.contains("\\") && !name.isEmpty
        }

        private static let mp3Magic: [UInt8] = [0x49, 0x44, 0x33]  // "ID3"

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
                    if let data = try? Data(
                        contentsOf: URL(fileURLWithPath: filePath),
                        options: .mappedIfSafe),
                        let image = UIImage(data: data, scale: 2.0)
                    {
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
}
