import SwiftUI
import Combine
#if os(macOS)
import AppKit
#endif

@main
struct FluxIPTVApp: App {
    @StateObject private var library = IPTVLibrary()
    @StateObject private var playback = PlaybackController()

    init() {
        MediaThemePreferences.migrateLegacy(in: .standard)
        // What the 0.9.3 saved becomes the settings of the 0.9.4.
        LiveTVPreviewDelay.migrate()
        DeskBackBehavior.migrate()
        FluxDockZoom.migrate()
        // The graphics of this machine, with « Automatique ».
        FluxGraphics.applyAutomatic()
    }

    var body: some Scene {
        WindowGroup {
            #if os(tvOS)
            // The screens of a television stand under the controller of the
            // pointer, for the remote in the mode « Souris ».
            FluxRemoteHost {
                ContentView()
                    .environmentObject(library)
                    .environmentObject(playback)
                    .preferredColorScheme(.dark)
            }
            #else
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
            #endif
        }
        #if os(macOS)
        .defaultSize(width: 1440, height: 850)
        #endif
    }
}
