import Testing
import Foundation
@testable import SVGAPlayer

// MARK: - Helpers

private func loadEntity(named name: String) async throws -> SVGAVideoEntity {
    guard let url = Bundle.module.url(forResource: name, withExtension: "svga") else {
        throw SVGAParserError.resourceNotFound("\(name).svga not found in test bundle")
    }
    let data = try Data(contentsOf: url)
    #expect(!data.isEmpty, "\(name).svga data should not be empty")
    // Use content hash as cache key so swapping the file invalidates the cache
    return try await SVGAParser.shared.parse(data: data, cacheKey: "test_\(name)_\(data.count)")
}

// MARK: - Parser Tests

@Test
func svgaPlayerModuleLoads() {
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