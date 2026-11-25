import SwiftUI
import Combine
#if os(macOS)
import AppKit
#endif

@main
struct FluxIPTVApp: App {
    @StateObject private var library = IPTVLibrary()
    @StateObject private var playback = PlaybackController()

    init() { MediaThemePreferences.migrateLegacy(in: .standard) }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(library)
                .environmentObject(playback)
                .preferredColorScheme(.dark)
                #if os(macOS)
                .onReceive(NotificationCenter.default.publisher(for:NSApplication.willTerminateNotification)) { _ in
                    library.flushBrowsingPreferences()
                    playback.stop()
                }
                #endif
        }
        #if os(macOS)
        .defaultSize(width: 1440, height: 850)
        #endif
    }
}
