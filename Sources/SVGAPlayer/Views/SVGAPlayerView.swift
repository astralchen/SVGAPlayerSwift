import UIKit

// MARK: - Dynamic content configuration

/// SVGA 动画的动态内容配置，用于在播放前替换动画中的图片、文本等元素。
///
/// key 对应 SVGA 文件中 sprite 的 imageKey。
///
/// ```swift
/// var content = SVGADynamicContent()
/// content.setImage(avatarImage, forKey: "avatar")
/// content.setAttributedText(nickname, forKey: "username")
/// content.setHidden(true, forKey: "badge")
/// playerView.play(named: "gift", dynamicContent: content)
/// ```
public struct SVGADynamicContent {

    public struct Item {
        var image: UIImage?
        var text: NSAttributedString?
        var drawingBlock: SVGAPlayerDynamicDrawingBlock?
        var hidden: Bool?

        public init(image: UIImage? = nil,
                    text: NSAttributedString? = nil,
                    drawingBlock: SVGAPlayerDynamicDrawingBlock? = nil,
                    hidden: Bool? = nil) {
            self.image = image
            self.text = text
            self.drawingBlock = drawingBlock
            self.hidden = hidden
        }
    }

    var items: [String: Item] = [:]

    public init() {}

    /// 替换指定 key 的 sprite 图片。
    public mutating func setImage(_ image: UIImage, forKey key: String) {
        items[key, default: Item()].image = image
    }

    /// 在指定 key 的 sprite 上叠加富文本。
    public mutating func setAttributedText(_ text: NSAttributedString, forKey key: String) {
        items[key, default: Item()].text = text
    }

    /// 为指定 key 的 sprite 设置自定义绘制回调，每帧调用一次。
    public mutating func setDrawingBlock(_ block: SVGAPlayerDynamicDrawingBlock?, forKey key: String) {
        items[key, default: Item()].drawingBlock = block
    }

    /// 隐藏或显示指定 key 的 sprite。
    public mutating func setHidden(_ hidden: Bool, forKey key: String) {
        items[key, default: Item()].hidden = hidden
    }
}

// MARK: - SVGAPlayerView

/// 播放 SVGA 动画的视图。
///
/// `SVGAPlayerView` 封装了动画引擎，提供加载、播放、暂停、动态内容替换等功能。
/// 支持从 Bundle 资源名或网络 URL 加载 `.svga` 文件。
///
/// **基本用法：**
/// ```swift
/// let playerView = SVGAPlayerView(frame: CGRect(x: 0, y: 0, width: 300, height: 300))
/// playerView.contentMode = .scaleAspectFit
/// view.addSubview(playerView)
/// playerView.play(named: "animation")
/// ```
///
/// **监听事件：**
/// ```swift
/// playerView.onFinished = {
///     print("animation finished")
/// }
/// playerView.onLoadFailed = { error in
///     print("load failed: \(error)")
/// }
/// ```
///
/// **带动态内容播放：**
/// ```swift
/// var content = SVGADynamicContent()
/// content.setImage(avatar, forKey: "avatar")
/// playerView.play(named: "gift", dynamicContent: content)
/// ```
///
/// **从网络加载：**
/// ```swift
/// playerView.play(url: URL(string: "https://example.com/anim.svga")!)
/// ```
///
/// **Interface Builder：**
/// 设置 `filePath` 属性为资源名或 URL 字符串，勾选 `autoPlay` 即可自动播放。
@MainActor
public class SVGAPlayerView: UIView {

    // MARK: - Private engine

    private let engine = SVGAPlayer()
    private var loadTask: Task<Void, Never>?

    // MARK: - Public properties

    /// 循环次数。0 表示无限循环，默认 0。
    public var loops: Int {
        get { engine.loops }
        set { engine.loops = newValue }
    }

    /// 停止动画后是否清除画面，默认 true。
    public var clearsAfterStop: Bool {
        get { engine.clearsAfterStop }
        set { engine.clearsAfterStop = newValue }
    }

    /// 动画结束后的填充模式（仅 `clearsAfterStop = false` 时生效）。
    public var fillMode: SVGAFillMode {
        get { engine.fillMode }
        set { engine.fillMode = newValue }
    }

    /// DisplayLink 注册的 RunLoop 模式，默认 `.common`。
    public var mainRunLoopMode: RunLoop.Mode {
        get { engine.mainRunLoopMode }
        set { engine.mainRunLoopMode = newValue }
    }

    /// 设为 true 时，加载完成后自动开始播放，默认 true。
    @IBInspectable public var autoPlay: Bool = true

    // MARK: - Callbacks

    /// 动画播放完成时回调（达到 `loops` 次数后触发，无限循环不触发）。
    public var onFinished: (() -> Void)?

    /// 每一帧切换时回调，参数为当前帧索引。
    public var onFrameChanged: ((Int) -> Void)?

    /// 每一帧切换时回调，参数为播放进度百分比 (0.0 ~ 1.0)。
    public var onPercentageChanged: ((CGFloat) -> Void)?

    /// 加载失败时回调，参数为错误信息。
    public var onLoadFailed: ((Error) -> Void)?

    // MARK: - Convenience loading (Interface Builder)

    /// 资源路径，支持 Bundle 资源名或 HTTP(S) URL 字符串。
    ///
    /// 设置后自动加载并播放（需 `autoPlay = true`）。适用于 Interface Builder。
    @IBInspectable public var filePath: String? {
        didSet {
            guard let path = filePath else { return }
            if let url = URL(string: path),
               let scheme = url.scheme?.lowercased(),
               scheme == "http" || scheme == "https" {
                play(url: url)
            } else {
                play(named: path)
            }
        }
    }

    // MARK: - Init

    public override init(frame: CGRect) {
        super.init(frame: frame)
        contentMode = .top
        setupEngine()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        contentMode = .top
        setupEngine()
    }

    private func setupEngine() {
        engine.onDrawLayerChanged = { [weak self] newLayer in
            guard let self else { return }
            if let l = newLayer {
                self.layer.addSublayer(l)
                self.engine.resize(bounds: self.bounds.size, contentMode: self.contentMode)
            }
        }
        engine.delegate = self
    }

    // MARK: - UIView lifecycle

    public override func willMove(toSuperview newSuperview: UIView?) {
        super.willMove(toSuperview: newSuperview)
        if newSuperview == nil {
            loadTask?.cancel()
            loadTask = nil
            engine.stopAnimation()
        }
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        engine.resize(bounds: bounds.size, contentMode: contentMode)
    }

    // MARK: - Play

    /// 从 Bundle 加载 SVGA 资源并播放。
    ///
    /// ```swift
    /// // 加载 main bundle 中的 banner.svga
    /// playerView.play(named: "banner")
    ///
    /// // 加载指定 bundle 中的资源
    /// playerView.play(named: "effect", in: frameworkBundle)
    ///
    /// // 带动态内容
    /// var content = SVGADynamicContent()
    /// content.setImage(avatar, forKey: "avatar")
    /// playerView.play(named: "gift", dynamicContent: content)
    /// ```
    ///
    /// - Parameters:
    ///   - name: 资源名（不含 `.svga` 扩展名）。
    ///   - bundle: 资源所在的 Bundle，传 nil 使用 `Bundle.main`。
    ///   - dynamicContent: 可选的动态内容配置。
    public func play(named name: String, in bundle: Bundle? = nil, dynamicContent: SVGADynamicContent? = nil) {
        load(dynamicContent: dynamicContent) { try await SVGAParser.shared.parse(named: name, in: bundle) }
    }

    /// 从网络 URL 加载 SVGA 文件并播放。
    ///
    /// ```swift
    /// let url = URL(string: "https://cdn.example.com/animation.svga")!
    /// playerView.play(url: url)
    /// ```
    ///
    /// - Parameters:
    ///   - url: SVGA 文件的 HTTP(S) URL。
    ///   - dynamicContent: 可选的动态内容配置。
    public func play(url: URL, dynamicContent: SVGADynamicContent? = nil) {
        load(dynamicContent: dynamicContent) { try await SVGAParser.shared.parse(url: url) }
    }

    private func load(dynamicContent: SVGADynamicContent?, _ fetch: @escaping () async throws -> SVGAVideoEntity) {
        loadTask?.cancel()
        loadTask = Task {
            do {
                let entity = try await fetch()
                guard !Task.isCancelled else { return }
                engine.clearDynamicObjects()
                if let content = dynamicContent {
                    applyDynamicContent(content)
                }
                guard !Task.isCancelled else { return }
                engine.videoItem = entity
                if autoPlay { engine.startAnimation() }
            } catch {
                if !Task.isCancelled { onLoadFailed?(error) }
            }
        }
    }

    private func applyDynamicContent(_ content: SVGADynamicContent) {
        for (key, item) in content.items {
            if let image = item.image {
                engine.setImage(image, forKey: key)
            }
            if let text = item.text {
                engine.setAttributedText(text, forKey: key)
            }
            if let block = item.drawingBlock {
                engine.setDrawingBlock(block, forKey: key)
            }
            if let hidden = item.hidden {
                engine.setHidden(hidden, forKey: key)
            }
        }
    }

    // MARK: - Playback control

    /// 开始播放全部帧。需要先通过 `play(named:)` 或 `play(url:)` 加载数据。
    public func startAnimation() {
        engine.startAnimation()
    }

    /// 播放指定帧范围。
    ///
    /// ```swift
    /// // 播放第 10 ~ 30 帧，正向
    /// playerView.startAnimation(range: 10..<30, reverse: false)
    ///
    /// // 倒放第 0 ~ 20 帧
    /// playerView.startAnimation(range: 0..<20, reverse: true)
    /// ```
    ///
    /// - Parameters:
    ///   - range: 帧范围，自动 clamp 到有效区间。
    ///   - reverse: 是否倒放。
    public func startAnimation(range: Range<Int>, reverse: Bool) {
        engine.startAnimation(range: range, reverse: reverse)
    }

    /// 暂停动画，保留当前画面。
    public func pauseAnimation() {
        engine.pauseAnimation()
    }

    /// 停止动画。是否清除画面取决于 `clearsAfterStop` 属性。
    public func stopAnimation() {
        engine.stopAnimation()
    }

    /// 跳转到指定帧。
    ///
    /// ```swift
    /// // 跳转到第 5 帧并暂停
    /// playerView.step(toFrame: 5, andPlay: false)
    ///
    /// // 跳转到第 10 帧并继续播放
    /// playerView.step(toFrame: 10, andPlay: true)
    /// ```
    public func step(toFrame frame: Int, andPlay: Bool) {
        engine.step(toFrame: frame, andPlay: andPlay)
    }

    /// 跳转到指定百分比位置。
    ///
    /// ```swift
    /// // 跳转到 50% 位置并暂停
    /// playerView.step(toPercentage: 0.5, andPlay: false)
    /// ```
    ///
    /// - Parameters:
    ///   - percentage: 0.0 ~ 1.0，自动 clamp。
    ///   - andPlay: 是否跳转后继续播放。
    public func step(toPercentage percentage: CGFloat, andPlay: Bool) {
        engine.step(toPercentage: percentage, andPlay: andPlay)
    }

    /// 清除动画画面和所有图层。
    public func clear() {
        engine.clear()
    }
}

// MARK: - SVGAPlayerDelegate (bridge engine events to callbacks)

extension SVGAPlayerView: SVGAPlayerDelegate {
    public func svgaPlayerDidFinishAnimation(_ player: SVGAPlayer) {
        onFinished?()
    }

    public func svgaPlayer(_ player: SVGAPlayer, didAnimateToFrame frame: Int) {
        onFrameChanged?(frame)
    }

    public func svgaPlayer(_ player: SVGAPlayer, didAnimateToPercentage percentage: CGFloat) {
        onPercentageChanged?(percentage)
    }
}
