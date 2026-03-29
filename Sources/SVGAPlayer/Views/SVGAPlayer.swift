import UIKit
import AVFoundation

// MARK: - Public types

/// 自定义绘制回调，每帧调用一次。参数为 sprite 所在的 CALayer 和当前帧索引。
public typealias SVGAPlayerDynamicDrawingBlock = @MainActor @Sendable (CALayer, Int) -> Void

/// 动画结束后的填充模式。
public enum SVGAFillMode: Sendable {
    /// 停留在最后一帧。
    case forward
    /// 停留在第一帧。
    case backward
    /// 清除画面。
    case clear
}

/// 动画引擎事件代理（内部使用，外部通过 SVGAPlayerView 的回调监听）。
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

// MARK: - SVGAPlayer (Animation Engine)

/// SVGA 动画引擎，负责帧推进、图层管理、音频同步和动态内容。
///
/// 通常不直接使用，而是通过 `SVGAPlayerView` 间接驱动。
/// 引擎不依赖 UIView，可独立用于导出（参见 `SVGAExporter`）。
@MainActor
public final class SVGAPlayer {

    // MARK: - Public properties

    /// 动画数据。设置后自动构建图层并准备播放。
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

    /// 循环次数，0 = 无限循环。
    public var loops: Int = 0

    /// 停止后是否清除画面。
    public var clearsAfterStop: Bool = true

    /// 动画结束后的填充模式。
    public var fillMode: SVGAFillMode = .forward

    /// DisplayLink 注册的 RunLoop 模式。
    public var mainRunLoopMode: RunLoop.Mode = .common

    /// 事件代理。
    public weak var delegate: SVGAPlayerDelegate?

    /// 当前渲染图层（只读），由引擎创建和管理。
    public private(set) var drawLayer: CALayer?

    /// 图层变化回调，SVGAPlayerView 通过此回调挂载/移除 drawLayer。
    var onDrawLayerChanged: ((CALayer?) -> Void)?

    // MARK: - Private state

    private var audioLayers: [SVGAAudioLayer] = []
    private var displayLink: CADisplayLink?
    private var displayLinkProxy: DisplayLinkProxy?
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

    // MARK: - Init / Lifecycle

    public init() {
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(appDidEnterBackground),
                       name: UIApplication.didEnterBackgroundNotification, object: nil)
        nc.addObserver(self, selector: #selector(appWillEnterForeground),
                       name: UIApplication.willEnterForegroundNotification, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    /// App 进入后台时暂停 DisplayLink 和音频，节省 CPU/电量。
    @objc private func appDidEnterBackground() {
        MainActor.assumeIsolated {
            guard displayLink != nil else { return }
            displayLink?.isPaused = true
            clearAudios()
        }
    }

    /// App 回到前台时恢复 DisplayLink。
    @objc private func appWillEnterForeground() {
        MainActor.assumeIsolated {
            displayLink?.isPaused = false
        }
    }

    // MARK: - Playback control

    /// 从第一帧开始播放全部帧。
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

    /// 播放指定帧范围，range 自动 clamp 到有效区间。
    public func startAnimation(range: Range<Int>, reverse: Bool) {
        guard let item = videoItem else { return }
        guard item.fps > 0 else { return }
        let clampedRange = max(0, range.lowerBound)..<min(item.frames, range.upperBound)
        guard !clampedRange.isEmpty else { return }
        if drawLayer == nil { draw() }
        stopAnimation(clear: false)
        loopCount = 0
        currentRange = clampedRange
        reversing = reverse
        currentFrame = reverse
            ? clampedRange.upperBound - 1
            : clampedRange.lowerBound
        forwardAnimating = !reversing
        attachDisplayLink(fps: item.fps)
    }

    /// 暂停动画，保留当前画面。
    public func pauseAnimation() {
        stopAnimation(clear: false)
    }

    /// 停止动画，是否清除画面取决于 `clearsAfterStop`。
    public func stopAnimation() {
        stopAnimation(clear: clearsAfterStop)
    }

    /// 跳转到指定帧，可选择跳转后继续播放。
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

    /// 跳转到指定百分比位置 (0.0 ~ 1.0)，自动 clamp。
    public func step(toPercentage percentage: CGFloat, andPlay: Bool) {
        guard let item = videoItem else { return }
        let clamped = min(max(percentage, 0), 1)
        var frame = Int(CGFloat(item.frames) * clamped)
        if frame >= item.frames { frame = item.frames - 1 }
        step(toFrame: frame, andPlay: andPlay)
    }

    /// 清除所有图层和画面。
    public func clear() {
        contentLayers = []
        drawLayer?.removeFromSuperlayer()
        drawLayer = nil
        onDrawLayerChanged?(nil)
    }

    // MARK: - Layout

    /// 根据给定的容器尺寸和 contentMode 计算并应用 drawLayer 的缩放变换。
    public func resize(bounds: CGSize, contentMode: UIView.ContentMode) {
        guard let item = videoItem, let dl = drawLayer else { return }
        let vs = item.videoSize
        guard vs.width > 0, vs.height > 0, bounds.width > 0, bounds.height > 0 else { return }
        let videoRatio = vs.width / vs.height
        let layerRatio = bounds.width / bounds.height
        // CALayer 以 anchorPoint (默认中心) 为基准应用变换。
        // 对于均匀缩放 r，顶部左对齐偏移 (dx, dy):
        //   tx = (r-1)*vs.width/2 + dx
        //   ty = (r-1)*vs.height/2 + dy
        let t: CGAffineTransform
        switch contentMode {
        case .scaleAspectFit:
            let r: CGFloat, dx: CGFloat, dy: CGFloat
            if videoRatio > layerRatio {
                r = bounds.width / vs.width; dx = 0
                dy = (bounds.height - vs.height * r) / 2
            } else {
                r = bounds.height / vs.height; dy = 0
                dx = (bounds.width - vs.width * r) / 2
            }
            t = CGAffineTransform(a: r, b: 0, c: 0, d: r,
                                  tx: (r - 1) * vs.width / 2 + dx,
                                  ty: (r - 1) * vs.height / 2 + dy)
        case .scaleAspectFill:
            let r: CGFloat, dx: CGFloat, dy: CGFloat
            if videoRatio < layerRatio {
                r = bounds.width / vs.width; dx = 0
                dy = (bounds.height - vs.height * r) / 2
            } else {
                r = bounds.height / vs.height; dy = 0
                dx = (bounds.width - vs.width * r) / 2
            }
            t = CGAffineTransform(a: r, b: 0, c: 0, d: r,
                                  tx: (r - 1) * vs.width / 2 + dx,
                                  ty: (r - 1) * vs.height / 2 + dy)
        default:
            // 默认: 按宽度等比缩放，顶部对齐
            let r = bounds.width / vs.width
            t = CGAffineTransform(a: r, b: 0, c: 0, d: r,
                                  tx: (r - 1) * vs.width / 2,
                                  ty: (r - 1) * vs.height / 2)
        }
        dl.transform = CATransform3DMakeAffineTransform(t)
    }

    // MARK: - Dynamic objects

    /// 替换指定 key 的 sprite 位图。
    public func setImage(_ image: UIImage, forKey key: String) {
        dynamicImages[key] = image
        for layer in contentLayers where layer.imageKey == key {
            layer.bitmapLayer?.contents = image.cgImage
        }
    }

    /// 在指定 key 的 sprite 上叠加富文本。
    public func setAttributedText(_ text: NSAttributedString, forKey key: String) {
        dynamicTexts[key] = text
        for layer in contentLayers where layer.imageKey == key {
            layer.resetTextLayer(text)
        }
    }

    /// 为指定 key 的 sprite 设置自定义绘制回调。
    public func setDrawingBlock(_ block: SVGAPlayerDynamicDrawingBlock?, forKey key: String) {
        dynamicDrawings[key] = block
        for layer in contentLayers where layer.imageKey == key {
            layer.dynamicDrawingBlock = block
        }
    }

    /// 隐藏或显示指定 key 的 sprite。
    public func setHidden(_ hidden: Bool, forKey key: String) {
        dynamicHiddens[key] = hidden
        for layer in contentLayers where layer.imageKey == key {
            layer.dynamicHidden = hidden
        }
    }

    /// 清除所有动态内容（图片、文本、绘制回调、隐藏状态）。
    public func clearDynamicObjects() {
        dynamicImages = [:]
        dynamicTexts = [:]
        dynamicDrawings = [:]
        dynamicHiddens = [:]
    }

    // MARK: - Private layer building

    /// 构建完整的 CALayer 层级，包括 matte 遮罩、动态内容等。
    private func buildDrawLayer() -> (CALayer, [SVGAContentLayer])? {
        guard let item = videoItem else { return nil }
        let dl = CALayer()
        dl.frame = CGRect(origin: .zero, size: item.videoSize)
        dl.masksToBounds = true
        var layers: [SVGAContentLayer] = []
        var hostLayers: [String: CALayer] = [:]
        for (idx, sprite) in item.sprites.enumerated() {
            let bitmapKey = (sprite.imageKey as NSString).deletingPathExtension
            let bitmap = dynamicImages[bitmapKey] ?? item.images[bitmapKey]
            let contentLayer = sprite.requestLayer(bitmap: bitmap)
            layers.append(contentLayer)
            // Matte 遮罩处理：imageKey 以 ".matte" 结尾的 sprite 作为遮罩层，
            // 引用该 matteKey 的 sprite 作为被遮罩层添加到宿主图层中。
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
        return (dl, layers)
    }

    // MARK: - Private playback helpers

    /// 构建图层并通知宿主视图挂载。
    private func draw() {
        guard let result = buildDrawLayer() else { return }
        let (dl, layers) = result
        contentLayers = layers
        drawLayer = dl
        audioLayers = videoItem?.audios.map { SVGAAudioLayer(audioItem: $0, videoItem: videoItem!) } ?? []
        onDrawLayerChanged?(dl)
        update()
    }

    /// 创建 DisplayLink 驱动帧推进，通过 DisplayLinkProxy 避免 retain cycle。
    private func attachDisplayLink(fps: Int) {
        let clampedFPS = min(max(fps, 1), 120)
        let proxy = DisplayLinkProxy { [weak self] in self?.nextFrame() }
        let link = CADisplayLink(target: proxy, selector: #selector(DisplayLinkProxy.tick))
        link.preferredFramesPerSecond = clampedFPS
        link.add(to: .main, forMode: mainRunLoopMode)
        displayLink = link
        displayLinkProxy = proxy
    }

    /// 停止 DisplayLink，先置 nil 再 invalidate，防止 tick 竞态。
    private func stopAnimation(clear: Bool) {
        forwardAnimating = false
        let link = displayLink
        displayLink = nil
        displayLinkProxy = nil
        link?.invalidate()
        if clear { self.clear() }
        clearAudios()
    }

    private func clearAudios() {
        for layer in audioLayers where layer.audioPlaying {
            layer.audioPlayer?.stop()
            layer.audioPlaying = false
        }
    }

    /// 每帧调用：推进帧计数器、处理循环逻辑、通知代理。
    private func nextFrame() {
        guard let item = videoItem else { return }
        if reversing {
            currentFrame -= 1
            if currentFrame < max(0, currentRange.lowerBound) {
                currentFrame = min(item.frames - 1, currentRange.upperBound - 1)
                if loops > 0 { loopCount += 1 }
            }
        } else {
            currentFrame += 1
            if currentFrame >= min(item.frames, currentRange.upperBound) {
                currentFrame = max(0, currentRange.lowerBound)
                clearAudios()
                if loops > 0 { loopCount += 1 }
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

    /// 步进所有 contentLayer 到当前帧，同步音频播放。
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
}

// MARK: - DisplayLinkProxy

/// CADisplayLink 的弱引用代理，避免 CADisplayLink 强引用 target 导致 retain cycle。
@MainActor
private final class DisplayLinkProxy: NSObject {
    private let callback: () -> Void

    init(callback: @escaping () -> Void) {
        self.callback = callback
    }

    /// CADisplayLink 回调入口，在主线程 RunLoop 中调用。
    @objc nonisolated func tick() {
        MainActor.assumeIsolated {
            callback()
        }
    }
}
