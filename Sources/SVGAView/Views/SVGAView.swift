import UIKit

/// 无视图预下载 SVGA 文件时使用的进度回调。
///
/// 回调参数位于 `0.0...1.0` 范围内。
public typealias SVGAViewPreloadProgressHandler = @Sendable (_ progress: Double) -> Void

// MARK: - Dynamic content configuration

/// 播放 SVGA 动画时应用的动态内容配置。
///
/// 使用 `SVGADynamicContent` 在动画加载完成前配置需要替换或隐藏的
/// sprite。每个 key 对应 SVGA 文件中的 sprite `imageKey`，也可以使用
/// 不带文件扩展名的 key。
///
/// ```swift
/// var content = SVGADynamicContent()
/// content.setImage(avatarImage, forKey: "avatar")
/// content.setAttributedText(nickname, forKey: "username")
/// content.setHidden(true, forKey: "badge")
/// playerView.play(named: "gift", dynamicContent: content)
/// ```
public struct SVGADynamicContent {

    struct Item {
        var image: UIImage?
        var text: NSAttributedString?
        var drawingBlock: SVGADynamicDrawingHandler?
        var hidden: Bool?

        init(image: UIImage? = nil,
             text: NSAttributedString? = nil,
             drawingBlock: SVGADynamicDrawingHandler? = nil,
             hidden: Bool? = nil) {
            self.image = image
            self.text = text
            self.drawingBlock = drawingBlock
            self.hidden = hidden
        }
    }

    var items: [String: Item] = [:]

    /// 创建空的动态内容配置。
    public init() {}

    /// 设置指定 sprite 的替换图片。
    ///
    /// - Parameters:
    ///   - image: 要显示的图片。
    ///   - key: SVGA 文件中的 sprite `imageKey`。
    public mutating func setImage(_ image: UIImage, forKey key: String) {
        items[key, default: Item()].image = image
    }

    /// 设置指定 sprite 上叠加显示的富文本。
    ///
    /// - Parameters:
    ///   - text: 要叠加显示的富文本。
    ///   - key: SVGA 文件中的 sprite `imageKey`。
    public mutating func setAttributedText(_ text: NSAttributedString, forKey key: String) {
        items[key, default: Item()].text = text
    }

    /// 设置指定 sprite 的自定义绘制回调。
    ///
    /// 回调会在 sprite 所属 layer 完成当前帧布局后调用。
    ///
    /// - Parameters:
    ///   - block: 自定义绘制回调。传入 `nil` 时不设置回调。
    ///   - key: SVGA 文件中的 sprite `imageKey`。
    public mutating func setDrawingBlock(
        _ block: (@MainActor @Sendable (CALayer, Int) -> Void)?,
        forKey key: String
    ) {
        items[key, default: Item()].drawingBlock = block
    }

    /// 设置指定 sprite 的隐藏状态。
    ///
    /// - Parameters:
    ///   - hidden: `true` 表示隐藏该 sprite，`false` 表示显示。
    ///   - key: SVGA 文件中的 sprite `imageKey`。
    public mutating func setHidden(_ hidden: Bool, forKey key: String) {
        items[key, default: Item()].hidden = hidden
    }
}

// MARK: - SVGAView

/// SVGA 播放视图的当前状态。
public enum SVGAViewState: Equatable, Sendable {
    /// 播放器处于空闲状态。
    case idle
    /// 播放器正在加载动画数据。
    case loading
    /// 动画数据已加载完成，可以开始播放。
    case ready
    /// 播放器正在播放动画。
    case playing
    /// 播放器已暂停播放。
    case paused
    /// 播放器已停止播放。
    case stopped
    /// 播放器加载或播放失败。
    case failed(SVGAViewError)

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
}

/// `SVGAView` 抛出或回调的错误类型。
public enum SVGAViewError: Error, Equatable, LocalizedError, Sendable {
    /// URL 缺失或无法解析。
    case invalidURL
    /// URL scheme 不受支持。
    case unsupportedURLScheme(String?)
    /// 在指定 bundle 中找不到资源。
    case resourceNotFound(String)
    /// SVGA 压缩包中缺少 `movie.binary` 或 `movie.spec`。
    case missingMovieFile
    /// SVGA JSON 数据格式无效。
    case invalidJSON
    /// 下载文件超过 `SVGAParser` 配置的大小限制。
    case fileTooLarge
    /// 加载任务被取消。
    case cancelled
    /// 底层错误的描述。
    case underlying(String)

    /// 错误的本地化说明。
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

/// `SVGAView` 向外派发的播放和加载事件。
public enum SVGAViewEvent: Equatable, Sendable {
    /// 播放器状态已变化。
    case stateChanged(SVGAViewState)
    /// 动画数据加载完成，播放器已进入 ready 状态。
    case ready
    /// 动画播放完成。
    ///
    /// 只有动画达到 `loops` 指定的次数后才会触发；无限循环不会触发该事件。
    case finished
    /// 当前帧已变化。
    case frameChanged(Int)
    /// 播放进度已变化，范围为 `0.0...1.0`。
    case percentageChanged(CGFloat)
    /// 网络下载进度已变化，范围为 `0.0...1.0`。
    case downloadProgress(Double)
    /// 动画加载失败。
    case loadFailed(SVGAViewError)
}

/// `SVGAView` 可加载的动画数据来源。
public enum SVGAViewSource: CustomDebugStringConvertible, Sendable {
    /// Bundle 中的 SVGA 资源名。
    case named(String, bundle: Bundle? = nil)
    /// HTTP 或 HTTPS 资源 URL。
    case remoteURL(URL)
    /// 自定义网络请求。
    case request(URLRequest)
    /// 本地文件 URL。
    case fileURL(URL)
    /// 内存中的 SVGA 数据。
    case data(Data, cacheKey: String)

    /// 适合调试输出的源描述。
    public var debugDescription: String {
        switch self {
        case .named(let name, _):
            return "named(\(name))"
        case .remoteURL(let url):
            return "remoteURL(\(url.absoluteString))"
        case .request(let request):
            return "request(\(request.url?.absoluteString ?? "nil"))"
        case .fileURL(let url):
            return "fileURL(\(url.path))"
        case .data(_, let cacheKey):
            return "data(cacheKey: \(cacheKey))"
        }
    }
}

private extension SVGAViewSource {
    var usesLocalResourceFrameSize: Bool {
        switch self {
        case .named, .fileURL:
            return true
        case .remoteURL, .request, .data:
            return false
        }
    }

    var reportsDownloadProgress: Bool {
        switch self {
        case .remoteURL, .request:
            return true
        case .named, .fileURL, .data:
            return false
        }
    }
}

/// 加载和播放 SVGA 动画的视图。
///
/// `SVGAView` 封装了动画解析、逐帧渲染、音频同步和动态内容替换。
/// 可以从 bundle 资源、网络 URL、本地文件 URL、`URLRequest` 或 `Data` 加载
/// `.svga` 动画。
///
/// ```swift
/// let playerView = SVGAView(frame: CGRect(x: 0, y: 0, width: 300, height: 300))
/// playerView.contentMode = .scaleAspectFit
/// view.addSubview(playerView)
/// playerView.play(named: "animation")
/// ```
///
/// 使用统一事件回调监听播放事件：
///
/// ```swift
/// playerView.onEvent = { event in
///     switch event {
///     case .finished:
///         print("animation finished")
///     case .loadFailed(let error):
///         print("load failed: \(error)")
///     default:
///         break
///     }
/// }
/// ```
///
/// 使用动态内容替换动画中的 sprite：
///
/// ```swift
/// var content = SVGADynamicContent()
/// content.setImage(avatar, forKey: "avatar")
/// playerView.play(named: "gift", dynamicContent: content)
/// ```
///
/// 从网络加载：
///
/// ```swift
/// playerView.play(remoteURL: URL(string: "https://example.com/anim.svga")!)
/// ```
///
/// 在 Interface Builder 中，可以设置 `resourcePath` 为资源名、HTTP(S) URL、
/// file URL 或本地绝对路径，并通过 `autoPlay` 控制是否自动播放。
@MainActor
open class SVGAView: UIView {

    // MARK: - Private engine

    private let engine = SVGAPlaybackEngine()
    private var loadTask: Task<Void, Never>?
    private var loadSequence: Int = 0
    private var resourcePathLoadTask: Task<Void, Never>?
    private var isEngineConfigured = false
    private var isPerformingInspectableResourcePathLoad = false
    private var sizesFrameToNextLocalResourcePathLoad = false

    // MARK: - Public properties

    /// 动画重复播放的次数。
    ///
    /// 值为 `0` 时无限循环。默认值为 `0`。
    public var loops: Int {
        get { engine.loops }
        set { engine.loops = newValue }
    }

    /// 一个布尔值，指示停止动画后是否清除当前画面。
    ///
    /// 默认值为 `true`。
    public var clearsAfterStop: Bool {
        get { engine.clearsAfterStop }
        set { engine.clearsAfterStop = newValue }
    }

    /// 动画结束后保留的画面。
    ///
    /// 仅当 `clearsAfterStop` 为 `false` 时生效。
    public var fillMode: SVGAFillMode {
        get { engine.fillMode }
        set { engine.fillMode = newValue }
    }

    /// 驱动动画的 display link 所使用的 run loop 模式。
    ///
    /// 默认值为 `.common`。
    public var mainRunLoopMode: RunLoop.Mode {
        get { engine.mainRunLoopMode }
        set { engine.mainRunLoopMode = newValue }
    }

    /// 一个布尔值，指示 `resourcePath` 加载完成后是否自动开始播放。
    ///
    /// `play` 方法始终会开始播放，`load` 方法使用 `startsPlayback` 显式控制。
    /// 默认值为 `true`。
    @IBInspectable public var autoPlay: Bool = true

    /// 播放器当前状态。
    public private(set) var state: SVGAViewState = .idle {
        didSet {
            guard oldValue != state else { return }
            emit(.stateChanged(state))
        }
    }

    // MARK: - Events

    /// 播放器事件回调。
    ///
    /// 回调总是在主线程触发。高频事件包括 `.frameChanged`、
    /// `.percentageChanged` 和 `.downloadProgress`。
    public var onEvent: ((SVGAViewEvent) -> Void)?

    // MARK: - Convenience loading (Interface Builder)

    /// Interface Builder 使用的动画资源路径。
    ///
    /// 该值可以是 bundle 资源名、HTTP(S) URL、file URL 或本地绝对路径。
    /// 设置后会自动开始加载，并根据 `autoPlay` 决定是否播放。
    @IBInspectable public var resourcePath: String? {
        didSet {
            if oldValue != nil {
                sizesFrameToNextLocalResourcePathLoad = false
            }
            scheduleInspectableResourcePathLoad()
        }
    }

    // MARK: - Init

    /// 使用指定 frame 创建播放器视图。
    ///
    /// - Parameter frame: 视图的初始 frame。
    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupEngine()
    }

    /// 使用资源路径创建播放器视图，并在本地资源加载完成后使用资源尺寸作为初始 frame size。
    ///
    /// - Parameter resourcePath: bundle 资源名、file URL、本地绝对路径或 HTTP(S) URL。
    public convenience init(resourcePath: String) {
        self.init(frame: .zero)
        let path = resourcePath.trimmingCharacters(in: .whitespacesAndNewlines)
        sizesFrameToNextLocalResourcePathLoad = !path.isEmpty
        self.resourcePath = resourcePath
        scheduleInspectableResourcePathLoad()
    }

    /// 使用 bundle 中的 SVGA 资源创建播放器视图。
    ///
    /// 加载完成后会根据 `autoPlay` 决定是否播放；如果初始 frame size 为 `.zero`，
    /// 会使用资源的原始尺寸作为初始 frame size。
    ///
    /// - Parameters:
    ///   - name: 资源名（不含 `.svga` 扩展名）。
    ///   - bundle: 资源所在的 bundle。传入 `nil` 时使用 `Bundle.main`。
    public convenience init(named name: String, in bundle: Bundle? = nil) {
        self.init(frame: .zero)
        startLoadTask(
            source: .named(name, bundle: bundle),
            dynamicContent: nil,
            startsPlaybackAfterLoad: autoPlay,
            sizesFrameToContentAfterLoad: true
        )
    }

    /// 使用本地文件 URL 创建播放器视图。
    ///
    /// 加载完成后会根据 `autoPlay` 决定是否播放；如果初始 frame size 为 `.zero`，
    /// 会使用资源的原始尺寸作为初始 frame size。
    ///
    /// - Parameter fileURL: 指向 SVGA 文件的本地文件 URL。
    public convenience init(fileURL: URL) {
        self.init(frame: .zero)
        startLoadTask(
            source: .fileURL(fileURL),
            dynamicContent: nil,
            startsPlaybackAfterLoad: autoPlay,
            sizesFrameToContentAfterLoad: true
        )
    }

    /// 使用 HTTP 或 HTTPS URL 创建播放器视图。
    ///
    /// 加载完成后会根据 `autoPlay` 决定是否播放。
    ///
    /// - Parameter remoteURL: SVGA 文件的 HTTP(S) URL。
    public convenience init(remoteURL: URL) {
        self.init(frame: .zero)
        startLoadTask(
            source: .remoteURL(remoteURL),
            dynamicContent: nil,
            startsPlaybackAfterLoad: autoPlay
        )
    }

    /// 从 storyboard 或 nib 反序列化播放器视图。
    ///
    /// - Parameter coder: 用于反序列化视图的 coder。
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupEngine()
    }

    private func setupEngine() {
        engine.onRenderLayerChanged = { [weak self] newLayer in
            guard let self else { return }
            if let l = newLayer {
                self.layer.addSublayer(l)
                self.engine.resize(bounds: self.bounds.size, contentMode: self.contentMode)
            }
        }
        engine.delegate = self
        isEngineConfigured = true
        scheduleInspectableResourcePathLoad()
    }

    private func emit(_ event: SVGAViewEvent) {
        onEvent?(event)
    }

    private func scheduleInspectableResourcePathLoad() {
        resourcePathLoadTask?.cancel()
        guard isEngineConfigured else { return }
        guard let path = resourcePath?.trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty
        else {
            resourcePathLoadTask = nil
            return
        }

        resourcePathLoadTask = Task { [weak self] in
            await Task.yield()
            guard let self, !Task.isCancelled else { return }
            guard self.resourcePath?.trimmingCharacters(in: .whitespacesAndNewlines) == path else { return }
            self.loadInspectableResourcePath(path)
            self.resourcePathLoadTask = nil
        }
    }

    private func loadInspectableResourcePath(_ path: String) {
        isPerformingInspectableResourcePathLoad = true
        defer { isPerformingInspectableResourcePathLoad = false }
        let source = inspectableResourceSource(for: path)
        let sizesFrameToContent = sizesFrameToNextLocalResourcePathLoad && source.usesLocalResourceFrameSize
        sizesFrameToNextLocalResourcePathLoad = false
        startLoadTask(
            source: source,
            dynamicContent: nil,
            startsPlaybackAfterLoad: autoPlay,
            sizesFrameToContentAfterLoad: sizesFrameToContent
        )
    }

    private func inspectableResourceSource(for path: String) -> SVGAViewSource {
        if let url = URL(string: path),
           let scheme = url.scheme?.lowercased() {
            switch scheme {
            case "http", "https":
                return .remoteURL(url)
            case "file":
                return .fileURL(url)
            default:
                return .remoteURL(url)
            }
        } else if path.hasPrefix("/") {
            return .fileURL(URL(fileURLWithPath: path))
        } else {
            return .named(path, bundle: nil)
        }
    }

    // MARK: - UIView lifecycle

    open override func willMove(toSuperview newSuperview: UIView?) {
        super.willMove(toSuperview: newSuperview)
        if newSuperview == nil {
            resourcePathLoadTask?.cancel()
            resourcePathLoadTask = nil
            cancelLoading(resetState: true)
            engine.stop()
            state = .stopped
        }
    }

    open override func layoutSubviews() {
        super.layoutSubviews()
        engine.resize(bounds: bounds.size, contentMode: contentMode)
    }

    open override var intrinsicContentSize: CGSize {
        engine.contentSize ?? super.intrinsicContentSize
    }

    open override func sizeThatFits(_ size: CGSize) -> CGSize {
        engine.contentSize ?? super.sizeThatFits(size)
    }

    // MARK: - Preload

    /// 无需创建视图，预先加载并缓存指定来源的 SVGA 文件。
    ///
    /// 该方法会完成下载、解压、解析和缓存。后续用相同来源 `play` 或 `load`
    /// 时会复用缓存。
    ///
    /// - Parameters:
    ///   - source: 动画数据来源。
    ///   - progressHandler: 可选的下载进度回调。非网络来源会在成功后回调 `1.0`。
    /// - Throws: 加载、解压或解析失败时抛出 `SVGAViewError`。
    @concurrent public nonisolated static func preload(
        _ source: SVGAViewSource,
        progressHandler: SVGAViewPreloadProgressHandler? = nil
    ) async throws {
        do {
            _ = try await fetchEntity(for: source, progressHandler: progressHandler)
            if !source.reportsDownloadProgress {
                progressHandler?(1.0)
            }
        } catch {
            throw viewError(from: error)
        }
    }

    /// 无需创建视图，预先加载并缓存 bundle 中的 SVGA 资源。
    @concurrent public nonisolated static func preload(
        named name: String,
        in bundle: Bundle? = nil,
        progressHandler: SVGAViewPreloadProgressHandler? = nil
    ) async throws {
        try await preload(.named(name, bundle: bundle), progressHandler: progressHandler)
    }

    /// 无需创建视图，预先下载并缓存 HTTP 或 HTTPS SVGA 文件。
    @concurrent public nonisolated static func preload(
        remoteURL url: URL,
        progressHandler: SVGAViewPreloadProgressHandler? = nil
    ) async throws {
        try await preload(.remoteURL(url), progressHandler: progressHandler)
    }

    /// 无需创建视图，使用自定义请求预先下载并缓存 SVGA 文件。
    @concurrent public nonisolated static func preload(
        request: URLRequest,
        progressHandler: SVGAViewPreloadProgressHandler? = nil
    ) async throws {
        try await preload(.request(request), progressHandler: progressHandler)
    }

    /// 无需创建视图，预先加载并缓存本地文件 URL 指向的 SVGA 文件。
    @concurrent public nonisolated static func preload(
        fileURL: URL,
        progressHandler: SVGAViewPreloadProgressHandler? = nil
    ) async throws {
        try await preload(.fileURL(fileURL), progressHandler: progressHandler)
    }

    /// 无需创建视图，预先解析并缓存内存中的 SVGA 数据。
    @concurrent public nonisolated static func preload(
        data: Data,
        cacheKey: String,
        progressHandler: SVGAViewPreloadProgressHandler? = nil
    ) async throws {
        try await preload(.data(data, cacheKey: cacheKey), progressHandler: progressHandler)
    }

    // MARK: - Play

    /// 加载指定来源的 SVGA 文件并开始播放。
    ///
    /// `play` 的语义始终是加载并播放，不受 `autoPlay` 影响。`autoPlay` 仅用于
    /// `resourcePath` 和 Interface Builder 加载。
    ///
    /// - Parameters:
    ///   - source: 动画数据来源。
    ///   - dynamicContent: 可选的动态内容配置。
    public func play(_ source: SVGAViewSource, dynamicContent: SVGADynamicContent? = nil) {
        startLoadTask(source: source, dynamicContent: dynamicContent, startsPlaybackAfterLoad: true)
    }

    /// 加载指定来源的 SVGA 文件，配置动态内容后开始播放。
    ///
    /// - Parameters:
    ///   - source: 动画数据来源。
    ///   - configureDynamicContent: 动态内容配置闭包。
    public func play(
        _ source: SVGAViewSource,
        configureDynamicContent: (inout SVGADynamicContent) -> Void
    ) {
        play(source, dynamicContent: makeDynamicContent(configureDynamicContent))
    }

    /// 从 bundle 加载 SVGA 资源并开始播放。
    ///
    /// - Parameters:
    ///   - name: 资源名（不含 `.svga` 扩展名）。
    ///   - bundle: 资源所在的 bundle。传入 `nil` 时使用 `Bundle.main`。
    ///   - dynamicContent: 可选的动态内容配置。
    public func play(named name: String, in bundle: Bundle? = nil, dynamicContent: SVGADynamicContent? = nil) {
        play(.named(name, bundle: bundle), dynamicContent: dynamicContent)
    }

    /// 从 bundle 加载 SVGA 资源，配置动态内容后开始播放。
    public func play(
        named name: String,
        in bundle: Bundle? = nil,
        configureDynamicContent: (inout SVGADynamicContent) -> Void
    ) {
        play(.named(name, bundle: bundle), configureDynamicContent: configureDynamicContent)
    }

    /// 从 HTTP 或 HTTPS URL 加载 SVGA 文件并开始播放。
    ///
    /// - Parameters:
    ///   - url: SVGA 文件的 HTTP(S) URL。
    ///   - dynamicContent: 可选的动态内容配置。
    public func play(remoteURL url: URL, dynamicContent: SVGADynamicContent? = nil) {
        play(.remoteURL(url), dynamicContent: dynamicContent)
    }

    /// 从 HTTP 或 HTTPS URL 加载 SVGA 文件，配置动态内容后开始播放。
    public func play(
        remoteURL url: URL,
        configureDynamicContent: (inout SVGADynamicContent) -> Void
    ) {
        play(.remoteURL(url), configureDynamicContent: configureDynamicContent)
    }

    /// 使用自定义请求加载 SVGA 文件并开始播放。
    ///
    /// - Parameters:
    ///   - request: 用于下载 SVGA 文件的请求。
    ///   - dynamicContent: 可选的动态内容配置。
    public func play(request: URLRequest, dynamicContent: SVGADynamicContent? = nil) {
        play(.request(request), dynamicContent: dynamicContent)
    }

    /// 使用自定义请求加载 SVGA 文件，配置动态内容后开始播放。
    public func play(
        request: URLRequest,
        configureDynamicContent: (inout SVGADynamicContent) -> Void
    ) {
        play(.request(request), configureDynamicContent: configureDynamicContent)
    }

    /// 从本地文件 URL 加载 SVGA 文件并开始播放。
    ///
    /// - Parameters:
    ///   - fileURL: 指向 SVGA 文件的本地文件 URL。
    ///   - dynamicContent: 可选的动态内容配置。
    public func play(fileURL: URL, dynamicContent: SVGADynamicContent? = nil) {
        play(.fileURL(fileURL), dynamicContent: dynamicContent)
    }

    /// 从本地文件 URL 加载 SVGA 文件，配置动态内容后开始播放。
    public func play(
        fileURL: URL,
        configureDynamicContent: (inout SVGADynamicContent) -> Void
    ) {
        play(.fileURL(fileURL), configureDynamicContent: configureDynamicContent)
    }

    /// 从内存数据加载 SVGA 文件并开始播放。
    ///
    /// - Parameters:
    ///   - data: SVGA 文件数据。
    ///   - cacheKey: 用于读写内存缓存和磁盘缓存的稳定 key。
    ///   - dynamicContent: 可选的动态内容配置。
    public func play(data: Data, cacheKey: String, dynamicContent: SVGADynamicContent? = nil) {
        play(.data(data, cacheKey: cacheKey), dynamicContent: dynamicContent)
    }

    /// 从内存数据加载 SVGA 文件，配置动态内容后开始播放。
    public func play(
        data: Data,
        cacheKey: String,
        configureDynamicContent: (inout SVGADynamicContent) -> Void
    ) {
        play(.data(data, cacheKey: cacheKey), configureDynamicContent: configureDynamicContent)
    }

    // MARK: - Load

    /// 加载指定来源的 SVGA 文件。
    ///
    /// 默认只加载动画，不会自动开始播放。需要加载完成后立即播放时，传入
    /// `startsPlayback: true`。
    ///
    /// - Parameters:
    ///   - source: 动画数据来源。
    ///   - dynamicContent: 可选的动态内容配置。
    ///   - startsPlayback: `true` 表示加载完成后立即播放。
    /// - Throws: 加载、解压或解析失败时抛出 `SVGAViewError`。
    public func load(
        _ source: SVGAViewSource,
        dynamicContent: SVGADynamicContent? = nil,
        startsPlayback: Bool = false
    ) async throws {
        resourcePathLoadTask?.cancel()
        resourcePathLoadTask = nil
        cancelLoading(resetState: false)
        beginLoadingState()
        do {
            try await performLoad(source: source, dynamicContent: dynamicContent)
            state = .ready
            emit(.ready)
            if startsPlayback {
                start()
            }
        } catch {
            let mapped = Self.viewError(from: error)
            state = .failed(mapped)
            emit(.loadFailed(mapped))
            throw mapped
        }
    }

    /// 加载指定来源的 SVGA 文件，并在加载前配置动态内容。
    public func load(
        _ source: SVGAViewSource,
        startsPlayback: Bool = false,
        configureDynamicContent: (inout SVGADynamicContent) -> Void
    ) async throws {
        try await load(
            source,
            dynamicContent: makeDynamicContent(configureDynamicContent),
            startsPlayback: startsPlayback
        )
    }

    /// 从 bundle 加载 SVGA 资源并准备播放。
    ///
    /// - Parameters:
    ///   - name: 资源名（不含 `.svga` 扩展名）。
    ///   - bundle: 资源所在的 bundle。传入 `nil` 时使用 `Bundle.main`。
    ///   - dynamicContent: 可选的动态内容配置。
    ///   - startsPlayback: `true` 表示加载完成后立即播放。
    /// - Throws: 加载、解压或解析失败时抛出 `SVGAViewError`。
    public func load(
        named name: String,
        in bundle: Bundle? = nil,
        dynamicContent: SVGADynamicContent? = nil,
        startsPlayback: Bool = false
    ) async throws {
        try await load(.named(name, bundle: bundle), dynamicContent: dynamicContent, startsPlayback: startsPlayback)
    }

    /// 从 bundle 加载 SVGA 资源，并在加载前配置动态内容。
    public func load(
        named name: String,
        in bundle: Bundle? = nil,
        startsPlayback: Bool = false,
        configureDynamicContent: (inout SVGADynamicContent) -> Void
    ) async throws {
        try await load(
            .named(name, bundle: bundle),
            startsPlayback: startsPlayback,
            configureDynamicContent: configureDynamicContent
        )
    }

    /// 从 HTTP 或 HTTPS URL 加载 SVGA 文件并准备播放。
    ///
    /// - Parameters:
    ///   - url: SVGA 文件的远程 URL。
    ///   - dynamicContent: 可选的动态内容配置。
    ///   - startsPlayback: `true` 表示加载完成后立即播放。
    /// - Throws: 加载、解压或解析失败时抛出 `SVGAViewError`。
    public func load(
        remoteURL url: URL,
        dynamicContent: SVGADynamicContent? = nil,
        startsPlayback: Bool = false
    ) async throws {
        try await load(.remoteURL(url), dynamicContent: dynamicContent, startsPlayback: startsPlayback)
    }

    /// 从 HTTP 或 HTTPS URL 加载 SVGA 文件，并在加载前配置动态内容。
    public func load(
        remoteURL url: URL,
        startsPlayback: Bool = false,
        configureDynamicContent: (inout SVGADynamicContent) -> Void
    ) async throws {
        try await load(.remoteURL(url), startsPlayback: startsPlayback, configureDynamicContent: configureDynamicContent)
    }

    /// 使用自定义请求加载 SVGA 文件并准备播放。
    ///
    /// - Parameters:
    ///   - request: 用于下载 SVGA 文件的请求。
    ///   - dynamicContent: 可选的动态内容配置。
    ///   - startsPlayback: `true` 表示加载完成后立即播放。
    /// - Throws: 加载、解压或解析失败时抛出 `SVGAViewError`。
    public func load(
        request: URLRequest,
        dynamicContent: SVGADynamicContent? = nil,
        startsPlayback: Bool = false
    ) async throws {
        try await load(.request(request), dynamicContent: dynamicContent, startsPlayback: startsPlayback)
    }

    /// 使用自定义请求加载 SVGA 文件，并在加载前配置动态内容。
    public func load(
        request: URLRequest,
        startsPlayback: Bool = false,
        configureDynamicContent: (inout SVGADynamicContent) -> Void
    ) async throws {
        try await load(.request(request), startsPlayback: startsPlayback, configureDynamicContent: configureDynamicContent)
    }

    /// 从本地文件 URL 加载 SVGA 文件并准备播放。
    ///
    /// - Parameters:
    ///   - fileURL: 指向 SVGA 文件的本地文件 URL。
    ///   - dynamicContent: 可选的动态内容配置。
    ///   - startsPlayback: `true` 表示加载完成后立即播放。
    /// - Throws: 加载、解压或解析失败时抛出 `SVGAViewError`。
    public func load(
        fileURL: URL,
        dynamicContent: SVGADynamicContent? = nil,
        startsPlayback: Bool = false
    ) async throws {
        try await load(.fileURL(fileURL), dynamicContent: dynamicContent, startsPlayback: startsPlayback)
    }

    /// 从本地文件 URL 加载 SVGA 文件，并在加载前配置动态内容。
    public func load(
        fileURL: URL,
        startsPlayback: Bool = false,
        configureDynamicContent: (inout SVGADynamicContent) -> Void
    ) async throws {
        try await load(.fileURL(fileURL), startsPlayback: startsPlayback, configureDynamicContent: configureDynamicContent)
    }

    /// 从内存数据加载 SVGA 文件并准备播放。
    ///
    /// - Parameters:
    ///   - data: SVGA 文件数据。
    ///   - cacheKey: 用于读写内存缓存和磁盘缓存的稳定 key。
    ///   - dynamicContent: 可选的动态内容配置。
    ///   - startsPlayback: `true` 表示加载完成后立即播放。
    /// - Throws: 解压或解析失败时抛出 `SVGAViewError`。
    public func load(
        data: Data,
        cacheKey: String,
        dynamicContent: SVGADynamicContent? = nil,
        startsPlayback: Bool = false
    ) async throws {
        try await load(.data(data, cacheKey: cacheKey), dynamicContent: dynamicContent, startsPlayback: startsPlayback)
    }

    /// 从内存数据加载 SVGA 文件，并在加载前配置动态内容。
    public func load(
        data: Data,
        cacheKey: String,
        startsPlayback: Bool = false,
        configureDynamicContent: (inout SVGADynamicContent) -> Void
    ) async throws {
        try await load(
            .data(data, cacheKey: cacheKey),
            startsPlayback: startsPlayback,
            configureDynamicContent: configureDynamicContent
        )
    }

    /// 取消当前正在进行的加载任务。
    public func cancelLoading() {
        cancelLoading(resetState: true)
    }

    private func cancelLoading(resetState: Bool) {
        loadSequence += 1
        loadTask?.cancel()
        loadTask = nil
        if resetState, state.isLoading {
            state = .idle
        }
    }

    private func makeDynamicContent(
        _ configureDynamicContent: (inout SVGADynamicContent) -> Void
    ) -> SVGADynamicContent {
        var dynamicContent = SVGADynamicContent()
        configureDynamicContent(&dynamicContent)
        return dynamicContent
    }

    private func startLoadTask(
        source: SVGAViewSource,
        dynamicContent: SVGADynamicContent?,
        startsPlaybackAfterLoad: Bool
    ) {
        startLoadTask(
            source: source,
            dynamicContent: dynamicContent,
            startsPlaybackAfterLoad: startsPlaybackAfterLoad,
            sizesFrameToContentAfterLoad: false
        )
    }

    private func startLoadTask(
        source: SVGAViewSource,
        dynamicContent: SVGADynamicContent?,
        startsPlaybackAfterLoad: Bool,
        sizesFrameToContentAfterLoad: Bool
    ) {
        if !isPerformingInspectableResourcePathLoad {
            resourcePathLoadTask?.cancel()
            resourcePathLoadTask = nil
        }
        cancelLoading(resetState: false)
        beginLoadingState()
        let sequence = loadSequence
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.performLoad(
                    source: source,
                    dynamicContent: dynamicContent,
                    sizesFrameToContentAfterLoad: sizesFrameToContentAfterLoad
                )
                guard !Task.isCancelled, self.loadSequence == sequence else { return }
                self.state = .ready
                self.emit(.ready)
                if startsPlaybackAfterLoad {
                    self.start()
                }
            } catch {
                guard !Task.isCancelled, self.loadSequence == sequence else { return }
                let mapped = Self.viewError(from: error)
                self.state = .failed(mapped)
                self.emit(.loadFailed(mapped))
            }
            if self.loadSequence == sequence {
                self.loadTask = nil
            }
        }
    }

    private func performLoad(
        source: SVGAViewSource,
        dynamicContent: SVGADynamicContent?,
        sizesFrameToContentAfterLoad: Bool = false
    ) async throws {
        let progressHandler = makeProgressHandler()
        let entity = try await Self.fetchEntity(for: source, progressHandler: progressHandler)
        try Task.checkCancellation()
        engine.clearDynamicContent()
        if let content = dynamicContent {
            applyDynamicContent(content)
        }
        try Task.checkCancellation()
        if sizesFrameToContentAfterLoad {
            applyInitialResourceFrameSize(entity.videoSize)
        }
        engine.videoEntity = entity
        invalidateIntrinsicContentSize()
    }

    private func applyInitialResourceFrameSize(_ size: CGSize) {
        guard bounds.size == .zero,
              size.width > 0,
              size.height > 0
        else { return }
        var initialFrame = frame
        initialFrame.size = size
        frame = initialFrame
    }

    private nonisolated static func fetchEntity(
        for source: SVGAViewSource,
        progressHandler: SVGADownloadProgressHandler?
    ) async throws -> SVGA.VideoEntity {
        switch source {
        case .named(let name, let bundle):
            return try await SVGAParser.shared.parse(named: name, in: bundle)
        case .remoteURL(let url):
            try validateRemoteURL(url)
            return try await SVGAParser.shared.parse(url: url, progressHandler: progressHandler)
        case .request(let request):
            guard let url = request.url else {
                throw SVGAViewError.invalidURL
            }
            try validateRemoteURL(url)
            return try await SVGAParser.shared.parse(request: request, progressHandler: progressHandler)
        case .fileURL(let url):
            guard url.isFileURL else {
                throw SVGAViewError.unsupportedURLScheme(url.scheme)
            }
            return try await SVGAParser.shared.parse(fileURL: url)
        case .data(let data, let cacheKey):
            return try await SVGAParser.shared.parse(data: data, cacheKey: cacheKey)
        }
    }

    private nonisolated static func validateRemoteURL(_ url: URL) throws {
        let scheme = url.scheme?.lowercased()
        guard scheme == "http" || scheme == "https" else {
            throw SVGAViewError.unsupportedURLScheme(url.scheme)
        }
    }

    private func makeProgressHandler() -> SVGADownloadProgressHandler {
        { [weak self] progress in
            Task { @MainActor in
                self?.emit(.downloadProgress(progress))
            }
        }
    }

    private func beginLoadingState() {
        state = .loading
    }

    private nonisolated static func viewError(from error: Error) -> SVGAViewError {
        if error is CancellationError {
            return .cancelled
        }
        if let viewError = error as? SVGAViewError {
            return viewError
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

    // MARK: - Dynamic content

    /// 替换指定 sprite 的图片。
    ///
    /// 可以在加载完成后或播放过程中调用。
    ///
    /// - Parameters:
    ///   - image: 要显示的图片。
    ///   - key: SVGA 文件中的 sprite `imageKey`。
    public func setImage(_ image: UIImage, forKey key: String) {
        engine.setImage(image, forKey: key)
    }

    /// 移除指定 sprite 的动态图片，并恢复 SVGA 文件中的原始图片。
    ///
    /// - Parameter key: SVGA 文件中的 sprite `imageKey`。
    public func removeImage(forKey key: String) {
        engine.removeImage(forKey: key)
    }

    /// 在指定 sprite 上叠加富文本。
    ///
    /// 可以在加载完成后或播放过程中调用。
    ///
    /// - Parameters:
    ///   - text: 要叠加显示的富文本。
    ///   - key: SVGA 文件中的 sprite `imageKey`。
    public func setAttributedText(_ text: NSAttributedString, forKey key: String) {
        engine.setAttributedText(text, forKey: key)
    }

    /// 移除指定 sprite 上的动态富文本。
    ///
    /// - Parameter key: SVGA 文件中的 sprite `imageKey`。
    public func removeAttributedText(forKey key: String) {
        engine.removeAttributedText(forKey: key)
    }

    /// 设置指定 sprite 的自定义绘制回调。
    ///
    /// - Parameters:
    ///   - block: 自定义绘制回调。传入 `nil` 时移除回调。
    ///   - key: SVGA 文件中的 sprite `imageKey`。
    public func setDrawingBlock(
        _ block: (@MainActor @Sendable (CALayer, Int) -> Void)?,
        forKey key: String
    ) {
        engine.setDrawingBlock(block, forKey: key)
    }

    /// 移除指定 sprite 的自定义绘制回调。
    ///
    /// - Parameter key: SVGA 文件中的 sprite `imageKey`。
    public func removeDrawingBlock(forKey key: String) {
        engine.removeDrawingBlock(forKey: key)
    }

    /// 设置指定 sprite 的隐藏状态。
    ///
    /// - Parameters:
    ///   - hidden: `true` 表示隐藏该 sprite，`false` 表示显示。
    ///   - key: SVGA 文件中的 sprite `imageKey`。
    public func setHidden(_ hidden: Bool, forKey key: String) {
        engine.setHidden(hidden, forKey: key)
    }

    /// 移除指定 sprite 的动态隐藏状态，并恢复显示。
    ///
    /// - Parameter key: SVGA 文件中的 sprite `imageKey`。
    public func removeHidden(forKey key: String) {
        engine.removeHidden(forKey: key)
    }

    /// 清除所有动态内容（图片、文本、绘制回调、隐藏状态）。
    public func clearDynamicContent() {
        engine.clearDynamicContent()
    }

    // MARK: - Playback control

    /// 从当前动画的第一帧开始播放全部帧。
    ///
    /// 需要先通过 `load(_:dynamicContent:startsPlayback:)` 或任一 `play` 方法加载数据。
    public func start() {
        if engine.start() {
            state = .playing
        }
    }

    /// 播放指定帧范围。
    ///
    /// ```swift
    /// // 播放第 10 ~ 30 帧，正向
    /// playerView.start(range: 10..<30, reverse: false)
    ///
    /// // 倒放第 0 ~ 20 帧
    /// playerView.start(range: 0..<20, reverse: true)
    /// ```
    ///
    /// - Parameters:
    ///   - range: 要播放的帧范围。范围会被限制在动画的有效帧范围内。
    ///   - reverse: 是否倒放。
    public func start(range: Range<Int>, reverse: Bool) {
        if engine.start(range: range, reverse: reverse) {
            state = .playing
        }
    }

    /// 暂停动画，保留当前画面。
    public func pause() {
        if engine.pause() {
            state = .paused
        }
    }

    /// 停止动画。
    ///
    /// 是否清除画面取决于 `clearsAfterStop`。
    public func stop() {
        stop(cancelLoading: true)
    }

    /// 停止动画，并可选择是否取消正在进行的加载任务。
    ///
    /// - Parameter shouldCancelLoading: `true` 表示同时取消当前加载任务。
    public func stop(cancelLoading shouldCancelLoading: Bool) {
        let wasLoading = state.isLoading
        if shouldCancelLoading {
            cancelLoading(resetState: true)
        }
        engine.stop()
        state = wasLoading && shouldCancelLoading ? .idle : .stopped
    }

    /// 跳转到指定帧。
    ///
    /// ```swift
    /// // 跳转到第 5 帧并暂停
    /// playerView.seek(toFrame: 5, startsPlayback: false)
    ///
    /// // 跳转到第 10 帧并继续播放
    /// playerView.seek(toFrame: 10, startsPlayback: true)
    /// ```
    ///
    /// - Parameters:
    ///   - frame: 目标帧索引。
    ///   - startsPlayback: `true` 表示跳转后继续播放，`false` 表示跳转后暂停。
    public func seek(toFrame frame: Int, startsPlayback: Bool) {
        if engine.seek(toFrame: frame, startsPlayback: startsPlayback) {
            state = startsPlayback ? .playing : .paused
        }
    }

    /// 跳转到指定进度。
    ///
    /// ```swift
    /// // 跳转到 50% 位置并暂停
    /// playerView.seek(toProgress: 0.5, startsPlayback: false)
    /// ```
    ///
    /// - Parameters:
    ///   - progress: 目标播放进度。取值会被限制在 `0.0...1.0` 范围内。
    ///   - startsPlayback: `true` 表示跳转后继续播放，`false` 表示跳转后暂停。
    public func seek(toProgress progress: CGFloat, startsPlayback: Bool) {
        if engine.seek(toProgress: progress, startsPlayback: startsPlayback) {
            state = startsPlayback ? .playing : .paused
        }
    }

    /// 清除动画画面和所有图层。
    public func clear() {
        clear(cancelLoading: true)
    }

    /// 清除动画画面和所有图层，并可选择是否取消正在进行的加载任务。
    ///
    /// - Parameter shouldCancelLoading: `true` 表示同时取消当前加载任务。
    public func clear(cancelLoading shouldCancelLoading: Bool) {
        if shouldCancelLoading {
            cancelLoading(resetState: true)
        }
        engine.clear()
        state = .idle
    }
}

// MARK: - SVGAPlaybackEngineDelegate (bridge engine events to callbacks)

extension SVGAView: SVGAPlaybackEngineDelegate {
    func svgaPlaybackEngineDidFinishAnimation(_ engine: SVGAPlaybackEngine) {
        state = .stopped
        emit(.finished)
    }

    func svgaPlaybackEngine(_ engine: SVGAPlaybackEngine, didAnimateToFrame frame: Int) {
        emit(.frameChanged(frame))
    }

    func svgaPlaybackEngine(_ engine: SVGAPlaybackEngine, didAnimateToPercentage percentage: CGFloat) {
        emit(.percentageChanged(percentage))
    }
}
