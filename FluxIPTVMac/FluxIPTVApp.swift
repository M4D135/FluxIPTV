import SwiftUI

@main
struct FluxIPTVApp: App {
    @StateObject private var library = IPTVLibrary()
    @StateObject private var playback = PlaybackController()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(library)
                .environmentObject(playback)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 1280, height: 780)
    }
}
