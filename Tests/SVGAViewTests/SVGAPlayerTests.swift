import Testing
import Foundation
@testable import SVGAView

// MARK: - Helpers

private func loadEntity(named name: String) async throws -> SVGA.VideoEntity {
    guard let url = Bundle.module.url(forResource: name, withExtension: "svga") else {
        throw SVGAParserError.resourceNotFound("\(name).svga not found in test bundle")
    }
    let data = try Data(contentsOf: url)
    #expect(!data.isEmpty, "\(name).svga data should not be empty")
    // Use content hash as cache key so swapping the file invalidates the cache
    return try await SVGAParser.shared.parse(data: data, cacheKey: "test_\(name)_\(data.count)")
}

private final class ProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedValues: [Double] = []

    func record(_ value: Double) {
        lock.lock()
        recordedValues.append(value)
        lock.unlock()
    }

    var values: [Double] {
        lock.lock()
        defer { lock.unlock() }
        return recordedValues
    }
}

final class ChunkedSVGAURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var responseData = Data()
    private var isStopped = false

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "svga-progress.test"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: SVGAParserError.invalidURL)
            return
        }
        let data = Self.responseData
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Length": "\(data.count)"]
        )!

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        let splitIndex = data.count / 2
        client?.urlProtocol(self, didLoad: Data(data.prefix(splitIndex)))
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self, !self.isStopped else { return }
            self.client?.urlProtocol(self, didLoad: Data(data.suffix(data.count - splitIndex)))
            self.client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {
        isStopped = true
    }
}

// MARK: - Parser Tests

@Test
func svgaViewModuleLoads() {
    #expect(true)
}

@Test
func parseBannerSVGA_hasValidMetadata() async throws {
    let entity = try await loadEntity(named: "banner")
    #expect(entity.fps > 0, "fps=\(entity.fps) should be > 0")
    #expect(entity.frames > 0, "frames=\(entity.frames) should be > 0")
    #expect(entity.videoSize.width > 0, "videoSize.width should be > 0")
    #expect(entity.videoSize.height > 0, "videoSize.height should be > 0")
    #expect(!entity.sprites.isEmpty, "sprites should not be empty")
    print("[SVGATest] banner: fps=\(entity.fps) frames=\(entity.frames) size=\(entity.videoSize) sprites=\(entity.sprites.count) images=\(entity.images.count)")
}

@Test
func parseBannerSVGA_imagesLoadCorrectly() async throws {
    let entity = try await loadEntity(named: "banner")
    #expect(!entity.images.isEmpty, "banner.svga should have at least one image")
    for (key, image) in entity.images {
        #expect(image.size.width > 0, "Image '\(key)' has zero width")
        #expect(image.size.height > 0, "Image '\(key)' has zero height")
    }
    print("[SVGATest] banner: all \(entity.images.count) images loaded successfully")
}

@Test
func parseBannerSVGA_spriteImageKeysNonEmpty() async throws {
    let entity = try await loadEntity(named: "banner")
    for (i, sprite) in entity.sprites.enumerated() {
        #expect(!sprite.imageKey.isEmpty, "sprite[\(i)] imageKey should not be empty")
    }
    print("[SVGATest] banner: all \(entity.sprites.count) sprite imageKeys are non-empty")
}

@Test
func parseBubbleSVGA_hasValidMetadata() async throws {
    let entity = try await loadEntity(named: "bubble")
    #expect(entity.fps > 0, "fps=\(entity.fps) should be > 0")
    #expect(entity.frames > 0, "frames=\(entity.frames) should be > 0")
    #expect(entity.videoSize.width > 0, "videoSize.width should be > 0")
    #expect(entity.videoSize.height > 0, "videoSize.height should be > 0")
    #expect(!entity.sprites.isEmpty, "sprites should not be empty")
    print("[SVGATest] bubble: fps=\(entity.fps) frames=\(entity.frames) size=\(entity.videoSize) sprites=\(entity.sprites.count) images=\(entity.images.count)")
}

@Test
func parseBubbleSVGA_spriteImageKeysNonEmpty() async throws {
    let entity = try await loadEntity(named: "bubble")
    for (i, sprite) in entity.sprites.enumerated() {
        #expect(!sprite.imageKey.isEmpty, "sprite[\(i)] imageKey should not be empty")
    }
    print("[SVGATest] bubble: all \(entity.sprites.count) sprite imageKeys are non-empty")
}

@Test
func parseURL_reportsDownloadProgress() async throws {
    guard let url = Bundle.module.url(forResource: "banner", withExtension: "svga") else {
        throw SVGAParserError.resourceNotFound("banner.svga not found in test bundle")
    }
    ChunkedSVGAURLProtocol.responseData = try Data(contentsOf: url)
    SVGAURLSessionTestHooks.protocolClasses = [
        ChunkedSVGAURLProtocol.self,
        NeverFinishingSVGAURLProtocol.self
    ]

    let request = URLRequest(
        url: URL(string: "https://svga-progress.test/banner-\(UUID().uuidString).svga")!,
        cachePolicy: .reloadIgnoringLocalCacheData,
        timeoutInterval: 5
    )
    let recorder = ProgressRecorder()

    let entity = try await SVGAParser.shared.parse(request: request) { progress in
        recorder.record(progress)
    }

    let values = recorder.values
    #expect(entity.frames > 0)
    #expect(values.contains { $0 > 0 && $0 < 1 }, "expected an intermediate progress value, got \(values)")
    #expect(values.last == 1.0, "expected final progress to be 1.0, got \(values)")
}
