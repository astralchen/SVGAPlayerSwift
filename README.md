# SVGAPlayerSwift

A lightweight, high-performance SVGA animation player for iOS, built with Swift 6 strict concurrency.

Supports both **Proto 2.x** and **JSON 1.x** SVGA formats, with audio playback, dynamic content replacement, and frame-level control.

## Requirements

- iOS 14.0+
- Swift 6.0+
- Xcode 16+

## Installation

### Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/astralchen/SVGAPlayerSwift.git", from: "1.0.0")
]
```

Or in Xcode: **File > Add Package Dependencies**, enter the repository URL.

## Quick Start

```swift
import SVGAPlayer

let playerView = SVGAPlayerView(frame: CGRect(x: 0, y: 0, width: 300, height: 300))
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

### Event Callbacks

```swift
playerView.onFinished = {
    print("animation finished")
}

playerView.onFrameChanged = { frame in
    print("current frame: \(frame)")
}

playerView.onPercentageChanged = { percentage in
    print("progress: \(percentage)")
}

playerView.onLoadFailed = { error in
    print("load failed: \(error)")
}
```

### Configuration

```swift
playerView.loops = 3              // Play 3 times (0 = infinite, default)
playerView.clearsAfterStop = true // Clear canvas after stop (default true)
playerView.fillMode = .forward    // Stay on last frame after finish
playerView.autoPlay = true        // Auto-play after loading (default true)
```

### Interface Builder

Set the custom class to `SVGAPlayerView` in Interface Builder, then configure:

- **filePath** — Bundle resource name or HTTP(S) URL string
- **autoPlay** — Auto-play on load

### Export Frames

```swift
let entity = try await SVGAParser.shared.parse(named: "animation")
let exporter = SVGAExporter()
exporter.videoItem = entity

// Export as UIImage array
let images = exporter.toImages()

// Save as PNG sequence
exporter.saveImages(to: "/path/to/output", filePrefix: "frame_")
```

## Architecture

```
SVGAPlayerView (UIView)
  └── SVGAPlayer (Animation Engine)
        ├── CADisplayLink (frame timing)
        ├── SVGAContentLayer[] (sprite rendering)
        │     ├── SVGABitmapLayer (bitmap)
        │     └── SVGAVectorLayer (vector shapes)
        └── SVGAAudioLayer[] (audio sync)

SVGAParser (actor)
  ├── SVGADecompressor (zlib / ZIP)
  └── SVGACacheStore (memory cache)
```

- **SVGAPlayerView** — Public UIView, provides play/stop/callback API
- **SVGAPlayer** — Pure animation engine, no UIView dependency
- **SVGAParser** — Async SVGA file parser with built-in caching
- **SVGAExporter** — Frame-by-frame image export

## Security

- Path traversal protection on extracted filenames
- Decompression size limits (zlib and ZIP, 100 MB)
- Download size limit (configurable, default 50 MB)
- SHA256 cache keys
- HTTPS-only for URL scheme validation
- Input range clamping (fps, frames, percentages)

## License

MIT
