import UIKit

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
        var drawingBlock: SVGADynamicDrawingBlock?
        var hidden: Bool?

        init(image: UIImage? = nil,
             text: NSAttributedString? = nil,
             drawingBlock: SVGADynamicDrawingBlock? = nil,
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
public enum SVGAViewSource: CustomDebugStringConvertible {
    /// Bundle 中的 SVGA 资源名。
    case named(String, bundle: Bundle?)
    /// HTTP 或 HTTPS 资源 URL。
    case url(URL)
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
/// playerView.play(url: URL(string: "https://example.com/anim.svga")!)
/// ```
///
/// 在 Interface Builder 中，可以设置 `filePath` 为资源名、HTTP(S) URL、
/// file URL 或本地绝对路径，并通过 `autoPlay` 控制是否自动播放。
@MainActor
public class SVGAView: UIView {

    // MARK: - Private engine

    private let engine = SVGAPlaybackEngine()
    private var loadTask: Task<Void, Never>?
    private var loadGeneration: Int = 0
    private var filePathLoadTask: Task<Void, Never>?
    private var isEngineConfigured = false
    private var isRunningInspectableFilePathLoad = false

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

    /// 一个布尔值，指示加载完成后是否自动开始播放。
    ///
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
    @IBInspectable public var filePath: String? {
        didSet {
            scheduleInspectableFilePathLoad()
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

    /// 从 storyboard 或 nib 反序列化播放器视图。
    ///
    /// - Parameter coder: 用于反序列化视图的 coder。
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
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
        isEngineConfigured = true
        scheduleInspectableFilePathLoad()
    }

    private func emit(_ event: SVGAViewEvent) {
        onEvent?(event)
    }

    private func scheduleInspectableFilePathLoad() {
        filePathLoadTask?.cancel()
        guard isEngineConfigured else { return }
        guard let path = filePath?.trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty
        else {
            filePathLoadTask = nil
            return
        }

        filePathLoadTask = Task { [weak self] in
            await Task.yield()
            guard let self, !Task.isCancelled else { return }
            guard self.filePath?.trimmingCharacters(in: .whitespacesAndNewlines) == path else { return }
            self.loadInspectableFilePath(path)
            self.filePathLoadTask = nil
        }
    }

    private func loadInspectableFilePath(_ path: String) {
        isRunningInspectableFilePathLoad = true
        defer { isRunningInspectableFilePathLoad = false }
        if let url = URL(string: path),
           let scheme = url.scheme?.lowercased() {
            switch scheme {
            case "http", "https":
                play(url: url)
            case "file":
                play(fileURL: url)
            default:
                play(url: url)
            }
        } else if path.hasPrefix("/") {
            play(fileURL: URL(fileURLWithPath: path))
        } else {
            play(named: path)
        }
    }

    // MARK: - UIView lifecycle

    public override func willMove(toSuperview newSuperview: UIView?) {
        super.willMove(toSuperview: newSuperview)
        if newSuperview == nil {
            filePathLoadTask?.cancel()
            filePathLoadTask = nil
            cancelLoading(resetState: true)
            engine.stopAnimation()
            state = .stopped
        }
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        engine.resize(bounds: bounds.size, contentMode: contentMode)
    }

    // MARK: - Play

    /// 从 bundle 加载 SVGA 资源，并根据 `autoPlay` 决定是否播放。
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
    ///   - bundle: 资源所在的 bundle。传入 `nil` 时使用 `Bundle.main`。
    ///   - dynamicContent: 可选的动态内容配置。
    public func play(named name: String, in bundle: Bundle? = nil, dynamicContent: SVGADynamicContent? = nil) {
        startLoadTask(source: .named(name, bundle: bundle), dynamicContent: dynamicContent, autoStart: autoPlay)
    }

    /// 从 HTTP 或 HTTPS URL 加载 SVGA 文件，并根据 `autoPlay` 决定是否播放。
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
        startLoadTask(source: .url(url), dynamicContent: dynamicContent, autoStart: autoPlay)
    }

    /// 从 bundle 加载 SVGA 资源并准备播放。
    ///
    /// 该方法只加载动画，不会自动开始播放。加载完成后调用 `startAnimation()`
    /// 开始播放。
    ///
    /// - Parameters:
    ///   - name: 资源名（不含 `.svga` 扩展名）。
    ///   - bundle: 资源所在的 bundle。传入 `nil` 时使用 `Bundle.main`。
    ///   - dynamicContent: 可选的动态内容配置。
    /// - Throws: 加载、解压或解析失败时抛出 `SVGAViewError`。
    public func load(named name: String, in bundle: Bundle? = nil, dynamicContent: SVGADynamicContent? = nil) async throws {
        try await load(source: .named(name, bundle: bundle), dynamicContent: dynamicContent)
    }

    /// 从 HTTP 或 HTTPS URL 加载 SVGA 文件并准备播放。
    ///
    /// - Parameters:
    ///   - url: SVGA 文件的远程 URL。
    ///   - dynamicContent: 可选的动态内容配置。
    /// - Throws: 加载、解压或解析失败时抛出 `SVGAViewError`。
    public func load(url: URL, dynamicContent: SVGADynamicContent? = nil) async throws {
        try await load(source: .url(url), dynamicContent: dynamicContent)
    }

    /// 使用自定义请求加载 SVGA 文件并准备播放。
    ///
    /// - Parameters:
    ///   - request: 用于下载 SVGA 文件的请求。
    ///   - dynamicContent: 可选的动态内容配置。
    /// - Throws: 加载、解压或解析失败时抛出 `SVGAViewError`。
    public func load(request: URLRequest, dynamicContent: SVGADynamicContent? = nil) async throws {
        try await load(source: .request(request), dynamicContent: dynamicContent)
    }

    /// 从本地文件 URL 加载 SVGA 文件并准备播放。
    ///
    /// - Parameters:
    ///   - fileURL: 指向 SVGA 文件的本地文件 URL。
    ///   - dynamicContent: 可选的动态内容配置。
    /// - Throws: 加载、解压或解析失败时抛出 `SVGAViewError`。
    public func load(fileURL: URL, dynamicContent: SVGADynamicContent? = nil) async throws {
        try await load(source: .fileURL(fileURL), dynamicContent: dynamicContent)
    }

    /// 从内存数据加载 SVGA 文件并准备播放。
    ///
    /// - Parameters:
    ///   - data: SVGA 文件数据。
    ///   - cacheKey: 用于读写内存缓存和磁盘缓存的稳定 key。
    ///   - dynamicContent: 可选的动态内容配置。
    /// - Throws: 解压或解析失败时抛出 `SVGAViewError`。
    public func load(data: Data, cacheKey: String, dynamicContent: SVGADynamicContent? = nil) async throws {
        try await load(source: .data(data, cacheKey: cacheKey), dynamicContent: dynamicContent)
    }

    /// 加载指定来源的 SVGA 文件并准备播放。
    ///
    /// 该方法只加载动画，不会自动开始播放。加载完成后，播放器状态变为
    /// `SVGAViewState.ready`。
    ///
    /// - Parameters:
    ///   - source: 动画数据来源。
    ///   - dynamicContent: 可选的动态内容配置。
    /// - Throws: 加载、解压或解析失败时抛出 `SVGAViewError`。
    public func load(source: SVGAViewSource, dynamicContent: SVGADynamicContent? = nil) async throws {
        filePathLoadTask?.cancel()
        filePathLoadTask = nil
        cancelLoading(resetState: false)
        beginLoadingState()
        do {
            try await performLoad(source: source, dynamicContent: dynamicContent)
            state = .ready
            emit(.ready)
        } catch {
            let mapped = playerError(from: error)
            state = .failed(mapped)
            emit(.loadFailed(mapped))
            throw mapped
        }
    }

    /// 取消当前正在进行的加载任务。
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

    /// 使用自定义请求加载 SVGA 文件，并根据 `autoPlay` 决定是否播放。
    ///
    /// - Parameters:
    ///   - request: 用于下载 SVGA 文件的请求。
    ///   - dynamicContent: 可选的动态内容配置。
    public func play(request: URLRequest, dynamicContent: SVGADynamicContent? = nil) {
        startLoadTask(source: .request(request), dynamicContent: dynamicContent, autoStart: autoPlay)
    }

    /// 从本地文件 URL 加载 SVGA 文件，并根据 `autoPlay` 决定是否播放。
    ///
    /// - Parameters:
    ///   - fileURL: 指向 SVGA 文件的本地文件 URL。
    ///   - dynamicContent: 可选的动态内容配置。
    public func play(fileURL: URL, dynamicContent: SVGADynamicContent? = nil) {
        startLoadTask(source: .fileURL(fileURL), dynamicContent: dynamicContent, autoStart: autoPlay)
    }

    /// 从内存数据加载 SVGA 文件，并根据 `autoPlay` 决定是否播放。
    ///
    /// - Parameters:
    ///   - data: SVGA 文件数据。
    ///   - cacheKey: 用于读写内存缓存和磁盘缓存的稳定 key。
    ///   - dynamicContent: 可选的动态内容配置。
    public func play(data: Data, cacheKey: String, dynamicContent: SVGADynamicContent? = nil) {
        startLoadTask(source: .data(data, cacheKey: cacheKey), dynamicContent: dynamicContent, autoStart: autoPlay)
    }

    private func startLoadTask(source: SVGAViewSource, dynamicContent: SVGADynamicContent?, autoStart: Bool) {
        if !isRunningInspectableFilePathLoad {
            filePathLoadTask?.cancel()
            filePathLoadTask = nil
        }
        cancelLoading(resetState: false)
        beginLoadingState()
        let generation = loadGeneration
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.performLoad(source: source, dynamicContent: dynamicContent)
                guard !Task.isCancelled, self.loadGeneration == generation else { return }
                self.state = .ready
                self.emit(.ready)
                if autoStart {
                    self.startAnimation()
                }
            } catch {
                guard !Task.isCancelled, self.loadGeneration == generation else { return }
                let mapped = self.playerError(from: error)
                self.state = .failed(mapped)
                self.emit(.loadFailed(mapped))
            }
            if self.loadGeneration == generation {
                self.loadTask = nil
            }
        }
    }

    private func performLoad(source: SVGAViewSource, dynamicContent: SVGADynamicContent?) async throws {
        let progressHandler = makeProgressHandler()
        let entity = try await fetchEntity(for: source, progressHandler: progressHandler)
        try Task.checkCancellation()
        engine.clearDynamicObjects()
        if let content = dynamicContent {
            applyDynamicContent(content)
        }
        try Task.checkCancellation()
        engine.videoItem = entity
    }

    private func fetchEntity(
        for source: SVGAViewSource,
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

    private func validateRemoteURL(_ url: URL) throws {
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

    private func playerError(from error: Error) -> SVGAViewError {
        if error is CancellationError {
            return .cancelled
        }
        if let playerError = error as? SVGAViewError {
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
        engine.clearDynamicObjects()
    }

    // MARK: - Playback control

    /// 从当前动画的第一帧开始播放全部帧。
    ///
    /// 需要先通过 `load(source:dynamicContent:)` 或任一 `play` 方法加载数据。
    public func startAnimation() {
        if engine.startAnimation() {
            state = .playing
        }
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
    ///   - range: 要播放的帧范围。范围会被限制在动画的有效帧范围内。
    ///   - reverse: 是否倒放。
    public func startAnimation(range: Range<Int>, reverse: Bool) {
        if engine.startAnimation(range: range, reverse: reverse) {
            state = .playing
        }
    }

    /// 暂停动画，保留当前画面。
    public func pauseAnimation() {
        if engine.pauseAnimation() {
            state = .paused
        }
    }

    /// 停止动画。
    ///
    /// 是否清除画面取决于 `clearsAfterStop`。
    public func stopAnimation() {
        stopAnimation(cancelLoading: true)
    }

    /// 停止动画，并可选择是否取消正在进行的加载任务。
    ///
    /// - Parameter shouldCancelLoading: `true` 表示同时取消当前加载任务。
    public func stopAnimation(cancelLoading shouldCancelLoading: Bool) {
        let wasLoading = state.isLoading
        if shouldCancelLoading {
            cancelLoading(resetState: true)
        }
        engine.stopAnimation()
        state = wasLoading && shouldCancelLoading ? .idle : .stopped
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
    ///
    /// - Parameters:
    ///   - frame: 目标帧索引。
    ///   - andPlay: `true` 表示跳转后继续播放，`false` 表示跳转后暂停。
    public func step(toFrame frame: Int, andPlay: Bool) {
        if engine.step(toFrame: frame, andPlay: andPlay) {
            state = andPlay ? .playing : .paused
        }
    }

    /// 跳转到指定百分比位置。
    ///
    /// ```swift
    /// // 跳转到 50% 位置并暂停
    /// playerView.step(toPercentage: 0.5, andPlay: false)
    /// ```
    ///
    /// - Parameters:
    ///   - percentage: 目标播放进度。取值会被限制在 `0.0...1.0` 范围内。
    ///   - andPlay: `true` 表示跳转后继续播放，`false` 表示跳转后暂停。
    public func step(toPercentage percentage: CGFloat, andPlay: Bool) {
        if engine.step(toPercentage: percentage, andPlay: andPlay) {
            state = andPlay ? .playing : .paused
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
    func svgaPlaybackEngineDidFinishAnimation(_ player: SVGAPlaybackEngine) {
        state = .stopped
        emit(.finished)
    }

    func svgaPlaybackEngine(_ player: SVGAPlaybackEngine, didAnimateToFrame frame: Int) {
        emit(.frameChanged(frame))
    }

    func svgaPlaybackEngine(_ player: SVGAPlaybackEngine, didAnimateToPercentage percentage: CGFloat) {
        emit(.percentageChanged(percentage))
    }
}
