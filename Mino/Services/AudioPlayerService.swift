import AVFoundation

class AudioPlayerService {
    static let shared = AudioPlayerService()
    private var player: AVPlayer?

    func play(url urlString: String) {
        let url: URL
        if urlString.hasPrefix("/") {
            url = URL(fileURLWithPath: urlString)
        } else if let parsed = URL(string: urlString) {
            url = parsed
        } else {
            return
        }
        player = AVPlayer(url: url)
        player?.play()
    }

    func stop() {
        player?.pause()
        player = nil
    }
}
