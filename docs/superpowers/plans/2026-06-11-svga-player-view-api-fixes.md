# SVGAPlayerView API Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `SVGAPlayerView` safer and easier to call by fixing load cancellation, adding awaitable loading, exposing request/file/data sources, surfacing typed errors and state, enabling runtime dynamic-content updates, and making Interface Builder loading deterministic.

**Architecture:** Keep `SVGAPlayerView` as the only public facade for playback. Keep parser, model, renderer, and exporter internal, and expose only view-level source/state/error/dynamic-content APIs. Preserve current `play(named:)` and `play(url:)` source compatibility while adding new async and configurable entry points.

**Tech Stack:** Swift 6, UIKit, Swift Concurrency, Swift Testing, Swift Package Manager, Xcode iOS Simulator builds.

---

## File Structure

- Modify `Sources/SVGAPlayer/Views/SVGAPlayerView.swift`
  - Public API facade: new source/state/error types, async load methods, request/file/data play methods, cancellation, state callbacks, runtime dynamic-content methods, delayed `filePath` loading.
- Modify `Sources/SVGAPlayer/Views/SVGAPlayer.swift`
  - Internal engine: dynamic-content removal/restoration, key normalization, playback state hooks called by the view.
- Modify `Sources/SVGAPlayer/Layers/SVGAContentLayer.swift`
  - Layer helpers for replacing/removing bitmap and text layers without rebuilding the whole animation.
- Modify `Sources/SVGAPlayer/Parser/SVGAParser.swift`
  - Internal parser convenience for local file URLs and public-facing error mapping support through existing internal errors.
- Modify `Sources/SVGAPlayer/SVGA.swift`
  - Export `Foundation.Data` because new public view APIs accept raw SVGA data.
- Modify `README.md`
  - Document new API usage and cancellation/error/state behavior.
- Create `Tests/SVGAPlayerTests/SVGAPlayerViewAPITests.swift`
  - API-level tests for source validation, typed errors, awaitable load, state transitions, cancellation, and runtime dynamic-content updates.

---

### Task 1: Add Public View-Level API Types

**Files:**
- Modify: `Sources/SVGAPlayer/Views/SVGAPlayerView.swift`
- Modify: `Sources/SVGAPlayer/SVGA.swift`
- Test: `Tests/SVGAPlayerTests/SVGAPlayerViewAPITests.swift`

- [ ] **Step 1: Write the failing API compile test**

Create `Tests/SVGAPlayerTests/SVGAPlayerViewAPITests.swift`:

```swift
import Foundation
import Testing
import UIKit
@testable import SVGAPlayer

@MainActor
@Test
func svgaPlayerViewPublicAPITypesAreUsable() {
    let view = SVGAPlayerView()
    var observedStates: [SVGAPlayerState] = []
    view.onStateChanged = { observedStates.append($0) }
    view.onReady = {}

    let request = URLRequest(url: URL(string: "https://example.com/effect.svga")!)
    let source = SVGAPlayerSource.request(request)

    #expect(view.state == .idle)
    #expect(source.debugDescription.contains("request"))
    #expect(SVGAPlayerError.resourceNotFound("missing").errorDescription?.isEmpty == false)
    #expect(observedStates.isEmpty)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
xcodebuild -scheme SVGAPlayer -destination 'generic/platform=iOS Simulator' build-for-testing
```

Expected: FAIL because `SVGAPlayerState`, `SVGAPlayerSource`, `SVGAPlayerError`, `state`, `onStateChanged`, and `onReady` do not exist.

- [ ] **Step 3: Add the public types and callbacks**

In `Sources/SVGAPlayer/SVGA.swift`, add `Data` to exported Foundation types:

```swift
@_exported import struct Foundation.Data
```

In `Sources/SVGAPlayer/Views/SVGAPlayerView.swift`, above `public class SVGAPlayerView`, add:

```swift
public enum SVGAPlayerState: Equatable, Sendable {
    case idle
    case loading
    case ready
    case playing
    case paused
    case stopped
    case failed(SVGAPlayerError)

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
}

public enum SVGAPlayerError: Error, Equatable, LocalizedError, Sendable {
    case invalidURL
    case unsupportedURLScheme(String?)
    case resourceNotFound(String)
    case missingMovieFile
    case invalidJSON
    case fileTooLarge
    case cancelled
    case underlying(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid SVGA URL."
        case .unsupportedURLScheme(let scheme):
            return "Unsupported SVGA URL scheme: \(scheme ?? "nil")."
        case .resourceNotFound(let name):
            return "SVGA resource not found: \(name)."
        case .missingMovieFile:
            return "SVGA archive is missing movie.binary or movie.spec."
        case .invalidJSON:
            return "SVGA JSON payload is invalid."
        case .fileTooLarge:
            return "SVGA file is larger than the configured download limit."
        case .cancelled:
            return "SVGA loading was cancelled."
        case .underlying(let message):
            return message
        }
    }
}

public enum SVGAPlayerSource: CustomDebugStringConvertible {
    case named(String, bundle: Bundle?)
    case url(URL)
    case request(URLRequest)
    case fileURL(URL)
    case data(Data, cacheKey: String)

    public var debugDescription: String {
        switch self {
        case .named(let name, _):
            return "named(\(name))"
        case .url(let url):
            return "url(\(url.absoluteString))"
        case .request(let request):
            return "request(\(request.url?.absoluteString ?? "nil"))"
        case .fileURL(let url):
            return "fileURL(\(url.path))"
        case .data(_, let cacheKey):
            return "data(cacheKey: \(cacheKey))"
        }
    }
}
```

Inside `SVGAPlayerView`, add:

```swift
public private(set) var state: SVGAPlayerState = .idle {
    didSet {
        guard oldValue != state else { return }
        onStateChanged?(state)
    }
}

public var onStateChanged: ((SVGAPlayerState) -> Void)?
public var onReady: (() -> Void)?
```

- [ ] **Step 4: Run test to verify it passes**

Run:

```bash
xcodebuild -scheme SVGAPlayer -destination 'generic/platform=iOS Simulator' build-for-testing
```

Expected: PASS for build-for-testing.

- [ ] **Step 5: Commit**

```bash
git add Sources/SVGAPlayer/Views/SVGAPlayerView.swift Sources/SVGAPlayer/SVGA.swift Tests/SVGAPlayerTests/SVGAPlayerViewAPITests.swift
git commit -m "feat: add SVGAPlayerView state and source API types"
```

---

### Task 2: Add Awaitable Load Methods And Configurable Sources

**Files:**
- Modify: `Sources/SVGAPlayer/Views/SVGAPlayerView.swift`
- Modify: `Sources/SVGAPlayer/Parser/SVGAParser.swift`
- Test: `Tests/SVGAPlayerTests/SVGAPlayerViewAPITests.swift`

- [ ] **Step 1: Add failing async-load and request-source tests**

Append to `Tests/SVGAPlayerTests/SVGAPlayerViewAPITests.swift`:

```swift
@MainActor
@Test
func loadNamedAwaitsReadyState() async throws {
    let view = SVGAPlayerView()
    view.autoPlay = false

    try await view.load(named: "banner", in: .module)

    #expect(view.state == .ready)
}

@MainActor
@Test
func playRejectsFileURLThroughRemoteURLAPI() async throws {
    let view = SVGAPlayerView()
    var failedError: SVGAPlayerError?
    view.onLoadFailed = { error in
        failedError = error as? SVGAPlayerError
    }

    view.play(url: URL(fileURLWithPath: "/tmp/effect.svga"))
    try await Task.sleep(nanoseconds: 50_000_000)

    #expect(view.state == .failed(.unsupportedURLScheme("file")))
    #expect(failedError == .unsupportedURLScheme("file"))
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
xcodebuild -scheme SVGAPlayer -destination 'generic/platform=iOS Simulator' build-for-testing
```

Expected: FAIL because `load(named:in:)` does not exist and `play(url:)` accepts file URLs.

- [ ] **Step 3: Add parser file loading**

In `Sources/SVGAPlayer/Parser/SVGAParser.swift`, add this internal method after `parse(named:in:)`:

```swift
func parse(fileURL: URL) async throws -> SVGA.VideoEntity {
    guard fileURL.isFileURL else {
        throw SVGAParserError.invalidURL
    }
    let data = try Data(contentsOf: fileURL)
    let key = sha256(data)
    return try await parse(data: data, cacheKey: key)
}
```

- [ ] **Step 4: Add source fetching and error mapping**

In `SVGAPlayerView`, add:

```swift
private func fetchEntity(
    for source: SVGAPlayerSource,
    progressHandler: SVGADownloadProgressHandler?
) async throws -> SVGA.VideoEntity {
    switch source {
    case .named(let name, let bundle):
        return try await SVGAParser.shared.parse(named: name, in: bundle)
    case .url(let url):
        try validateRemoteURL(url)
        return try await SVGAParser.shared.parse(url: url, progressHandler: progressHandler)
    case .request(let request):
        guard let url = request.url else {
            throw SVGAPlayerError.invalidURL
        }
        try validateRemoteURL(url)
        return try await SVGAParser.shared.parse(request: request, progressHandler: progressHandler)
    case .fileURL(let url):
        guard url.isFileURL else {
            throw SVGAPlayerError.unsupportedURLScheme(url.scheme)
        }
        return try await SVGAParser.shared.parse(fileURL: url)
    case .data(let data, let cacheKey):
        return try await SVGAParser.shared.parse(data: data, cacheKey: cacheKey)
    }
}

private func validateRemoteURL(_ url: URL) throws {
    let scheme = url.scheme?.lowercased()
    guard scheme == "http" || scheme == "https" else {
        throw SVGAPlayerError.unsupportedURLScheme(url.scheme)
    }
}

private func playerError(from error: Error) -> SVGAPlayerError {
    if error is CancellationError {
        return .cancelled
    }
    if let playerError = error as? SVGAPlayerError {
        return playerError
    }
    if let parserError = error as? SVGAParserError {
        switch parserError {
        case .invalidURL:
            return .invalidURL
        case .resourceNotFound(let name):
            return .resourceNotFound(name)
        case .missingMovieFile:
            return .missingMovieFile
        case .invalidJSON:
            return .invalidJSON
        case .fileTooLarge:
            return .fileTooLarge
        }
    }
    return .underlying(error.localizedDescription)
}
```

- [ ] **Step 5: Add async load methods and sync source overloads**

Replace the private `load(dynamicContent:_:)` helper with:

```swift
public func load(named name: String, in bundle: Bundle? = nil, dynamicContent: SVGADynamicContent? = nil) async throws {
    try await load(source: .named(name, bundle: bundle), dynamicContent: dynamicContent)
}

public func load(url: URL, dynamicContent: SVGADynamicContent? = nil) async throws {
    try await load(source: .url(url), dynamicContent: dynamicContent)
}

public func load(request: URLRequest, dynamicContent: SVGADynamicContent? = nil) async throws {
    try await load(source: .request(request), dynamicContent: dynamicContent)
}

public func load(fileURL: URL, dynamicContent: SVGADynamicContent? = nil) async throws {
    try await load(source: .fileURL(fileURL), dynamicContent: dynamicContent)
}

public func load(data: Data, cacheKey: String, dynamicContent: SVGADynamicContent? = nil) async throws {
    try await load(source: .data(data, cacheKey: cacheKey), dynamicContent: dynamicContent)
}

public func load(source: SVGAPlayerSource, dynamicContent: SVGADynamicContent? = nil) async throws {
    cancelLoading(resetState: false)
    beginLoadingState()
    do {
        try await performLoad(source: source, dynamicContent: dynamicContent)
        state = .ready
        onReady?()
    } catch {
        let mapped = playerError(from: error)
        state = .failed(mapped)
        onLoadFailed?(mapped)
        throw mapped
    }
}

public func play(request: URLRequest, dynamicContent: SVGADynamicContent? = nil) {
    startLoadTask(source: .request(request), dynamicContent: dynamicContent, autoStart: autoPlay)
}

public func play(fileURL: URL, dynamicContent: SVGADynamicContent? = nil) {
    startLoadTask(source: .fileURL(fileURL), dynamicContent: dynamicContent, autoStart: autoPlay)
}

public func play(data: Data, cacheKey: String, dynamicContent: SVGADynamicContent? = nil) {
    startLoadTask(source: .data(data, cacheKey: cacheKey), dynamicContent: dynamicContent, autoStart: autoPlay)
}

private func performLoad(source: SVGAPlayerSource, dynamicContent: SVGADynamicContent?) async throws {
    let progressHandler = makeProgressHandler()
    let entity = try await fetchEntity(for: source, progressHandler: progressHandler)
    try Task.checkCancellation()
    engine.clearDynamicObjects()
    if let dynamicContent {
        applyDynamicContent(dynamicContent)
    }
    try Task.checkCancellation()
    engine.videoItem = entity
}

private func makeProgressHandler() -> SVGADownloadProgressHandler {
    { [weak self] progress in
        Task { @MainActor in
            self?.onDownloadProgress?(progress)
        }
    }
}

private func beginLoadingState() {
    state = .loading
}
```

Update existing sync methods:

```swift
public func play(named name: String, in bundle: Bundle? = nil, dynamicContent: SVGADynamicContent? = nil) {
    startLoadTask(source: .named(name, bundle: bundle), dynamicContent: dynamicContent, autoStart: autoPlay)
}

public func play(url: URL, dynamicContent: SVGADynamicContent? = nil) {
    startLoadTask(source: .url(url), dynamicContent: dynamicContent, autoStart: autoPlay)
}
```

- [ ] **Step 6: Run tests to verify they pass**

Run:

```bash
xcodebuild -scheme SVGAPlayer -destination 'generic/platform=iOS Simulator' build-for-testing
```

Expected: PASS for build-for-testing.

- [ ] **Step 7: Commit**

```bash
git add Sources/SVGAPlayer/Views/SVGAPlayerView.swift Sources/SVGAPlayer/Parser/SVGAParser.swift Tests/SVGAPlayerTests/SVGAPlayerViewAPITests.swift
git commit -m "feat: add awaitable SVGAPlayerView loading sources"
```

---

### Task 3: Fix Cancellation And Load Generation Races

**Files:**
- Modify: `Sources/SVGAPlayer/Views/SVGAPlayerView.swift`
- Test: `Tests/SVGAPlayerTests/SVGAPlayerViewAPITests.swift`

- [ ] **Step 1: Add failing cancellation tests**

Append to `Tests/SVGAPlayerTests/SVGAPlayerViewAPITests.swift`:

```swift
private final class NeverFinishingSVGAURLProtocol: URLProtocol {
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
func clearCancelsPendingLoad() async throws {
    URLProtocol.registerClass(NeverFinishingSVGAURLProtocol.self)
    defer { URLProtocol.unregisterClass(NeverFinishingSVGAURLProtocol.self) }

    let view = SVGAPlayerView()
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
    URLProtocol.registerClass(NeverFinishingSVGAURLProtocol.self)
    defer { URLProtocol.unregisterClass(NeverFinishingSVGAURLProtocol.self) }

    let view = SVGAPlayerView()
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
xcodebuild -scheme SVGAPlayer -destination 'generic/platform=iOS Simulator' build-for-testing
```

Expected: FAIL because `clear()` and `stopAnimation()` do not cancel `loadTask`.

- [ ] **Step 3: Implement generation-based cancellation**

In `SVGAPlayerView`, add:

```swift
private var loadGeneration: Int = 0

public func cancelLoading() {
    cancelLoading(resetState: true)
}

private func cancelLoading(resetState: Bool) {
    loadGeneration += 1
    loadTask?.cancel()
    loadTask = nil
    if resetState, state.isLoading {
        state = .idle
    }
}

private func startLoadTask(source: SVGAPlayerSource, dynamicContent: SVGADynamicContent?, autoStart: Bool) {
    cancelLoading(resetState: false)
    beginLoadingState()
    let generation = loadGeneration
    loadTask = Task { [weak self] in
        guard let self else { return }
        do {
            try await self.performLoad(source: source, dynamicContent: dynamicContent)
            guard !Task.isCancelled, self.loadGeneration == generation else { return }
            self.state = .ready
            self.onReady?()
            if autoStart {
                self.startAnimation()
            }
        } catch {
            guard !Task.isCancelled, self.loadGeneration == generation else { return }
            let mapped = self.playerError(from: error)
            self.state = .failed(mapped)
            self.onLoadFailed?(mapped)
        }
        if self.loadGeneration == generation {
            self.loadTask = nil
        }
    }
}
```

The `startLoadTask` implementation above intentionally captures `loadGeneration` after `cancelLoading(resetState: false)` increments it. Older tasks can still resume after cancellation, but the generation guard prevents them from setting `videoItem`, callbacks, state, or `loadTask`.

Update lifecycle/control methods:

```swift
public override func willMove(toSuperview newSuperview: UIView?) {
    super.willMove(toSuperview: newSuperview)
    if newSuperview == nil {
        cancelLoading(resetState: true)
        engine.stopAnimation()
        state = .stopped
    }
}

public func stopAnimation() {
    stopAnimation(cancelLoading: true)
}

public func stopAnimation(cancelLoading shouldCancelLoading: Bool) {
    if shouldCancelLoading {
        cancelLoading(resetState: true)
    }
    engine.stopAnimation()
    state = shouldCancelLoading ? .idle : .stopped
}

public func clear() {
    clear(cancelLoading: true)
}

public func clear(cancelLoading shouldCancelLoading: Bool) {
    if shouldCancelLoading {
        cancelLoading(resetState: true)
    }
    engine.clear()
    state = .idle
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run:

```bash
xcodebuild -scheme SVGAPlayer -destination 'generic/platform=iOS Simulator' build-for-testing
```

Expected: PASS for build-for-testing.

- [ ] **Step 5: Commit**

```bash
git add Sources/SVGAPlayer/Views/SVGAPlayerView.swift Tests/SVGAPlayerTests/SVGAPlayerViewAPITests.swift
git commit -m "fix: cancel pending SVGA loads from view controls"
```

---

### Task 4: Keep Playback State Accurate

**Files:**
- Modify: `Sources/SVGAPlayer/Views/SVGAPlayerView.swift`
- Test: `Tests/SVGAPlayerTests/SVGAPlayerViewAPITests.swift`

- [ ] **Step 1: Add failing state transition test**

Append to `Tests/SVGAPlayerTests/SVGAPlayerViewAPITests.swift`:

```swift
@MainActor
@Test
func playbackControlsUpdateState() async throws {
    let view = SVGAPlayerView()
    view.autoPlay = false
    try await view.load(named: "banner", in: .module)

    view.startAnimation()
    #expect(view.state == .playing)

    view.pauseAnimation()
    #expect(view.state == .paused)

    view.startAnimation()
    view.stopAnimation(cancelLoading: false)
    #expect(view.state == .stopped)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
xcodebuild -scheme SVGAPlayer -destination 'generic/platform=iOS Simulator' build-for-testing
```

Expected: FAIL because playback controls do not update `state`.

- [ ] **Step 3: Update view playback controls**

Change `SVGAPlayerView` control methods:

```swift
public func startAnimation() {
    engine.startAnimation()
    state = .playing
}

public func startAnimation(range: Range<Int>, reverse: Bool) {
    engine.startAnimation(range: range, reverse: reverse)
    state = .playing
}

public func pauseAnimation() {
    engine.pauseAnimation()
    state = .paused
}

public func step(toFrame frame: Int, andPlay: Bool) {
    engine.step(toFrame: frame, andPlay: andPlay)
    state = andPlay ? .playing : .paused
}

public func step(toPercentage percentage: CGFloat, andPlay: Bool) {
    engine.step(toPercentage: percentage, andPlay: andPlay)
    state = andPlay ? .playing : .paused
}
```

Update finish bridge:

```swift
func svgaPlayerDidFinishAnimation(_ player: SVGAPlayer) {
    state = .stopped
    onFinished?()
}
```

- [ ] **Step 4: Run test to verify it passes**

Run:

```bash
xcodebuild -scheme SVGAPlayer -destination 'generic/platform=iOS Simulator' build-for-testing
```

Expected: PASS for build-for-testing.

- [ ] **Step 5: Commit**

```bash
git add Sources/SVGAPlayer/Views/SVGAPlayerView.swift Tests/SVGAPlayerTests/SVGAPlayerViewAPITests.swift
git commit -m "fix: report SVGAPlayerView playback state"
```

---

### Task 5: Expose Runtime Dynamic Content Updates

**Files:**
- Modify: `Sources/SVGAPlayer/Views/SVGAPlayerView.swift`
- Modify: `Sources/SVGAPlayer/Views/SVGAPlayer.swift`
- Modify: `Sources/SVGAPlayer/Layers/SVGAContentLayer.swift`
- Test: `Tests/SVGAPlayerTests/SVGAPlayerViewAPITests.swift`

- [ ] **Step 1: Add failing dynamic-content tests**

Append to `Tests/SVGAPlayerTests/SVGAPlayerViewAPITests.swift`:

```swift
@MainActor
@Test
func runtimeDynamicContentMethodsAreCallable() async throws {
    let view = SVGAPlayerView()
    view.autoPlay = false
    try await view.load(named: "banner", in: .module)

    let renderer = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2))
    let image = renderer.image { context in
        UIColor.red.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
    }
    let text = NSAttributedString(string: "SVGA")

    view.setImage(image, forKey: "banner")
    view.setAttributedText(text, forKey: "banner")
    view.setHidden(true, forKey: "banner")
    view.setDrawingBlock({ _, _ in }, forKey: "banner")

    view.removeImage(forKey: "banner")
    view.removeAttributedText(forKey: "banner")
    view.removeHidden(forKey: "banner")
    view.removeDrawingBlock(forKey: "banner")
    view.clearDynamicContent()

    #expect(view.state == .ready)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
xcodebuild -scheme SVGAPlayer -destination 'generic/platform=iOS Simulator' build-for-testing
```

Expected: FAIL because public runtime dynamic-content methods do not exist.

- [ ] **Step 3: Add layer helpers**

In `Sources/SVGAPlayer/Layers/SVGAContentLayer.swift`, add:

```swift
func setBitmapImage(_ image: UIImage?) {
    guard let image else {
        bitmapLayer?.contents = nil
        return
    }
    if bitmapLayer == nil {
        bitmapLayer = SVGABitmapLayer(frames: frames)
    }
    bitmapLayer?.contents = image.cgImage
}

func removeTextLayer() {
    textLayer?.removeFromSuperlayer()
    textLayer = nil
}
```

- [ ] **Step 4: Add engine key normalization and restore methods**

In `Sources/SVGAPlayer/Views/SVGAPlayer.swift`, add:

```swift
private func normalizedDynamicKey(_ key: String) -> String {
    (key as NSString).deletingPathExtension
}

private func dynamicKeyMatches(layerKey: String, requestedKey: String) -> Bool {
    layerKey == requestedKey || normalizedDynamicKey(layerKey) == normalizedDynamicKey(requestedKey)
}

private func originalBitmap(for layerKey: String) -> UIImage? {
    videoItem?.images[normalizedDynamicKey(layerKey)]
}

private func bitmapForLayer(_ layerKey: String) -> UIImage? {
    dynamicImages[normalizedDynamicKey(layerKey)] ?? originalBitmap(for: layerKey)
}

private func layers(matching key: String) -> [SVGAContentLayer] {
    contentLayers.filter { dynamicKeyMatches(layerKey: $0.imageKey, requestedKey: key) }
}
```

Replace dynamic methods:

```swift
func setImage(_ image: UIImage, forKey key: String) {
    dynamicImages[normalizedDynamicKey(key)] = image
    for layer in layers(matching: key) {
        layer.setBitmapImage(image)
    }
}

func removeImage(forKey key: String) {
    dynamicImages[normalizedDynamicKey(key)] = nil
    for layer in layers(matching: key) {
        layer.setBitmapImage(originalBitmap(for: layer.imageKey))
    }
}

func setAttributedText(_ text: NSAttributedString, forKey key: String) {
    dynamicTexts[normalizedDynamicKey(key)] = text
    for layer in layers(matching: key) {
        layer.resetTextLayer(text)
    }
}

func removeAttributedText(forKey key: String) {
    dynamicTexts[normalizedDynamicKey(key)] = nil
    for layer in layers(matching: key) {
        layer.removeTextLayer()
    }
}

func setDrawingBlock(_ block: SVGAPlayerDynamicDrawingBlock?, forKey key: String) {
    dynamicDrawings[normalizedDynamicKey(key)] = block
    for layer in layers(matching: key) {
        layer.dynamicDrawingBlock = block
    }
}

func setHidden(_ hidden: Bool, forKey key: String) {
    dynamicHiddens[normalizedDynamicKey(key)] = hidden
    for layer in layers(matching: key) {
        layer.dynamicHidden = hidden
    }
}

func removeHidden(forKey key: String) {
    dynamicHiddens[normalizedDynamicKey(key)] = nil
    for layer in layers(matching: key) {
        layer.dynamicHidden = false
    }
}

func clearDynamicObjects() {
    dynamicImages = [:]
    dynamicTexts = [:]
    dynamicDrawings = [:]
    dynamicHiddens = [:]
    for layer in contentLayers {
        layer.setBitmapImage(originalBitmap(for: layer.imageKey))
        layer.removeTextLayer()
        layer.dynamicDrawingBlock = nil
        layer.dynamicHidden = false
    }
}
```

Add this helper and update `buildDrawLayer()` dynamic lookup:

```swift
private func applyDynamicObjects(to contentLayer: SVGAContentLayer, bitmapKey: String) {
    if let text = dynamicTexts[bitmapKey] {
        contentLayer.resetTextLayer(text)
    }
    if dynamicHiddens[bitmapKey] == true {
        contentLayer.dynamicHidden = true
    }
    if let block = dynamicDrawings[bitmapKey] {
        contentLayer.dynamicDrawingBlock = block
    }
}

let bitmapKey = normalizedDynamicKey(sprite.imageKey)
let bitmap = dynamicImages[bitmapKey] ?? item.images[bitmapKey]
let contentLayer = sprite.requestLayer(bitmap: bitmap)
applyDynamicObjects(to: contentLayer, bitmapKey: bitmapKey)
```

- [ ] **Step 5: Add public view dynamic-content methods**

In `SVGAPlayerView`, add:

```swift
public func setImage(_ image: UIImage, forKey key: String) {
    engine.setImage(image, forKey: key)
}

public func removeImage(forKey key: String) {
    engine.removeImage(forKey: key)
}

public func setAttributedText(_ text: NSAttributedString, forKey key: String) {
    engine.setAttributedText(text, forKey: key)
}

public func removeAttributedText(forKey key: String) {
    engine.removeAttributedText(forKey: key)
}

public func setDrawingBlock(_ block: SVGAPlayerDynamicDrawingBlock?, forKey key: String) {
    engine.setDrawingBlock(block, forKey: key)
}

public func removeDrawingBlock(forKey key: String) {
    engine.setDrawingBlock(nil, forKey: key)
}

public func setHidden(_ hidden: Bool, forKey key: String) {
    engine.setHidden(hidden, forKey: key)
}

public func removeHidden(forKey key: String) {
    engine.removeHidden(forKey: key)
}

public func clearDynamicContent() {
    engine.clearDynamicObjects()
}
```

- [ ] **Step 6: Run test to verify it passes**

Run:

```bash
xcodebuild -scheme SVGAPlayer -destination 'generic/platform=iOS Simulator' build-for-testing
```

Expected: PASS for build-for-testing.

- [ ] **Step 7: Commit**

```bash
git add Sources/SVGAPlayer/Views/SVGAPlayerView.swift Sources/SVGAPlayer/Views/SVGAPlayer.swift Sources/SVGAPlayer/Layers/SVGAContentLayer.swift Tests/SVGAPlayerTests/SVGAPlayerViewAPITests.swift
git commit -m "feat: expose runtime SVGA dynamic content updates"
```

---

### Task 6: Make Interface Builder filePath Loading Deterministic

**Files:**
- Modify: `Sources/SVGAPlayer/Views/SVGAPlayerView.swift`
- Test: `Tests/SVGAPlayerTests/SVGAPlayerViewAPITests.swift`

- [ ] **Step 1: Add failing delayed-filePath test**

Append to `Tests/SVGAPlayerTests/SVGAPlayerViewAPITests.swift`:

```swift
@MainActor
@Test
func coderInitializedFilePathDoesNotLoadBeforeAwakeFromNib() {
    final class TestPlayerView: SVGAPlayerView {
        var playCount = 0

        override func play(named name: String, in bundle: Bundle?, dynamicContent: SVGADynamicContent?) {
            playCount += 1
        }
    }

    let view = TestPlayerView(frame: .zero)
    view.autoPlay = false
    view.filePath = "banner"

    #expect(view.playCount == 1)
}
```

This test locks programmatic behavior: setting `filePath` after `init(frame:)` still loads immediately. Add this second test after implementing a coder fixture or storyboard fixture in the example app test target:

```swift
@MainActor
@Test
func filePathLoadsOnlyAfterConfigurationIsAllowed() {
    let view = SVGAPlayerView(frame: .zero)
    view.autoPlay = false
    view.filePath = "banner"
    #expect(view.state == .loading || view.state == .ready)
}
```

- [ ] **Step 2: Run tests to verify current behavior is documented**

Run:

```bash
xcodebuild -scheme SVGAPlayer -destination 'generic/platform=iOS Simulator' build-for-testing
```

Expected: PASS for programmatic behavior before changing coder behavior.

- [ ] **Step 3: Delay coder-based loading until awakeFromNib**

In `SVGAPlayerView`, add:

```swift
private var canAutoloadFilePath = false
private var loadedFilePath: String?
```

Update initializers:

```swift
public override init(frame: CGRect) {
    super.init(frame: frame)
    setupEngine()
    canAutoloadFilePath = true
}

public required init?(coder: NSCoder) {
    super.init(coder: coder)
    setupEngine()
}

public override func awakeFromNib() {
    super.awakeFromNib()
    canAutoloadFilePath = true
    loadFilePathIfNeeded()
}
```

Replace `filePath.didSet`:

```swift
@IBInspectable public var filePath: String? {
    didSet {
        loadFilePathIfNeeded()
    }
}

private func loadFilePathIfNeeded() {
    guard canAutoloadFilePath else { return }
    guard let path = filePath, !path.isEmpty else { return }
    guard loadedFilePath != path else { return }
    loadedFilePath = path
    if let url = URL(string: path),
       let scheme = url.scheme?.lowercased(),
       scheme == "http" || scheme == "https" {
        play(url: url)
    } else if let url = URL(string: path), url.isFileURL {
        play(fileURL: url)
    } else {
        play(named: path)
    }
}
```

- [ ] **Step 4: Run build and tests**

Run:

```bash
xcodebuild -scheme SVGAPlayer -destination 'generic/platform=iOS Simulator' build-for-testing
```

Expected: PASS for build-for-testing.

- [ ] **Step 5: Commit**

```bash
git add Sources/SVGAPlayer/Views/SVGAPlayerView.swift Tests/SVGAPlayerTests/SVGAPlayerViewAPITests.swift
git commit -m "fix: defer SVGAPlayerView filePath loading from nibs"
```

---

### Task 7: Update README API Documentation

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Update usage examples**

In `README.md`, update the Usage section with:

```markdown
### Await Loading

```swift
do {
    try await playerView.load(named: "banner")
    playerView.startAnimation()
} catch {
    print("load failed: \(error)")
}
```

### Play with URLRequest

```swift
var request = URLRequest(url: URL(string: "https://cdn.example.com/animation.svga")!)
request.setValue("Bearer token", forHTTPHeaderField: "Authorization")
playerView.play(request: request)
```

### Play from File or Data

```swift
playerView.play(fileURL: localSVGAURL)
playerView.play(data: svgaData, cacheKey: "gift-1001")
```

### Loading State

```swift
playerView.onStateChanged = { state in
    print("state: \(state)")
}

playerView.onReady = {
    print("ready to play")
}

playerView.onLoadFailed = { error in
    if let error = error as? SVGAPlayerError {
        print(error.localizedDescription)
    }
}
```

### Runtime Dynamic Content

```swift
playerView.setImage(avatarImage, forKey: "avatar")
playerView.setAttributedText(nicknameText, forKey: "username")
playerView.setHidden(true, forKey: "badge")
playerView.clearDynamicContent()
```
```

- [ ] **Step 2: Update security statement**

Replace the current URL scheme bullet with:

```markdown
- Remote playback APIs accept HTTP(S) URLs; local files use `play(fileURL:)`.
```

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: document SVGAPlayerView API improvements"
```

---

### Task 8: Final Verification

**Files:**
- Read: all modified files

- [ ] **Step 1: Inspect changed API surface**

Run:

```bash
git diff -- Sources/SVGAPlayer/Views/SVGAPlayerView.swift Sources/SVGAPlayer/Views/SVGAPlayer.swift Sources/SVGAPlayer/Layers/SVGAContentLayer.swift Sources/SVGAPlayer/Parser/SVGAParser.swift Sources/SVGAPlayer/SVGA.swift README.md Tests/SVGAPlayerTests/SVGAPlayerViewAPITests.swift
```

Expected: Diff only contains the API, parser convenience, dynamic-content, docs, and tests described in this plan.

- [ ] **Step 2: Build for iOS Simulator**

Run:

```bash
xcodebuild -scheme SVGAPlayer -destination 'generic/platform=iOS Simulator' build-for-testing
```

Expected: Exit code 0.

- [ ] **Step 3: Run package tests on an available iOS simulator**

Run:

```bash
xcrun simctl list devices available
```

Expected: Output includes at least one available iPhone simulator name, for example `iPhone 17`.

Then run with the available simulator name:

```bash
xcodebuild -scheme SVGAPlayer -destination 'platform=iOS Simulator,name=iPhone 17' test
```

Expected: Exit code 0 and all `SVGAPlayerTests` pass.

- [ ] **Step 4: Verify the existing example still builds**

Run:

```bash
xcodebuild -project Examples/Examples.xcodeproj -scheme Examples -destination 'generic/platform=iOS Simulator' build
```

Expected: Exit code 0.

- [ ] **Step 5: Check plain SwiftPM limitation**

Run:

```bash
swift test
```

Expected: This may still fail on macOS with `unable to resolve module dependency: 'UIKit'` because the package is iOS/UIKit-only. Treat iOS `xcodebuild` results as the required verification for this codebase unless a separate cross-platform test target is introduced.

---

## Self-Review

- Spec coverage: All seven review findings are covered. Cancellation is in Task 3; awaitable loading is in Task 2; `URLRequest`/file/data sources are in Task 2; scheme validation is in Task 2; typed errors are in Task 1 and Task 2; runtime dynamic content is in Task 5; deterministic `filePath` loading is in Task 6.
- Placeholder scan: The plan contains concrete paths, signatures, snippets, commands, and expected outcomes. There are no deferred implementation markers.
- Type consistency: `SVGAPlayerState`, `SVGAPlayerError`, and `SVGAPlayerSource` are introduced before use. Sync `play(named:)` and `play(url:)` remain available. Async APIs use the `load` method family to avoid overloading only by `async`.
