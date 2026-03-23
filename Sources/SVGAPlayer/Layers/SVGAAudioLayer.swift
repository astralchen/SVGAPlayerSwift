import AVFoundation

final class SVGAAudioLayer {
    let audioItem: SVGAAudioEntity
    let audioPlayer: AVAudioPlayer?
    var audioPlaying: Bool = false

    init(audioItem: SVGAAudioEntity, videoItem: SVGAVideoEntity) {
        self.audioItem = audioItem
        if let data = videoItem.audiosData[audioItem.audioKey] {
            audioPlayer = try? AVAudioPlayer(data: data, fileTypeHint: "mp3")
            audioPlayer?.prepareToPlay()
        } else {
            audioPlayer = nil
        }
    }
}
