import UIKit

@MainActor
public class SVGAImageView: SVGAPlayer {

    @IBInspectable public var autoPlay: Bool = true

    @IBInspectable public var imageName: String? {
        didSet {
            guard let name = imageName else { return }
            Task {
                do {
                    let entity: SVGAVideoEntity
                    if name.hasPrefix("http://") || name.hasPrefix("https://"),
                       let url = URL(string: name) {
                        entity = try await SVGAParser.shared.parse(url: url)
                    } else {
                        entity = try await SVGAParser.shared.parse(named: name, in: nil)
                    }
                    self.videoItem = entity
                    if self.autoPlay {
                        self.startAnimation()
                    }
                } catch {
                    // ignore parse errors for IB convenience
                    print(error)
                }
            }
        }
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    public override init(frame: CGRect) {
        super.init(frame: frame)
    }
}
