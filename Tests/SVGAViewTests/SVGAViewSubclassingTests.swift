import Testing
import UIKit
import SVGAView

@MainActor
private final class ExternalSVGAViewSubclass: SVGAView {
    private(set) var didMoveToSuperview = false
    private(set) var didLayoutSubviews = false
    private(set) var didAskIntrinsicContentSize = false
    private(set) var didAskSizeThatFits = false

    override func willMove(toSuperview newSuperview: UIView?) {
        didMoveToSuperview = true
        super.willMove(toSuperview: newSuperview)
    }

    override func layoutSubviews() {
        didLayoutSubviews = true
        super.layoutSubviews()
    }

    override var intrinsicContentSize: CGSize {
        didAskIntrinsicContentSize = true
        return super.intrinsicContentSize
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        didAskSizeThatFits = true
        return super.sizeThatFits(size)
    }
}

@MainActor
@Test
func svgaViewSupportsExternalSubclassingHooks() {
    let view = ExternalSVGAViewSubclass(frame: .zero)

    view.willMove(toSuperview: UIView())
    view.layoutSubviews()
    _ = view.intrinsicContentSize
    _ = view.sizeThatFits(CGSize(width: 100, height: 100))

    #expect(view.didMoveToSuperview)
    #expect(view.didLayoutSubviews)
    #expect(view.didAskIntrinsicContentSize)
    #expect(view.didAskSizeThatFits)
}

@Test
func svgaViewPreloadPublicAPIsAreUsableWithoutAView() async throws {
    guard let fileURL = Bundle.module.url(forResource: "banner", withExtension: "svga") else {
        throw NSError(domain: "SVGAViewSubclassingTests", code: 1)
    }
    let data = try Data(contentsOf: fileURL)
    let progressHandler: SVGAViewPreloadProgressHandler = { _ in }

    try await SVGAView.preload(.named("banner", bundle: .module))
    try await SVGAView.preload(named: "banner", in: .module)
    try await SVGAView.preload(fileURL: fileURL)
    try await SVGAView.preload(data: data, cacheKey: "public-preload-\(data.count)")

    _ = progressHandler
    _ = SVGAView.preload(remoteURL:progressHandler:)
    _ = SVGAView.preload(request:progressHandler:)
}
