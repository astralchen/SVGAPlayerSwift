import Foundation

extension SVGA {
    /// SVGA 动画中的音频片段。
    struct AudioEntity: Sendable {
        /// 音频数据资源 key。
        let audioKey: String
        /// 开始播放的帧索引。
        let startFrame: Int
        /// 停止播放的帧索引。
        let endFrame: Int
        /// 音频片段的起始时间，单位为毫秒。
        let startTime: Int

        /// 使用 SVGA 2.x Proto audio 创建音频数据。
        ///
        /// - Parameter protoObject: 反序列化后的 Proto audio 对象。
        init(protoObject: SVGAProto.Audio) {
            audioKey = protoObject.audioKey
            startFrame = Int(protoObject.startFrame)
            endFrame = Int(protoObject.endFrame)
            startTime = Int(protoObject.startTime)
        }
    }
}
