# SVGAView

A lightweight, high-performance SVGA animation view for iOS, built with Swift 6 strict concurrency.

Supports both **Proto 2.x** and **JSON 1.x** SVGA formats, with audio playback, dynamic content replacement, and frame-level control.

## Requirements

- iOS 14.0+
- Swift 6.0+
- Xcode 16+

## Installation

### Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/astralchen/SVGAView.git", from: "1.0.0")
]
```

Or in Xcode: **File > Add Package Dependencies**, enter the repository URL.

## Quick Start

```swift
import SVGAView

let playerView = SVGAView(frame: CGRect(x: 0, y: 0, width: 300, height: 300))
playerView.contentMode = .scaleAspectFit
view.addSubview(playerView)

// Play from bundle
playerView.play(named: "animation")
```

## Usage

### Play from Bundle

```swift
playerView.play(named: "banner")

// From a specific bundle
playerView.play(named: "effect", in: frameworkBundle)
```

### Play from URL

```swift
let url = URL(string: "https://cdn.example.com/animation.svga")!
playerView.play(url: url)
```

### Load Without Auto-Play

Use `load(...)` when you need to await readiness before starting playback:

```swift
try await playerView.load(named: "banner")
playerView.startAnimation()

try await playerView.load(url: url)
try await playerView.load(request: URLRequest(url: url))
try await playerView.load(fileURL: localFileURL)
try await playerView.load(data: svgaData, cacheKey: "gift-v1")
```

You can also route through `SVGAViewSource` when the source is selected dynamically:

```swift
let source = SVGAViewSource.request(URLRequest(url: url))
try await playerView.load(source: source)
```

### Additional Play Sources

```swift
playerView.play(request: URLRequest(url: url))
playerView.play(fileURL: localFileURL)
playerView.play(data: svgaData, cacheKey: "gift-v1")
```

### Playback Control

```swift
playerView.startAnimation()
playerView.pauseAnimation()
playerView.stopAnimation()

// Play specific frame range
playerView.startAnimation(range: 10..<30, reverse: false)

// Jump to a frame
playerView.step(toFrame: 5, andPlay: false)

// Jump to percentage
playerView.step(toPercentage: 0.5, andPlay: true)
```

### Dynamic Content

Replace images, text, or add custom drawing to sprites at play time:

```swift
var content = SVGADynamicContent()
content.setImage(avatarImage, forKey: "avatar")
content.setAttributedText(nicknameText, forKey: "username")
content.setHidden(true, forKey: "badge")
content.setDrawingBlock({ layer, frame in
    // custom drawing each frame
}, forKey: "effect")

playerView.play(named: "gift", dynamicContent: content)
```

Update dynamic content after the SVGA has loaded:

```swift
playerView.setImage(avatarImage, forKey: "avatar")
playerView.setAttributedText(nicknameText, forKey: "username")
playerView.setHidden(false, forKey: "badge")
playerView.setDrawingBlock({ layer, frame in
    // custom drawing each frame
}, forKey: "effect")

playerView.removeImage(forKey: "avatar")
playerView.removeAttributedText(forKey: "username")
playerView.removeDrawingBlock(forKey: "effect")
playerView.removeHidden(forKey: "badge")
playerView.clearDynamicContent()
```

Image keys may be passed either as the original SVGA `imageKey` or without the file extension.

### Event Callbacks

```swift
playerView.onEvent = { event in
    switch event {
    case .stateChanged(let state):
        print("state changed: \(state)")
    case .ready:
        print("animation is ready")
    case .finished:
        print("animation finished")
    case .frameChanged(let frame):
        print("current frame: \(frame)")
    case .percentageChanged(let percentage):
        print("playback progress: \(percentage)")
    case .downloadProgress(let progress):
        print("download progress: \(progress)")
    case .loadFailed(let error):
        print("load failed: \(error)")
    }
}
```

`SVGAViewEvent` is the single callback surface for loading, playback, frame, percentage, download progress, and failure events.

`state` is exposed as `SVGAViewState` with `idle`, `loading`, `ready`, `playing`, `paused`, `stopped`, and `failed(SVGAViewError)`.

### Cancellation

```swift
playerView.cancelLoading()
playerView.clear()         // also cancels an in-flight load
playerView.stopAnimation() // cancels an in-flight load, or stops playback
```

Starting a new load cancels the previous pending load. Stale completions are ignored.

### Configuration

```swift
playerView.loops = 3              // Play 3 times (0 = infinite, default)
playerView.clearsAfterStop = true // Clear canvas after stop (default true)
playerView.fillMode = .forward    // Stay on last frame after finish
playerView.autoPlay = true        // Auto-play after loading (default true)
```

### Interface Builder

Set the custom class to `SVGAView` in Interface Builder, then configure:

- **filePath** — Bundle resource name, HTTP(S) URL, file URL, or absolute local path
- **autoPlay** — Auto-play on load

`filePath` loading is deferred until the view has finished initialization.

## Architecture

```
SVGAView (UIView)
  └── Internal animation engine
        ├── CADisplayLink (frame timing)
        ├── Sprite rendering layers
        │     ├── Bitmap layers
        │     └── Vector shape layers
        ├── Audio sync
        └── SVGA parsing and caching

Public API:
  └── SVGAView and its playback configuration types
```

- **SVGAView** — Public UIView, provides loading, playback, controls, callbacks, and dynamic content.
- Parser, model, renderer, cache, audio, and exporter types are internal implementation details.

## Security

- Path traversal protection on extracted filenames
- Decompression size limits (zlib and ZIP, 100 MB)
- Download size limit (configurable, default 50 MB)
- SHA256 cache keys
- HTTP(S)-only validation for remote URLs; local file URLs use file loading APIs
- Input range clamping (fps, frames, percentages)

## License

MIT
