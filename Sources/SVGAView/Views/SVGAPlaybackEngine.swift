import UIKit
import AVFoundation

// MARK: - Public types

/// 在 sprite layer 完成当前帧布局后执行的自定义绘制回调。
///
/// 回调参数依次为 sprite 所在的 layer 和当前帧索引。
typealias SVGADynamicDrawingBlock = @MainActor @Sendable (CALayer, Int) -> Void

/// 动画结束后的填充模式。
public enum SVGAFillMode: Sendable {
    /// 停留在播放范围的最后一帧。
    case forward
    /// 停留在播放范围的第一帧。
    case backward
    /// 清除画面。
    case clear
}

/// 接收动画引擎播放事件的代理。
///
/// 该协议仅供内部桥接使用。公开事件通过 `SVGAView` 的回调暴露。
@MainActor
protocol SVGAPlaybackEngineDelegate: AnyObject {
    func svgaPlaybackEngineDidFinishAnimation(_ player: SVGAPlaybackEngine)
    func svgaPlaybackEngine(_ player: SVGAPlaybackEngine, didAnimateToFrame frame: Int)
    func svgaPlaybackEngine(_ player: SVGAPlaybackEngine, didAnimateToPercentage percentage: CGFloat)
}

extension SVGAPlaybackEngineDelegate {
    func svgaPlaybackEngineDidFinishAnimation(_ player: SVGAPlaybackEngine) {}
    func svgaPlaybackEngine(_ player: SVGAPlaybackEngine, didAnimateToFrame frame: Int) {}
    func svgaPlaybackEngine(_ player: SVGAPlaybackEngine, didAnimateToPercentage percentage: CGFloat) {}
}

// MARK: - SVGAPlaybackEngine (Animation Engine)

/// 驱动 SVGA 动画播放的内部引擎。
///
/// `SVGAPlaybackEngine` 管理帧推进、layer 树构建、音频同步和动态内容替换。
/// 它不直接依赖 `UIView`，由 `SVGAView` 负责承载最终的
/// `drawLayer`。
@MainActor
final class SVGAPlaybackEngine {

    // MARK: - Public properties

    /// 当前动画数据。
    ///
    /// 设置该属性会重置播放范围、当前帧和循环计数，并重新构建渲染 layer。
    var videoItem: SVGA.VideoEntity? {
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

    /// 动画重复播放的次数。
    ///
    /// 值为 `0` 时无限循环。
    var loops: Int = 0

    /// 一个布尔值，指示停止播放后是否清除画面。
    var clearsAfterStop: Bool = true

    /// 动画结束后保留的画面。
    var fillMode: SVGAFillMode = .forward

    /// 驱动动画的 display link 所使用的 run loop 模式。
    var mainRunLoopMode: RunLoop.Mode = .common

    /// 接收播放事件的代理。
    weak var delegate: SVGAPlaybackEngineDelegate?

    /// 当前渲染图层。
    ///
    /// 该 layer 由引擎创建和管理，宿主视图只负责把它挂载到自身 layer 上。
    private(set) var drawLayer: CALayer?

    /// 渲染图层变化时调用的回调。
    ///
    /// `SVGAView` 通过该回调挂载或移除 `drawLayer`。
    var onDrawLayerChanged: ((CALayer?) -> Void)?

    // MARK: - Private state

    private var audioLayers: [SVGAAudioLayer] = []
    private var displayLink: CADisplayLink?
    private var displayLinkProxy: DisplayLinkProxy?
    private var currentFrame: Int = 0
    private var contentLayers: [SVGAContentLayer] = []
    private var dynamicImages: [String: UIImage] = [:]
    private var dynamicTexts: [String: NSAttributedString] = [:]
    private var dynamicDrawings: [String: SVGADynamicDrawingBlock] = [:]
    private var dynamicHiddens: [String: Bool] = [:]
    private var loopCount: Int = 0
    private var currentRange: Range<Int> = 0..<0
    private var forwardAnimating: Bool = false
    private var reversing: Bool = false
    private var notificationObservers: [any NSObjectProtocol] = []

    // MARK: - Init / Lifecycle

    init() {
        let nc = NotificationCenter.default
        notificationObservers.append(
            nc.addObserver(forName: UIApplication.didEnterBackgroundNotification,
                           object: nil, queue: nil) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    guard self.displayLink != nil else { return }
                    self.displayLink?.isPaused = true
                    self.clearAudios()
                }
            }
        )
        notificationObservers.append(
            nc.addObserver(forName: UIApplication.willEnterForegroundNotification,
                           object: nil, queue: nil) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.displayLink?.isPaused = false
                }
            }
        )
    }

    isolated deinit {
        let nc = NotificationCenter.default
        for observer in notificationObservers {
            nc.removeObserver(observer)
        }
    }

    // MARK: - Playback control

    /// 从第一帧开始播放全部帧。
    ///
    /// - Returns: 动画开始播放时返回 `true`；没有可播放数据或帧率无效时返回 `false`。
    @discardableResult
    func startAnimation() -> Bool {
        guard let item = videoItem else { return false }
        guard item.fps > 0 else { return false }
        if drawLayer == nil { draw() }
        stopAnimation(clear: false)
        loopCount = 0
        currentRange = 0..<item.frames
        forwardAnimating = !reversing
        attachDisplayLink(fps: item.fps)
        return true
    }

    /// 播放指定帧范围。
    ///
    /// - Parameters:
    ///   - range: 要播放的帧范围。范围会被限制在动画的有效帧范围内。
    ///   - reverse: `true` 表示倒放该范围。
    /// - Returns: 动画开始播放时返回 `true`；没有可播放数据、帧率无效或范围为空时返回 `false`。
    @discardableResult
    func startAnimation(range: Range<Int>, reverse: Bool) -> Bool {
        guard let item = videoItem else { return false }
        guard item.fps > 0 else { return false }
        let clampedRange = max(0, range.lowerBound)..<min(item.frames, range.upperBound)
        guard !clampedRange.isEmpty else { return false }
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
        return true
    }

    /// 暂停动画并保留当前画面。
    ///
    /// - Returns: 暂停成功时返回 `true`；尚未加载动画时返回 `false`。
    @discardableResult
    func pauseAnimation() -> Bool {
        guard videoItem != nil else { return false }
        stopAnimation(clear: false)
        return true
    }

    /// 停止动画。
    ///
    /// 是否清除画面取决于 `clearsAfterStop`。
    func stopAnimation() {
        stopAnimation(clear: clearsAfterStop)
    }

    /// 跳转到指定帧，并可选择跳转后是否继续播放。
    ///
    /// - Parameters:
    ///   - frame: 目标帧索引。
    ///   - andPlay: `true` 表示跳转后继续播放。
    /// - Returns: 跳转成功时返回 `true`；尚未加载动画或帧索引无效时返回 `false`。
    @discardableResult
    func step(toFrame frame: Int, andPlay: Bool) -> Bool {
        guard let item = videoItem else { return false }
        guard frame >= 0, frame < item.frames else { return false }
        if drawLayer == nil { draw() }
        pauseAnimation()
        currentFrame = frame
        update()
        if andPlay {
            guard item.fps > 0 else { return true }
            forwardAnimating = true
            attachDisplayLink(fps: item.fps)
        }
        return true
    }

    /// 跳转到指定播放进度。
    ///
    /// - Parameters:
    ///   - percentage: 目标进度。取值会被限制在 `0.0...1.0` 范围内。
    ///   - andPlay: `true` 表示跳转后继续播放。
    /// - Returns: 跳转成功时返回 `true`；尚未加载动画时返回 `false`。
    @discardableResult
    func step(toPercentage percentage: CGFloat, andPlay: Bool) -> Bool {
        guard let item = videoItem else { return false }
        let clamped = min(max(percentage, 0), 1)
        var frame = Int(CGFloat(item.frames) * clamped)
        if frame >= item.frames { frame = item.frames - 1 }
        return step(toFrame: frame, andPlay: andPlay)
    }

    /// 清除所有渲染 layer 和当前画面。
    func clear() {
        contentLayers = []
        drawLayer?.removeFromSuperlayer()
        drawLayer = nil
        onDrawLayerChanged?(nil)
    }

    // MARK: - Layout

    /// 根据容器尺寸和内容模式调整渲染 layer。
    ///
    /// - Parameters:
    ///   - bounds: 宿主视图的内容尺寸。
    ///   - contentMode: 宿主视图的内容缩放模式。
    func resize(bounds: CGSize, contentMode: UIView.ContentMode) {
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

    /// 替换指定 sprite 的位图。
    ///
    /// - Parameters:
    ///   - image: 要显示的图片。
    ///   - key: SVGA 文件中的 sprite `imageKey`。
    func setImage(_ image: UIImage, forKey key: String) {
        let key = normalizedDynamicKey(key)
        dynamicImages[key] = image
        for layer in contentLayers(matching: key) {
            layer.setBitmapImage(image)
        }
    }

    /// 移除指定 sprite 的动态位图，并恢复原始图片。
    ///
    /// - Parameter key: SVGA 文件中的 sprite `imageKey`。
    func removeImage(forKey key: String) {
        let key = normalizedDynamicKey(key)
        dynamicImages.removeValue(forKey: key)
        for layer in contentLayers(matching: key) {
            let originalKey = normalizedDynamicKey(layer.imageKey)
            layer.setBitmapImage(videoItem?.images[originalKey])
        }
    }

    /// 在指定 sprite 上叠加富文本。
    ///
    /// - Parameters:
    ///   - text: 要叠加显示的富文本。
    ///   - key: SVGA 文件中的 sprite `imageKey`。
    func setAttributedText(_ text: NSAttributedString, forKey key: String) {
        dynamicTexts[key] = text
        for layer in contentLayers(matching: key) {
            layer.resetTextLayer(text)
        }
    }

    /// 移除指定 sprite 上的动态富文本。
    ///
    /// - Parameter key: SVGA 文件中的 sprite `imageKey`。
    func removeAttributedText(forKey key: String) {
        dynamicTexts.removeValue(forKey: key)
        dynamicTexts.removeValue(forKey: normalizedDynamicKey(key))
        for layer in contentLayers(matching: key) {
            layer.removeTextLayer()
        }
    }

    /// 设置指定 sprite 的自定义绘制回调。
    ///
    /// - Parameters:
    ///   - block: 自定义绘制回调。传入 `nil` 时移除回调。
    ///   - key: SVGA 文件中的 sprite `imageKey`。
    func setDrawingBlock(_ block: SVGADynamicDrawingBlock?, forKey key: String) {
        let key = normalizedDynamicKey(key)
        dynamicDrawings[key] = block
        for layer in contentLayers(matching: key) {
            layer.dynamicDrawingBlock = block
        }
    }

    /// 移除指定 sprite 的自定义绘制回调。
    ///
    /// - Parameter key: SVGA 文件中的 sprite `imageKey`。
    func removeDrawingBlock(forKey key: String) {
        let key = normalizedDynamicKey(key)
        dynamicDrawings.removeValue(forKey: key)
        for layer in contentLayers(matching: key) {
            layer.dynamicDrawingBlock = nil
        }
    }

    /// 设置指定 sprite 的隐藏状态。
    ///
    /// - Parameters:
    ///   - hidden: `true` 表示隐藏该 sprite，`false` 表示显示。
    ///   - key: SVGA 文件中的 sprite `imageKey`。
    func setHidden(_ hidden: Bool, forKey key: String) {
        let key = normalizedDynamicKey(key)
        dynamicHiddens[key] = hidden
        for layer in contentLayers(matching: key) {
            layer.dynamicHidden = hidden
        }
    }

    /// 移除指定 sprite 的动态隐藏状态。
    ///
    /// - Parameter key: SVGA 文件中的 sprite `imageKey`。
    func removeHidden(forKey key: String) {
        let key = normalizedDynamicKey(key)
        dynamicHiddens.removeValue(forKey: key)
        for layer in contentLayers(matching: key) {
            layer.dynamicHidden = false
        }
    }

    /// 清除所有动态内容。
    ///
    /// 包括图片、富文本、绘制回调和隐藏状态。
    func clearDynamicObjects() {
        dynamicImages = [:]
        dynamicTexts = [:]
        dynamicDrawings = [:]
        dynamicHiddens = [:]
        for layer in contentLayers {
            let originalKey = normalizedDynamicKey(layer.imageKey)
            layer.setBitmapImage(videoItem?.images[originalKey])
            layer.removeTextLayer()
            layer.dynamicDrawingBlock = nil
            layer.dynamicHidden = false
        }
    }

    // MARK: - Private layer building

    /// 构建完整的渲染 layer 层级。
    ///
    /// 返回值包括根 layer 和每个 sprite 对应的内容 layer。构建时会应用
    /// matte 遮罩和已设置的动态内容。
    private func buildDrawLayer() -> (CALayer, [SVGAContentLayer])? {
        guard let item = videoItem else { return nil }
        let dl = CALayer()
        dl.frame = CGRect(origin: .zero, size: item.videoSize)
        dl.masksToBounds = true
        var layers: [SVGAContentLayer] = []
        var hostLayers: [String: CALayer] = [:]
        for (idx, sprite) in item.sprites.enumerated() {
            let bitmapKey = normalizedDynamicKey(sprite.imageKey)
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
            if let text = dynamicValue(in: dynamicTexts, for: sprite.imageKey) {
                contentLayer.resetTextLayer(text)
            }
            if let hidden = dynamicValue(in: dynamicHiddens, for: sprite.imageKey) {
                contentLayer.dynamicHidden = hidden
            }
            if let block = dynamicValue(in: dynamicDrawings, for: sprite.imageKey) {
                contentLayer.dynamicDrawingBlock = block
            }
        }
        return (dl, layers)
    }

    private func normalizedDynamicKey(_ key: String) -> String {
        (key as NSString).deletingPathExtension
    }

    private func contentLayers(matching key: String) -> [SVGAContentLayer] {
        let normalizedKey = normalizedDynamicKey(key)
        return contentLayers.filter { layer in
            layer.imageKey == key || normalizedDynamicKey(layer.imageKey) == normalizedKey
        }
    }

    private func dynamicValue<T>(in values: [String: T], for spriteKey: String) -> T? {
        values[spriteKey] ?? values[normalizedDynamicKey(spriteKey)]
    }

    // MARK: - Private playback helpers

    /// 构建渲染 layer，并通知宿主视图挂载。
    private func draw() {
        guard let result = buildDrawLayer() else { return }
        let (dl, layers) = result
        contentLayers = layers
        drawLayer = dl
        audioLayers = videoItem?.audios.map { SVGAAudioLayer(audioItem: $0, videoItem: videoItem!) } ?? []
        onDrawLayerChanged?(dl)
        update()
    }

    /// 创建用于驱动帧推进的 display link。
    ///
    /// - Parameter fps: 动画帧率。实际值会被限制在 `1...120` 范围内。
    private func attachDisplayLink(fps: Int) {
        let clampedFPS = min(max(fps, 1), 120)
        let proxy = DisplayLinkProxy { [weak self] in self?.nextFrame() }
        let link = CADisplayLink(target: proxy, selector: #selector(DisplayLinkProxy.tick))
        link.preferredFramesPerSecond = clampedFPS
        link.add(to: .main, forMode: mainRunLoopMode)
        displayLink = link
        displayLinkProxy = proxy
    }

    /// 停止 display link，并按需清除画面。
    ///
    /// - Parameter clear: `true` 表示停止后清除渲染 layer。
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

    /// 推进到下一帧并发送播放事件。
    ///
    /// 该方法处理正放、倒放、循环计数和结束填充模式。
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
            delegate?.svgaPlaybackEngineDidFinishAnimation(self)
            return
        }
        update()
        let frame = currentFrame
        delegate?.svgaPlaybackEngine(self, didAnimateToFrame: frame)
        // delegate 回调可能已调用 stopAnimation/startAnimation 改变状态，
        // 需检查 displayLink 是否仍有效（即动画未被中断）。
        guard displayLink != nil, item.frames > 0 else { return }
        delegate?.svgaPlaybackEngine(self, didAnimateToPercentage: CGFloat(frame + 1) / CGFloat(item.frames))
    }

    /// 更新所有内容 layer 到当前帧，并同步音频播放。
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

/// `CADisplayLink` 使用的弱引用代理。
///
/// `CADisplayLink` 会强引用 target。该代理通过闭包转发 tick，避免动画引擎
/// 与 display link 之间形成强引用环。
@MainActor
private final class DisplayLinkProxy: NSObject {
    private let callback: () -> Void

    init(callback: @escaping () -> Void) {
        self.callback = callback
    }

    /// `CADisplayLink` 的回调入口。
    @objc func tick() {
        callback()
    }
}
