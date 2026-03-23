import Foundation

public struct SVGAAudioEntity: Sendable {
    public let audioKey: String
    public let startFrame: Int
    public let endFrame: Int
    public let startTime: Int

    init(protoObject: Svga_AudioEntity) {
        audioKey = protoObject.audioKey
        startFrame = Int(protoObject.startFrame)
        endFrame = Int(protoObject.endFrame)
        startTime = Int(protoObject.startTime)
    }
}
