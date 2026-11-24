import AVKit
import Combine
import Foundation

@MainActor
final class PlaybackController: ObservableObject {
    let player = AVPlayer()
    @Published private(set) var playingItem: IPTVItem?
    @Published var playbackError: String?
    private var observation: AnyCancellable?

    func play(_ item: IPTVItem, url: URL) {
        player.pause()
        observation = nil
        playbackError = nil
        playingItem = item
        let media = AVPlayerItem(url: url)
        observation = media.publisher(for: \.status, options: [.initial, .new])
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak media] status in
                if status == .failed {
                    self?.playbackError = media?.error?.localizedDescription
                        ?? "Ce flux ne peut pas être lu avec les codecs natifs du Mac."
                }
            }
        player.replaceCurrentItem(with: media)
        player.play()
    }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        observation = nil
        playingItem = nil
        playbackError = nil
    }
}
