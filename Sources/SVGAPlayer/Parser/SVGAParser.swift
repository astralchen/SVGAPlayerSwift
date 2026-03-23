import UIKit
import SwiftProtobuf
import CryptoKit

public actor SVGAParser {
    public static let shared = SVGAParser()
    public var enabledMemoryCache: Bool = true

    // MARK: - Public API

    public func parse(url: URL) async throws -> SVGAVideoEntity {
        let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 20)
        return try await parse(request: request)
    }

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
        return try await parse(data: data, cacheKey: key)
    }

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

    public func parse(named: String, in bundle: Bundle? = nil) async throws -> SVGAVideoEntity {
        let b = bundle ?? Bundle.main
        let key = cacheKey(for: named)
        if let cached = await SVGACacheStore.shared.read(key: key) {
            return cached
        }
        guard let fileURL = b.url(forResource: named, withExtension: "svga")
               ?? b.url(forResource: named, withExtension: nil) else {
            throw SVGAParserError.resourceNotFound(named)
        }
        let data = try Data(contentsOf: fileURL)
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
        let entity = SVGAVideoEntity(protoObject: proto, cacheDir: cacheDir)
        return entity
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
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return caches.appendingPathComponent("SVGACache").appendingPathComponent(key)
    }

    private func cacheKey(for url: URL) -> String {
        return md5(url.absoluteString)
    }

    private func cacheKey(for named: String) -> String {
        return md5(named)
    }

    private func md5(_ string: String) -> String {
        let data = Data(string.utf8)
        let digest = Insecure.MD5.hash(data: data)
        return digest.map { String(format: "%02X", $0) }.joined()
    }
}

// MARK: - Errors

public enum SVGAParserError: Error {
    case invalidURL
    case resourceNotFound(String)
    case missingMovieFile
    case invalidJSON
}
