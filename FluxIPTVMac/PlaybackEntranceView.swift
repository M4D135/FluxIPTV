import SwiftUI

/// A short native composition over the cached room. No timer or SceneKit
/// renderer survives the entrance; ContentView removes it before playback.
struct PlaybackEntranceView: View {
    let kind: IPTVMediaKind
    let expanded: Bool
    private var title: String {
        switch kind {
        case .movie: "La séance commence"
        case .series: "Votre épisode"
        case .live: "En direct"
        }
    }
    var body: some View {
        ZStack {
            Color.black.opacity(expanded ? 1 : 0)
            VStack(spacing: 14) {
                Image(systemName: kind == .live ? "tv" : "play.fill").font(.system(size: 34, weight: .light))
                Text(title).font(.title2.weight(.medium))
            }.foregroundStyle(.white).opacity(expanded ? 0 : 1)
                .scaleEffect(expanded ? 1.1 : 1)
        }.ignoresSafeArea().allowsHitTesting(false)
    }
}
