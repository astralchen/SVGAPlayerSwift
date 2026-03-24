import UIKit
import AVFoundation

// MARK: - Public types

public typealias SVGAPlayerDynamicDrawingBlock = @MainActor @Sendable (CALayer, Int) -> Void

public enum SVGAFillMode: Sendable {
    case forward, backward, clear
}

@MainActor
public protocol SVGAPlayerDelegate: AnyObject {
    func svgaPlayerDidFinishAnimation(_ player: SVGAPlayer)
    func svgaPlayer(_ player: SVGAPlayer, didAnimateToFrame frame: Int)
    func svgaPlayer(_ player: SVGAPlayer, didAnimateToPercentage percentage: CGFloat)
}

public extension SVGAPlayerDelegate {
    func svgaPlayerDidFinishAnimation(_ player: SVGAPlayer) {}
    func svgaPlayer(_ player: SVGAPlayer, didAnimateToFrame frame: Int) {}
    func svgaPlayer(_ player: SVGAPlayer, didAnimateToPercentage percentage: CGFloat) {}
}

// MARK: - SVGAPlayer

@MainActor
public class SVGAPlayer: UIView {

    // MARK: Public properties

    public var videoItem: SVGAVideoEntity? {
        didSet {
            guard let item = videoItem else { return }
            currentRange = 0..<item.frames
            reversing = false
            currentFrame = 0
            loopCount = 0
            clear()
            draw()
        }
    }

    public var loops: Int = 0
    public var clearsAfterStop: Bool = true
    public var fillMode: SVGAFillMode = .forward
    public var mainRunLoopMode: RunLoop.Mode = .common
    public weak var delegate: SVGAPlayerDelegate?

    // MARK: Private state

    private var drawLayer: CALayer?
    private var audioLayers: [SVGAAudioLayer] = []
    private var displayLink: CADisplayLink?
    private var currentFrame: Int = 0
    private var contentLayers: [SVGAContentLayer] = []
    private var dynamicImages: [String: UIImage] = [:]
    private var dynamicTexts: [String: NSAttributedString] = [:]
    private var dynamicDrawings: [String: SVGAPlayerDynamicDrawingBlock] = [:]
    private var dynamicHiddens: [String: Bool] = [:]
    private var loopCount: Int = 0
    private var currentRange: Range<Int> = 0..<0
    private var forwardAnimating: Bool = false
    private var reversing: Bool = false

    // MARK: Init
    public override init(frame: CGRect) {
        super.init(frame: frame)
        contentMode = .top
        clearsAfterStop = true
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        contentMode = .top
        clearsAfterStop = true
    }

    public override func willMove(toSuperview newSuperview: UIView?) {
        super.willMove(toSuperview: newSuperview)
        if newSuperview == nil {
            stopAnimation(clear: true)
        }
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        resize()
    }

    // MARK: - Playback control

    public func startAnimation() {
        guard let item = videoItem else { return }
        guard item.fps > 0 else { return }
        if drawLayer == nil { draw() }
        stopAnimation(clear: false)
        loopCount = 0
        currentRange = 0..<item.frames
        forwardAnimating = !reversing
        attachDisplayLink(fps: item.fps)
    }

    public func startAnimation(range: Range<Int>, reverse: Bool) {
        guard let item = videoItem else { return }
        guard item.fps > 0 else { return }
        if drawLayer == nil { draw() }
        stopAnimation(clear: false)
        loopCount = 0
        currentRange = range
        reversing = reverse
        currentFrame = reverse
            ? min(item.frames - 1, range.upperBound - 1)
            : max(0, range.lowerBound)
        forwardAnimating = !reversing
        attachDisplayLink(fps: item.fps)
    }

    public func pauseAnimation() {
        stopAnimation(clear: false)
    }

    public func stopAnimation() {
        stopAnimation(clear: clearsAfterStop)
    }

    public func step(toFrame frame: Int, andPlay: Bool) {
        guard let item = videoItem else { return }
        guard frame >= 0, frame < item.frames else { return }
        if drawLayer == nil { draw() }
        pauseAnimation()
        currentFrame = frame
        update()
        if andPlay {
            guard item.fps > 0 else { return }
            forwardAnimating = true
            attachDisplayLink(fps: item.fps)
        }
    }

    public func step(toPercentage percentage: CGFloat, andPlay: Bool) {
        guard let item = videoItem else { return }
        var frame = Int(CGFloat(item.frames) * percentage)
        if frame >= item.frames, frame > 0 { frame = item.frames - 1 }
        step(toFrame: frame, andPlay: andPlay)
    }

    public func clear() {
        contentLayers = []
        drawLayer?.removeFromSuperlayer()
        drawLayer = nil
    }
    // MARK: - Private playback helpers

    private func attachDisplayLink(fps: Int) {
        let link = CADisplayLink(target: self, selector: #selector(nextFrame))
        link.preferredFramesPerSecond = fps
        link.add(to: .main, forMode: mainRunLoopMode)
        displayLink = link
    }

    private func stopAnimation(clear: Bool) {
        forwardAnimating = false
        displayLink?.invalidate()
        displayLink = nil
        if clear { self.clear() }
        clearAudios()
    }

    private func clearAudios() {
        for layer in audioLayers where layer.audioPlaying {
            layer.audioPlayer?.stop()
            layer.audioPlaying = false
        }
    }

    @objc private func nextFrame() {
        guard let item = videoItem else { return }
        if reversing {
            currentFrame -= 1
            if currentFrame < max(0, currentRange.lowerBound) {
                currentFrame = min(item.frames - 1, currentRange.upperBound - 1)
                loopCount += 1
            }
        } else {
            currentFrame += 1
            if currentFrame >= min(item.frames, currentRange.upperBound) {
                currentFrame = max(0, currentRange.lowerBound)
                clearAudios()
                loopCount += 1
            }
        }
        if loops > 0, loopCount >= loops {
            stopAnimation(clear: clearsAfterStop)
            if !clearsAfterStop {
                switch fillMode {
                case .backward:
                    step(toFrame: max(0, currentRange.lowerBound), andPlay: false)
                case .forward:
                    step(toFrame: min(item.frames - 1, currentRange.upperBound - 1), andPlay: false)
                case .clear:
                    clear()
                }
            }
            delegate?.svgaPlayerDidFinishAnimation(self)
            return
        }
        update()
        delegate?.svgaPlayer(self, didAnimateToFrame: currentFrame)
        if item.frames > 0 {
            delegate?.svgaPlayer(self, didAnimateToPercentage: CGFloat(currentFrame + 1) / CGFloat(item.frames))
        }
    }
    private func draw() {
        guard let item = videoItem else { return }
        print("[SVGADraw] draw() start: videoSize=\(item.videoSize) fps=\(item.fps) frames=\(item.frames) sprites=\(item.sprites.count)")
        print("[SVGADraw] self.bounds=\(bounds) self.frame=\(frame)")
        let dl = CALayer()
        dl.frame = CGRect(origin: .zero, size: item.videoSize)
        dl.masksToBounds = true
        var tempContentLayers: [SVGAContentLayer] = []
        var hostLayers: [String: CALayer] = [:]
        for (idx, sprite) in item.sprites.enumerated() {
            let bitmapKey = (sprite.imageKey as NSString).deletingPathExtension
            let bitmap = dynamicImages[bitmapKey] ?? item.images[bitmapKey]
            let contentLayer = sprite.requestLayer(bitmap: bitmap)
            tempContentLayers.append(contentLayer)
            if sprite.imageKey.hasSuffix(".matte") {
                let hostLayer = CALayer()
                hostLayer.mask = contentLayer
                hostLayers[sprite.imageKey] = hostLayer
            } else if let matteKey = sprite.matteKey, !matteKey.isEmpty {
                let hostLayer = hostLayers[matteKey]
                hostLayer?.addSublayer(contentLayer)
                let prevMatteKey = idx > 0 ? item.sprites[idx - 1].matteKey : nil
                if matteKey != prevMatteKey, let hl = hostLayer {
                    dl.addSublayer(hl)
                }
            } else {
                dl.addSublayer(contentLayer)
            }
            if let text = dynamicTexts[sprite.imageKey] {
                contentLayer.resetTextLayer(text)
            }
            if dynamicHiddens[sprite.imageKey] == true {
                contentLayer.dynamicHidden = true
            }
            if let block = dynamicDrawings[sprite.imageKey] {
                contentLayer.dynamicDrawingBlock = block
            }
        }
        contentLayers = tempContentLayers
        layer.addSublayer(dl)
        drawLayer = dl
        print("[SVGADraw] draw() done: contentLayers=\(contentLayers.count) dl.frame=\(dl.frame) item.images.keys=\(item.images.keys.sorted())")
        for (i, cl) in contentLayers.enumerated() {
            print("[SVGADraw]   contentLayer[\(i)] imageKey=\(cl.imageKey) frame=\(cl.frame) hidden=\(cl.isHidden) opacity=\(cl.opacity) bitmapLayer=\(cl.bitmapLayer != nil) vectorLayer=\(cl.vectorLayer != nil)")
        }
        let layers = item.audios.map { SVGAAudioLayer(audioItem: $0, videoItem: item) }
        audioLayers = layers
        update()
        resize()
    }

    private func update() {
        CATransaction.setDisableActions(true)
        for layer in contentLayers {
            layer.stepToFrame(currentFrame)
        }
        CATransaction.setDisableActions(false)
        if forwardAnimating {
            for layer in audioLayers {
                if !layer.audioPlaying,
                   layer.audioItem.startFrame <= currentFrame,
                   currentFrame <= layer.audioItem.endFrame {
                    layer.audioPlayer?.currentTime = TimeInterval(layer.audioItem.startTime) / 1000
                    layer.audioPlayer?.play()
                    layer.audioPlaying = true
                }
                if layer.audioPlaying, layer.audioItem.endFrame <= currentFrame {
                    layer.audioPlayer?.stop()
                    layer.audioPlaying = false
                }
            }
        }
    }

    private func resize() {
        guard let item = videoItem, let dl = drawLayer else {
            print("[SVGAResize] resize() skipped: videoItem=\(videoItem != nil) drawLayer=\(drawLayer != nil)")
            return
        }
        let vs = item.videoSize
        let bs = bounds.size
        print("[SVGAResize] resize() videoSize=\(vs) bounds=\(bs) contentMode=\(contentMode.rawValue)")
        guard vs.width > 0, vs.height > 0, bs.width > 0, bs.height > 0 else {
            print("[SVGAResize] resize() guard failed")
            return
        }
        let videoRatio = vs.width / vs.height
        let layerRatio = bs.width / bs.height
        // CALayer applies transforms around anchorPoint (default 0.5,0.5 = layer center).
        // For uniform scale r with desired top-left at (dx, dy) in superlayer coords:
        //   tx = (r-1)*vs.width/2 + dx
        //   ty = (r-1)*vs.height/2 + dy
        let t: CGAffineTransform
        switch contentMode {
        case .scaleAspectFit:
            let r: CGFloat
            let dx: CGFloat
            let dy: CGFloat
            if videoRatio > layerRatio {
                r = bs.width / vs.width
                dx = 0
                dy = (bs.height - vs.height * r) / 2
            } else {
                r = bs.height / vs.height
                dx = (bs.width - vs.width * r) / 2
                dy = 0
            }
            t = CGAffineTransform(a: r, b: 0, c: 0, d: r,
                                  tx: (r - 1) * vs.width / 2 + dx,
                                  ty: (r - 1) * vs.height / 2 + dy)
        case .scaleAspectFill:
            let r: CGFloat
            let dx: CGFloat
            let dy: CGFloat
            if videoRatio < layerRatio {
                r = bs.width / vs.width
                dx = 0
                dy = (bs.height - vs.height * r) / 2
            } else {
                r = bs.height / vs.height
                dx = (bs.width - vs.width * r) / 2
                dy = 0
            }
            t = CGAffineTransform(a: r, b: 0, c: 0, d: r,
                                  tx: (r - 1) * vs.width / 2 + dx,
                                  ty: (r - 1) * vs.height / 2 + dy)
        default:
            // Matches ObjC .top: uniform scale to fit width, top-aligned
            let r = bs.width / vs.width
            t = CGAffineTransform(a: r, b: 0, c: 0, d: r,
                                  tx: (r - 1) * vs.width / 2,
                                  ty: (r - 1) * vs.height / 2)
        }
        dl.transform = CATransform3DMakeAffineTransform(t)
        print("[SVGAResize] applied transform=\(t) to drawLayer")
    }

    // MARK: - Dynamic objects

    public func setImage(_ image: UIImage, forKey key: String) {
        dynamicImages[key] = image
        for layer in contentLayers where layer.imageKey == key {
            layer.bitmapLayer?.contents = image.cgImage
        }
    }

    public func setAttributedText(_ text: NSAttributedString, forKey key: String) {
        dynamicTexts[key] = text
        for layer in contentLayers where layer.imageKey == key {
            layer.resetTextLayer(text)
        }
    }

    public func setDrawingBlock(_ block: SVGAPlayerDynamicDrawingBlock?, forKey key: String) {
        dynamicDrawings[key] = block
        for layer in contentLayers where layer.imageKey == key {
            layer.dynamicDrawingBlock = block
        }
    }

    public func setHidden(_ hidden: Bool, forKey key: String) {
        dynamicHiddens[key] = hidden
        for layer in contentLayers where layer.imageKey == key {
            layer.dynamicHidden = hidden
        }
    }

    public func clearDynamicObjects() {
        dynamicImages = [:]
        dynamicTexts = [:]
        dynamicDrawings = [:]
        dynamicHiddens = [:]
    }
}



