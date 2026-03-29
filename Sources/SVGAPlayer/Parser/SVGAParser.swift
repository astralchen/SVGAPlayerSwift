import UIKit
import SwiftProtobuf
import CryptoKit

/// SVGA 文件解析器，支持 Proto 2.x 和 JSON 1.x 两种格式。
///
/// 使用共享实例 `SVGAParser.shared` 进行解析，内置内存缓存和磁盘缓存。
///
/// ```swift
/// // 从 Bundle 加载
/// let entity = try await SVGAParser.shared.parse(named: "banner")
///
/// // 从网络加载
/// let entity = try await SVGAParser.shared.parse(url: url)
///
/// // 从原始数据加载
/// let entity = try await SVGAParser.shared.parse(data: svgaData, cacheKey: "myKey")
/// ```
public actor SVGAParser {
    public static let shared = SVGAParser()

    /// 是否启用内存强缓存，默认 true。关闭后仍使用弱引用缓存。
    public var enabledMemoryCache: Bool = true

    /// 网络下载最大文件大小（字节），超出抛出 `fileTooLarge`，默认 50 MB。
    public var maxDownloadSize: Int = 50_000_000

    // MARK: - Public API

    /// 从 URL 下载并解析 SVGA 文件。
    public func parse(url: URL) async throws -> SVGAVideoEntity {
        let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 20)
        return try await parse(request: request)
    }

    /// 从自定义 URLRequest 下载并解析 SVGA 文件。
    public func parse(request: URLRequest) async throws -> SVGAVideoEntity {
        guard let url = request.url else {
            throw SVGAParserError.invalidURL
        }
        let key = cacheKey(for: url)
        let cacheDir = cacheDirURL(for: key)
        if FileManager.default.fileExists(atPath: cacheDir.path) {
            if let entity = try? await loadFromDisk(cacheDir: cacheDir, cacheKey: key) {
                return entity
            }
            try? FileManager.default.removeItem(at: cacheDir)
        }
        let (data, _) = try await URLSession.shared.data(for: request)
        guard data.count <= maxDownloadSize else {
            throw SVGAParserError.fileTooLarge
        }
        return try await parse(data: data, cacheKey: key)
    }

    /// 从原始数据解析 SVGA，自动检测 ZIP/zlib 格式并解压。
    public func parse(data: Data, cacheKey key: String) async throws -> SVGAVideoEntity {
        if let cached = await SVGACacheStore.shared.read(key: key) {
            return cached
        }
        let cacheDir = cacheDirURL(for: key)
        if FileManager.default.fileExists(atPath: cacheDir.path),
           let entity = try? await loadFromDisk(cacheDir: cacheDir, cacheKey: key) {
            return entity
        }
        let entity: SVGAVideoEntity
        if SVGADecompressor.isZIP(data) {
            try SVGADecompressor.unzip(data, to: cacheDir)
            entity = try await loadFromDisk(cacheDir: cacheDir, cacheKey: key)
        } else {
            let inflated = try SVGADecompressor.inflate(data)
            entity = try parseProto(data: inflated, cacheDir: cacheDir.path, cacheKey: key)
        }
        await cacheEntity(entity, key: key)
        return entity
    }

    /// 从 Bundle 中按资源名加载 SVGA 文件。
    ///
    /// - Parameters:
    ///   - named: 资源名（不含 `.svga` 扩展名）。
    ///   - bundle: 资源所在 Bundle，nil 使用 `Bundle.main`。
    public func parse(named: String, in bundle: Bundle? = nil) async throws -> SVGAVideoEntity {
        let b = bundle ?? Bundle.main
        guard let fileURL = b.url(forResource: named, withExtension: "svga")
               ?? b.url(forResource: named, withExtension: nil) else {
            throw SVGAParserError.resourceNotFound(named)
        }
        let data = try Data(contentsOf: fileURL)
        let key = sha256(data)
        return try await parse(data: data, cacheKey: key)
    }

    // MARK: - Private helpers

    private func loadFromDisk(cacheDir: URL, cacheKey key: String) async throws -> SVGAVideoEntity {
        let binaryPath = cacheDir.appendingPathComponent("movie.binary").path
        let specPath = cacheDir.appendingPathComponent("movie.spec").path
        if FileManager.default.fileExists(atPath: binaryPath) {
            let protoData = try Data(contentsOf: URL(fileURLWithPath: binaryPath))
            return try parseProto(data: protoData, cacheDir: cacheDir.path, cacheKey: key)
        } else if FileManager.default.fileExists(atPath: specPath) {
            let jsonData = try Data(contentsOf: URL(fileURLWithPath: specPath))
            return try parseJSON(data: jsonData, cacheDir: cacheDir.path, cacheKey: key)
        }
        throw SVGAParserError.missingMovieFile
    }

    private func parseProto(data: Data, cacheDir: String, cacheKey key: String) throws -> SVGAVideoEntity {
        let proto = try Svga_MovieEntity(serializedBytes: data)
        return SVGAVideoEntity(protoObject: proto, cacheDir: cacheDir)
    }

    private func parseJSON(data: Data, cacheDir: String, cacheKey key: String) throws -> SVGAVideoEntity {
        guard let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SVGAParserError.invalidJSON
        }
        return SVGAVideoEntity(jsonObject: jsonObject, cacheDir: cacheDir)
    }

    private func cacheEntity(_ entity: SVGAVideoEntity, key: String) async {
        if enabledMemoryCache {
            await SVGACacheStore.shared.save(key: key, entity: entity)
        } else {
            await SVGACacheStore.shared.saveWeak(key: key, entity: entity)
        }
    }

    private func cacheDirURL(for key: String) -> URL {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return FileManager.default.temporaryDirectory
                .appendingPathComponent("SVGACache").appendingPathComponent(key)
        }
        return caches.appendingPathComponent("SVGACache").appendingPathComponent(key)
    }

    private func cacheKey(for url: URL) -> String {
        return sha256(url.absoluteString)
    }

    private func cacheKey(for named: String) -> String {
        return sha256(named)
    }

    private func sha256(_ string: String) -> String {
        let data = Data(string.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02X", $0) }.joined()
    }

    private func sha256(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02X", $0) }.joined()
    }
}

// MARK: - Errors

/// SVGA 解析错误。
public enum SVGAParserError: Error {
    case invalidURL
    case resourceNotFound(String)
    case missingMovieFile
    case invalidJSON
    case fileTooLarge
}
