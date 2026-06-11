import AVFoundation

/// 管理单个 SVGA 音频片段播放状态的对象。
@MainActor
final class SVGAAudioLayer {
    /// 音频片段的时间和资源信息。
    let audioItem: SVGA.AudioEntity
    /// 播放音频数据的播放器。
    let audioPlayer: AVAudioPlayer?
    /// 一个布尔值，指示当前音频片段是否正在播放。
    var audioPlaying: Bool = false

    /// 创建音频 layer。
    ///
    /// - Parameters:
    ///   - audioItem: 音频片段的时间和资源信息。
    ///   - videoItem: 提供音频数据的动画实体。
    init(audioItem: SVGA.AudioEntity, videoItem: SVGA.VideoEntity) {
        self.audioItem = audioItem
        if let data = videoItem.audiosData[audioItem.audioKey] {
            audioPlayer = try? AVAudioPlayer(data: data, fileTypeHint: "mp3")
            audioPlayer?.prepareToPlay()
        } else {
            audioPlayer = nil
        }
    }
}
