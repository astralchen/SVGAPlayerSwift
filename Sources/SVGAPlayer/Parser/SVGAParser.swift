import UIKit
import SwiftProtobuf
import CryptoKit

/// 网络下载进度回调，取值范围为 0.0 ~ 1.0。
public typealias SVGADownloadProgressHandler = @Sendable (_ progress: Double) -> Void

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
    public func parse(url: URL, progressHandler: SVGADownloadProgressHandler? = nil) async throws -> SVGAVideoEntity {
        let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 20)
        return try await parse(request: request, progressHandler: progressHandler)
    }

    /// 从自定义 URLRequest 下载并解析 SVGA 文件。
    public func parse(request: URLRequest, progressHandler: SVGADownloadProgressHandler? = nil) async throws -> SVGAVideoEntity {
        guard let url = request.url else {
            throw SVGAParserError.invalidURL
        }
        let key = cacheKey(for: url)
        let cacheDir = cacheDirURL(for: key)
        if FileManager.default.fileExists(atPath: cacheDir.path) {
            if let entity = try? await loadFromDisk(cacheDir: cacheDir, cacheKey: key) {
                progressHandler?(1.0)
                return entity
            }
            try? FileManager.default.removeItem(at: cacheDir)
        }
        let data = try await SVGADataDownloader.download(
            request: request,
            maximumSize: maxDownloadSize,
            progressHandler: progressHandler
        )
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
        let proto = try MovieEntity(serializedBytes: data)
        return SVGAVideoEntity(protoObject: proto, cacheDir: cacheDir)
    }

    private func parseJSON(data: Data, cacheDir: String, cacheKey key: String) throws -> SVGAVideoEntity {
        guard case .object(let jsonObject) = try JSONDecoder().decode(SVGAJSONValue.self, from: data) else {
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

private final class SVGADataDownloader: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let maximumSize: Int
    private let progressHandler: SVGADownloadProgressHandler?
    private var data = Data()
    private var expectedContentLength: Int64 = NSURLSessionTransferSizeUnknown
    private var continuation: CheckedContinuation<Data, Error>?
    private var session: URLSession?
    private var isCompleted = false

    private init(maximumSize: Int, progressHandler: SVGADownloadProgressHandler?) {
        self.maximumSize = maximumSize
        self.progressHandler = progressHandler
    }

    static func download(
        request: URLRequest,
        maximumSize: Int,
        progressHandler: SVGADownloadProgressHandler?
    ) async throws -> Data {
        let downloader = SVGADataDownloader(maximumSize: maximumSize, progressHandler: progressHandler)
        return try await downloader.download(request: request)
    }

    private func download(request: URLRequest) async throws -> Data {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                let configuration = URLSessionConfiguration.default
                configuration.requestCachePolicy = request.cachePolicy
                let queue = OperationQueue()
                queue.maxConcurrentOperationCount = 1
                queue.name = "com.svga.player.download"
                let session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
                self.session = session
                session.dataTask(with: request).resume()
            }
        } onCancel: {
            self.cancel()
        }
    }

    private func cancel() {
        session?.invalidateAndCancel()
        complete(.failure(CancellationError()))
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        expectedContentLength = response.expectedContentLength
        if expectedContentLength > Int64(maximumSize) {
            complete(.failure(SVGAParserError.fileTooLarge))
            completionHandler(.cancel)
            return
        }
        reportProgress(receivedBytes: 0)
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive receivedData: Data) {
        data.append(receivedData)
        guard data.count <= maximumSize else {
            complete(.failure(SVGAParserError.fileTooLarge))
            dataTask.cancel()
            return
        }
        reportProgress(receivedBytes: data.count)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            complete(.failure(error))
            return
        }
        reportProgress(receivedBytes: data.count, forceComplete: true)
        complete(.success(data))
    }

    private func reportProgress(receivedBytes: Int, forceComplete: Bool = false) {
        guard let progressHandler else { return }
        if forceComplete {
            progressHandler(1.0)
            return
        }
        guard expectedContentLength > 0 else {
            progressHandler(receivedBytes > 0 ? 0.0 : 0.0)
            return
        }
        let progress = min(1.0, max(0.0, Double(receivedBytes) / Double(expectedContentLength)))
        progressHandler(progress)
    }

    private func complete(_ result: Result<Data, Error>) {
        guard !isCompleted else { return }
        isCompleted = true
        session?.finishTasksAndInvalidate()
        session = nil
        switch result {
        case .success(let data):
            continuation?.resume(returning: data)
        case .failure(let error):
            continuation?.resume(throwing: error)
        }
        continuation = nil
    }
}
