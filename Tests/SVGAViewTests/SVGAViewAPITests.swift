import Foundation
import Testing
import UIKit
@testable import SVGAView

private func makeSolidTestImage() -> UIImage {
    UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { context in
        UIColor.red.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
    }
}

private func layerContentsIdentical(_ contents: Any?, to image: CGImage) -> Bool {
    guard let contents else { return false }
    return contents as AnyObject === image
}

@MainActor
private func findContentLayer(in layer: CALayer?, imageKey: String) -> SVGAContentLayer? {
    guard let layer else { return nil }
    if let contentLayer = layer as? SVGAContentLayer, contentLayer.imageKey == imageKey {
        return contentLayer
    }
    for sublayer in layer.sublayers ?? [] {
        if let match = findContentLayer(in: sublayer, imageKey: imageKey) {
            return match
        }
    }
    return nil
}

final class NeverFinishingSVGAURLProtocol: URLProtocol {
    nonisolated(unsafe) static var started = false

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "svga-never.test"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.started = true
    }

    override func stopLoading() {}
}

@MainActor
@Test
func svgaViewPublicAPITypesAreUsable() {
    let view = SVGAView()
    var observedEvents: [SVGAViewEvent] = []
    view.onEvent = { observedEvents.append($0) }

    let request = URLRequest(url: URL(string: "https://example.com/effect.svga")!)
    let source = SVGAViewSource.request(request)

    #expect(view.state == .idle)
    #expect(source.debugDescription.contains("request"))
    #expect(SVGAViewError.resourceNotFound("missing").errorDescription?.isEmpty == false)
    view.setImage(makeSolidTestImage(), forKey: "avatar")
    view.setAttributedText(NSAttributedString(string: "name"), forKey: "nickname")
    view.setDrawingBlock({ _, _ in }, forKey: "badge")
    view.setHidden(true, forKey: "badge")
    view.removeImage(forKey: "avatar")
    view.removeAttributedText(forKey: "nickname")
    view.removeDrawingBlock(forKey: "badge")
    view.removeHidden(forKey: "badge")
    view.clearDynamicContent()
    #expect(observedEvents.isEmpty)
}

@MainActor
@Test
func loadNamedAwaitsReadyState() async throws {
    let view = SVGAView()
    view.autoPlay = false
    var observedEvents: [SVGAViewEvent] = []
    view.onEvent = { observedEvents.append($0) }

    try await view.load(named: "banner", in: .module)

    #expect(view.state == .ready)
    #expect(observedEvents == [
        .stateChanged(.loading),
        .stateChanged(.ready),
        .ready
    ])
}

@MainActor
@Test
func filePathLoadingIsDeferredUntilAfterPropertySet() async throws {
    guard let fileURL = Bundle.module.url(forResource: "banner", withExtension: "svga") else {
        throw SVGAParserError.resourceNotFound("banner.svga")
    }
    let view = SVGAView()
    view.autoPlay = false

    view.filePath = fileURL.absoluteString

    #expect(view.state == .idle)
    for _ in 0..<200 where view.state != .ready {
        try await Task.sleep(nanoseconds: 10_000_000)
    }
    #expect(view.state == .ready)
}

@MainActor
@Test
func playbackControlsUpdateState() async throws {
    let view = SVGAView()
    view.autoPlay = false

    try await view.load(named: "banner", in: .module)

    view.startAnimation()
    #expect(view.state == .playing)

    view.pauseAnimation()
    #expect(view.state == .paused)

    view.step(toFrame: 0, andPlay: false)
    #expect(view.state == .paused)

    view.step(toPercentage: 0.2, andPlay: true)
    #expect(view.state == .playing)

    view.stopAnimation()
    #expect(view.state == .stopped)
}

@MainActor
@Test
func finishedAnimationUpdatesStateBeforeCallback() async throws {
    let view = SVGAView()
    view.autoPlay = false
    view.loops = 1
    view.clearsAfterStop = false
    var callbackState: SVGAViewState?
    view.onEvent = { event in
        guard case .finished = event else { return }
        callbackState = view.state
    }

    try await view.load(named: "banner", in: .module)
    view.startAnimation(range: 0..<1, reverse: false)
    try await Task.sleep(nanoseconds: 200_000_000)

    #expect(callbackState == .stopped)
    #expect(view.state == .stopped)
}

@MainActor
@Test
func runtimeDynamicContentMethodsUpdateLoadedLayers() async throws {
    let entity = try await SVGAParser.shared.parse(named: "banner", in: .module)
    guard let sprite = entity.sprites.first(where: { sprite in
        let bitmapKey = (sprite.imageKey as NSString).deletingPathExtension
        return entity.images[bitmapKey] != nil
    }) else {
        throw SVGAParserError.resourceNotFound("bitmap sprite")
    }
    let bitmapKey = (sprite.imageKey as NSString).deletingPathExtension
    guard let originalCGImage = entity.images[bitmapKey]?.cgImage else {
        throw SVGAParserError.resourceNotFound("bitmap image")
    }

    let player = SVGAPlaybackEngine()
    player.videoItem = entity
    guard let contentLayer = findContentLayer(in: player.drawLayer, imageKey: sprite.imageKey) else {
        throw SVGAParserError.resourceNotFound("content layer")
    }

    let replacementImage = makeSolidTestImage()
    guard let replacementCGImage = replacementImage.cgImage else {
        throw SVGAParserError.resourceNotFound("replacement bitmap")
    }
    player.setImage(replacementImage, forKey: bitmapKey)
    #expect(layerContentsIdentical(contentLayer.bitmapLayer?.contents, to: replacementCGImage))

    player.removeImage(forKey: sprite.imageKey)
    #expect(layerContentsIdentical(contentLayer.bitmapLayer?.contents, to: originalCGImage))

    player.setAttributedText(NSAttributedString(string: "nickname"), forKey: bitmapKey)
    #expect(contentLayer.textLayer?.string != nil)
    player.removeAttributedText(forKey: sprite.imageKey)
    #expect(contentLayer.textLayer == nil)

    player.setDrawingBlock({ _, _ in }, forKey: bitmapKey)
    #expect(contentLayer.dynamicDrawingBlock != nil)
    player.removeDrawingBlock(forKey: sprite.imageKey)
    #expect(contentLayer.dynamicDrawingBlock == nil)

    player.setHidden(true, forKey: sprite.imageKey)
    #expect(contentLayer.dynamicHidden)
    player.removeHidden(forKey: bitmapKey)
    #expect(!contentLayer.dynamicHidden)

    player.setImage(replacementImage, forKey: sprite.imageKey)
    player.setAttributedText(NSAttributedString(string: "clear"), forKey: sprite.imageKey)
    player.setDrawingBlock({ _, _ in }, forKey: sprite.imageKey)
    player.setHidden(true, forKey: sprite.imageKey)
    player.clearDynamicObjects()

    #expect(layerContentsIdentical(contentLayer.bitmapLayer?.contents, to: originalCGImage))
    #expect(contentLayer.textLayer == nil)
    #expect(contentLayer.dynamicDrawingBlock == nil)
    #expect(!contentLayer.dynamicHidden)
}

@MainActor
@Test
func playRejectsFileURLThroughRemoteURLAPI() async throws {
    let view = SVGAView()
    var failedError: SVGAViewError?
    view.onEvent = { event in
        guard case .loadFailed(let error) = event else { return }
        failedError = error
    }

    view.play(url: URL(fileURLWithPath: "/tmp/effect.svga"))
    try await Task.sleep(nanoseconds: 50_000_000)

    #expect(view.state == .failed(.unsupportedURLScheme("file")))
    #expect(failedError == .unsupportedURLScheme("file"))
}

@MainActor
@Test
func clearCancelsPendingLoad() async throws {
    SVGAURLSessionTestHooks.protocolClasses = [
        ChunkedSVGAURLProtocol.self,
        NeverFinishingSVGAURLProtocol.self
    ]

    let view = SVGAView()
    let request = URLRequest(
        url: URL(string: "https://svga-never.test/effect.svga")!,
        cachePolicy: .reloadIgnoringLocalCacheData,
        timeoutInterval: 30
    )

    view.play(request: request)
    try await Task.sleep(nanoseconds: 50_000_000)
    #expect(view.state == .loading)

    view.clear()
    try await Task.sleep(nanoseconds: 50_000_000)

    #expect(view.state == .idle)
}

@MainActor
@Test
func stopAnimationCancelsPendingLoad() async throws {
    SVGAURLSessionTestHooks.protocolClasses = [
        ChunkedSVGAURLProtocol.self,
        NeverFinishingSVGAURLProtocol.self
    ]

    let view = SVGAView()
    let request = URLRequest(
        url: URL(string: "https://svga-never.test/stop.svga")!,
        cachePolicy: .reloadIgnoringLocalCacheData,
        timeoutInterval: 30
    )

    view.play(request: request)
    try await Task.sleep(nanoseconds: 50_000_000)
    view.stopAnimation()

    #expect(view.state == .idle)
}
