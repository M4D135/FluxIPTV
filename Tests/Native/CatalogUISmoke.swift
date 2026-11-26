#if os(macOS) && FLUX_CATALOG_UI_TESTING
import AppKit
import AVFoundation
import CoreGraphics
import CoreText
import Darwin
import Foundation
import ImageIO
import QuartzCore
import SwiftUI
import UniformTypeIdentifiers
import WebKit

/// Measures actual production views without contributing accessibility/input.
struct CatalogDetailBoxFrameProbe: View {
    var body: some View { CatalogDetailControlFrameProbe(identifier: "media-detail-box") }
}

struct CatalogDetailControlFrameProbe: NSViewRepresentable {
    let identifier: String
    func makeNSView(context: Context) -> CatalogDetailControlProbeView {
        let view = CatalogDetailControlProbeView(frame: .zero)
        view.controlIdentifier = identifier
        view.setAccessibilityElement(false)
        return view
    }
    func updateNSView(_ view: CatalogDetailControlProbeView, context: Context) { view.controlIdentifier = identifier }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: CatalogDetailControlProbeView, context: Context) -> CGSize? {
        guard let width = proposal.width, let height = proposal.height else { return nil }
        return CGSize(width: width, height: height)
    }
}

final class CatalogDetailControlProbeView: NSView {
    var controlIdentifier = ""
    override var acceptsFirstResponder: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// A local run can keep its windows off every display and leave the user's
/// foreground application alone. Hosted runs keep the activated, visible window.
private final class CatalogCaptureWindow: NSWindow {
    var staysOffscreen = false
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        staysOffscreen ? frameRect : super.constrainFrameRect(frameRect, to: screen)
    }
}

private enum CatalogCaptureOptions {
    static let environment = ProcessInfo.processInfo.environment
    /// FLUX_CATALOG_UI_BACKGROUND=1: no activation, off-screen windows, and no
    /// scenario that needs the key window's native focus.
    static let background = environment["FLUX_CATALOG_UI_BACKGROUND"] == "1"
    /// FLUX_CATALOG_UI_ONLY=catalog-tv.png,movie-detail.png keeps those captures.
    static let only: Set<String>? = environment["FLUX_CATALOG_UI_ONLY"].map {
        Set($0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
    }
    /// FLUX_CATALOG_UI_SIZE=1728x1040 overrides the 1440 × 900 capture window.
    static let size: CGSize = {
        let parts = (environment["FLUX_CATALOG_UI_SIZE"] ?? "").lowercased().split(separator: "x").compactMap { Double($0) }
        guard parts.count == 2, parts[0] >= 860, parts[1] >= 540 else { return CGSize(width: 1440, height: 900) }
        return CGSize(width: parts[0], height: parts[1])
    }()
    static func window(title: String) -> CatalogCaptureWindow {
        let origin = background ? CGPoint(x: -12_000, y: -12_000) : CGPoint(x: 30, y: 30)
        let window = CatalogCaptureWindow(contentRect: CGRect(origin: origin, size: size),
                                          styleMask: [.titled], backing: .buffered, defer: false)
        window.staysOffscreen = background
        window.isReleasedWhenClosed = false
        window.title = title
        window.appearance = NSAppearance(named: .darkAqua)
        if background { window.setFrameOrigin(origin) }
        return window
    }
    static func show(_ window: NSWindow) {
        if background {
            let origin = window.frame.origin
            window.orderFrontRegardless()
            // Ordering a window in may bring it back to a display.
            window.setFrameOrigin(origin)
        } else { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    }
    /// FLUX_CATALOG_UI_GALLERY=1 adds the dock themes and positions.
    static let gallery = environment["FLUX_CATALOG_UI_GALLERY"] == "1"
    /// FLUX_CATALOG_UI_SCALE=1 stores point-sized images for a quick local look.
    static let nominalScale = environment["FLUX_CATALOG_UI_SCALE"] == "1"

    private typealias WindowImageFunction = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
    /// A process may read its own window from the WindowServer without the
    /// Screen Recording permission, including glass and materials that a view
    /// cache cannot draw. The entry point left the Swift SDK; resolve it at run
    /// time and fall back to the other capture paths when it is missing.
    @MainActor static func ownWindowImage(_ window: NSWindow) -> CGImage? {
        guard window.windowNumber > 0,
              let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage") else { return nil }
        let capture = unsafeBitCast(symbol, to: WindowImageFunction.self)
        let includingWindow: UInt32 = 1 << 3, ignoreFraming: UInt32 = 1
        let resolution: UInt32 = nominalScale ? 1 << 4 : 1 << 3
        return capture(.null, includingWindow, UInt32(window.windowNumber), ignoreFraming | resolution)?.takeRetainedValue()
    }
}

private enum CatalogUIFailure: Error, CustomStringConvertible {
    case assertion(String)
    var description: String { switch self { case .assertion(let message): return message } }
}

/// Captures the real ContentView in a native macOS window. The deterministic
/// fixture enters the production catalogue/cache; it does not replace any UI.
@main private struct CatalogUISmoke {
    private static let bundleID = "com.m4d135.FluxIPTV.CatalogUISmoke"

    @MainActor static func main() {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        Task { @MainActor in
            do {
                try require(Bundle.main.bundleIdentifier == bundleID,
                            "Run the harness from scripts/test-catalog-ui.sh.")
                try require(CommandLine.arguments.count == 2, "Pass the capture output directory.")
                let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
                try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
                configureDefaults()
                defer { UserDefaults.standard.removePersistentDomain(forName: bundleID) }
                print("System accessibility: reduced transparency=\(NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency), reduced motion=\(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion).")
                print("Native glass available=\(FluxAppearance.nativeAvailable). Hosted captures temporarily restore the normal system appearance before this process starts.")
                if ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true" {
                    try require(!NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency,
                                "The CI process still sees Reduce Transparency; native glass cannot be assessed.")
                }
                try await run(output: output)
                if CatalogCaptureOptions.background || CatalogCaptureOptions.only != nil {
                    print("PARTIAL: local captures only; run without FLUX_CATALOG_UI_BACKGROUND/ONLY for the complete check.")
                    exit(0)
                }
                print("PASS: real ContentView TV, DVD/VHS catalogue, twelve-season shelf and full-screen film/episode details rendered nonempty native captures.")
                print("Fixture artwork and catalogue only; no accounts, streams, remote images or video playback were used.")
                print("Review the PNGs for spacing, clipping and header appearance; this is not a pixel-perfect visual assertion.")
                exit(0)
            } catch {
                fputs("FAIL: \(error)\n", stderr)
                exit(1)
            }
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: CatalogCaptureOptions.gallery ? 300_000_000_000 : 150_000_000_000)
            fputs("FAIL: catalogue UI smoke exceeded its rendering deadline.\n", stderr)
            exit(1)
        }
        application.run()
    }

    @MainActor private static func configureDefaults(_ overrides: [String: Any] = [:]) {
        // This dedicated bundle has a separate preferences domain from FluxIPTV.
        UserDefaults.standard.removePersistentDomain(forName: bundleID)
        let base: [String: Any] = [
            FluxAppearance.glassKey: true,
            FluxAppearance.artworkKey: true,
            FluxAppearance.wallpaperKey: false,
            FluxAppearance.densityKey: "cinema",
            MediaThemePreferences.tvKey: VideoClubTheme.neo90.rawValue,
            MediaThemePreferences.cinemaKey: VideoClubTheme.neo90.rawValue,
            MediaThemePreferences.seriesKey: VideoClubTheme.neo90.rawValue,
            ClubInterfaceProfile.storageKey: ClubInterfaceProfile.neoVideoClub.rawValue,
            LiveTVPreviewDelay.automaticKey: false,
            LiveTVPreviewDelay.storageKey: LiveTVPreviewDelay.three.rawValue,
            TrailerPreviewDelay.automaticKey: false
        ]
        UserDefaults.standard.setVolatileDomain(base.merging(overrides) { _, scenario in scenario },
                                                forName: UserDefaults.argumentDomain)
    }

    /// One capture of the real ContentView. Gallery scenarios are further
    /// looks of the same screens and are captured on request only.
    private struct Scenario {
        let kind: IPTVMediaKind
        let filename: String
        var season: Int? = nil
        var detail = false
        var settings: PlaybackSettingsView.Page? = nil
        var favorites = false
        /// The home screen, with its bar in the middle of the window.
        var home = false
        /// The settings asked for during playback, above a stand-in picture.
        var playerSettings = false
        /// The zones of the screen, as Back shows them, with this one chosen.
        var zone: DeskZone? = nil
        /// The channel list of the player, above a stand-in picture.
        var zapList = false
        /// The commands of the player on a media that plays, drawn without any
        /// stream: "live", "film", "tracks" for the languages of a film, or
        /// "banner" for the bare picture of a channel under its banner.
        var player: String? = nil
        /// Keys of a remote sent to the screen, and the control that must
        /// hold the selection after them.
        var actions: [RemoteAction] = []
        var expectedFocus: String? = nil
        /// The channel those keys must leave on screen.
        var expectedPlaying: String? = nil
        /// The catalogue of a real subscription: tens of thousands of films,
        /// and so the pages of the catalogue on the line of the search.
        var manyFilms = false
        /// Titles relabelled the way playlists mark a language, with the
        /// language list open in the navigation column.
        var languages = false
        /// What the user keeps in the dock: "light" a few shortcuts, a
        /// video in progress and a folder; "full" two sections, a season,
        /// an episode and a recent as well; "many" more than the bar holds.
        var dock: String? = nil
        /// The lists of the selected title, with its place in the dock.
        var lists = false
        var defaults: [String: Any] = [:]
        var gallery = false
    }

    @MainActor private static func run(output: URL) async throws {
        for room in ["livingRoom-neo90", "cinema-neo90", "videoClub-neo90"] {
            guard let url = Bundle.main.url(forResource: room, withExtension: "jpg", subdirectory: "RoomBakes"),
                  let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let metadata = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = metadata[kCGImagePropertyPixelWidth] as? Int,
                  let height = metadata[kCGImagePropertyPixelHeight] as? Int else {
                throw CatalogUIFailure.assertion("Missing or unreadable production room resource: \(room).")
            }
            try require(width == 3840 && height == 2160, "Unexpected room resource dimensions for \(room).")
            print("Bundled room: \(room).jpg (\(width)×\(height)).")
        }
        let source = IPTVSource(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
                                name: "Catalogue local de démonstration", kind: .m3uFile)
        let artworkRoot = FileManager.default.temporaryDirectory.appendingPathComponent("FluxCatalogFixtures-\(UUID().uuidString)")
        let categories = ["Actualités", "Cinéma", "Culture et découverte", "Jeunesse", "Musique", "Sports"]
        var items: [IPTVItem] = []
        for index in 0..<24 {
            let number = index + 1
            let url = artworkRoot.appendingPathComponent("tv-\(index).png")
            let image = try fixtureArtwork(width: 240, height: 160, index: index, title: "TV \(number)", subtitle: "DÉMO LOCALE")
            cache(image, at: url)
            items.append(IPTVItem(id: "fixture-live-\(index)", sourceID: source.id,
                                  name: ["Horizon", "Panorama", "Grand écran", "Découverte", "Évasion", "Scène"][index % 6] + " \(number)",
                                  group: categories[index % categories.count], logoURL: url, kind: .live,
                                  directURL: nil, xtreamStreamID: nil, fileExtension: nil))
        }
        let titles = ["La dernière séance", "Au-delà des dunes", "Les lumières du port", "L’été suspendu", "Les passagers du ciel", "La ville endormie",
                      "Sur la route du nord", "Le jardin des possibles", "Un monde à part", "Les jours bleus", "La mémoire des vagues", "Le grand départ"]
        for index in titles.indices {
            let url = artworkRoot.appendingPathComponent("film-\(index).png")
            let year = index % 4 == 1 ? "1994" : "2011"
            let image = try fixtureArtwork(width: 360, height: 540, index: index + 2, title: titles[index].uppercased(), subtitle: "JAQUETTE LOCALE · \(year)")
            cache(image, at: url)
            items.append(IPTVItem(id: "fixture-movie-\(index)", sourceID: source.id, name: titles[index],
                                  group: index % 2 == 0 ? "Cinéma · Aventure" : "Cinéma · Classiques", logoURL: url,
                                  kind: .movie, directURL: nil, xtreamStreamID: nil, fileExtension: nil,
                                  details: IPTVDetails(synopsis: "Une équipe rejoint un observatoire isolé pour une dernière nuit sous les étoiles. Les souvenirs des voyageurs se croisent et font naître une nouvelle aventure. Le synopsis reste lisible à distance dans cette fiche plein écran.", year: year, duration: "1 h 48", genre: "Aventure · Drame")))
        }
        let seriesArtwork = artworkRoot.appendingPathComponent("series.png")
        cache(try fixtureArtwork(width: 360, height: 540, index: 7, title: "LES SAISONS", subtitle: "JAQUETTE LOCALE · 2014"), at: seriesArtwork)
        let collection = IPTVItem(id: "fixture-series", sourceID: source.id, name: "Les saisons", group: "Séries · Drame",
                                  logoURL: seriesArtwork, kind: .series, directURL: nil, xtreamStreamID: nil, fileExtension: nil,
                                  isSeriesCollection: true,
                                  details: IPTVDetails(synopsis: "Une description IPTV locale accompagne cette série de douze saisons. Chaque saison ouvre une fiche plein écran avec son boîtier et ses épisodes.", year: "2014", genre: "Drame"))
        items.append(collection)
        let seasons = (1...12).map { (number: Int) in
            IPTVSeason(number: number, episodes: (1...16).map { (episode: Int) in
                IPTVItem(id: "fixture-series-s\(number)-e\(episode)", sourceID: source.id,
                         name: "Épisode \(episode)", group: collection.group, logoURL: nil,
                         kind: .series, directURL: nil, xtreamStreamID: nil, fileExtension: nil,
                         details: IPTVDetails(synopsis: "Épisode de démonstration locale.", year: "2014", duration: "42 min"),
                         seasonNumber: number, episodeNumber: episode)
            })
        }
        let restoredEpisodeID = "fixture-series-s12-e15"
        try require(seasons.first(where: { $0.number == 12 })?.episodes.contains(where: { $0.id == restoredEpisodeID }) == true,
                    "The requested S12/E15 restoration fixture is missing or has an unexpected identifier.")
        let playback = PlaybackController()
        defer { playback.stop(); ArtworkLoader.cache.removeAllObjects() }
        var scenarios = [
            Scenario(kind: .live, filename: "home.png", home: true),
            Scenario(kind: .live, filename: "catalog-tv.png"),
            Scenario(kind: .movie, filename: "catalog-dvd-vhs.png"),
            Scenario(kind: .movie, filename: "catalog-films-pages.png", manyFilms: true),
            Scenario(kind: .movie, filename: "movie-detail.png", detail: true),
            Scenario(kind: .series, filename: "series-seasons.png"),
            Scenario(kind: .series, filename: "series-episode-detail.png", season: 12, detail: true),
            Scenario(kind: .live, filename: "favorites.png", favorites: true),
            Scenario(kind: .live, filename: "settings-sources.png", settings: .sources),
            Scenario(kind: .live, filename: "settings-dock.png", settings: .dock),
            Scenario(kind: .live, filename: "player-live.png", player: "live"),
            Scenario(kind: .movie, filename: "player-film.png", player: "film"),
            Scenario(kind: .movie, filename: "player-languages.png", player: "tracks"),
            Scenario(kind: .live, filename: "player-settings.png", playerSettings: true, player: "live"),
            Scenario(kind: .live, filename: "player-zapping.png", zapList: true),
            Scenario(kind: .live, filename: "player-banner.png", player: "banner"),
            Scenario(kind: .live, filename: "zones-tv.png", zone: .content),
            Scenario(kind: .movie, filename: "zones-dock.png", zone: .dock),
            // Back shows the compass of the zones: one arrow then jumps into
            // the dock under a list or to the controls above it, the arrows
            // walk the bar down to Back, and a second Back shows the home screen.
            Scenario(kind: .live, filename: "keys-dock.png", actions: [.back, .down],
                     expectedFocus: FluxDockItem.live.focusID, defaults: [DeskZone.backKey: true]),
            Scenario(kind: .movie, filename: "keys-top.png", actions: [.back, .up, .right],
                     expectedFocus: "reload", defaults: [DeskZone.backKey: true]),
            Scenario(kind: .movie, filename: "keys-bar.png", actions: [.back, .down, .left, .left],
                     expectedFocus: DeskZone.backID, defaults: [DeskZone.backKey: true]),
            Scenario(kind: .movie, filename: "keys-home.png", actions: [.back, .back],
                     expectedFocus: FluxDockItem.movie.focusID, defaults: [DeskZone.backKey: true]),
            // As the application starts: Back returns at once, here from
            // the films to the home screen, on the section that was left.
            Scenario(kind: .movie, filename: "keys-back.png", actions: [.back],
                     expectedFocus: FluxDockItem.movie.focusID),
            // The Home key of a remote, which a held Back stands for, shows
            // the home screen from wherever one is.
            Scenario(kind: .movie, filename: "keys-back-held.png", actions: [.home],
                     expectedFocus: FluxDockItem.movie.focusID),
            // The bar of the player: three keys to the right is Langues, OK
            // opens its panel on the audio in use, Down moves in it, and Back
            // closes it on the key that opened it.
            Scenario(kind: .movie, filename: "keys-player.png", player: "film",
                     actions: [.right, .right, .right, .select, .down, .back],
                     expectedFocus: PlayerTracks.buttonID),
            // The bare picture of a channel: Up and Down change channel under
            // its banner, the commands stay away and the picture keeps the keys.
            Scenario(kind: .live, filename: "keys-zap.png", player: "banner",
                     actions: [.up, .up, .down],
                     expectedFocus: "cinema-controls", expectedPlaying: "fixture-live-1")
        ]
        for theme in FluxDockTheme.allCases {
            scenarios.append(Scenario(kind: .live, filename: "dock-theme-\(theme.rawValue).png",
                                      defaults: [FluxDockTheme.storageKey: theme.rawValue, FluxDockPosition.storageKey: FluxDockPosition.bottom.rawValue,
                                                 "fluxiptv.fixture.dockPointer": 1], gallery: true))
        }
        scenarios.append(Scenario(kind: .movie, filename: "languages.png", languages: true, gallery: true))
        // The dock as a user fills it. A few shortcuts keep their full
        // size; the pointer on one of them shows its whole name.
        let folder = DockEntry.stack(listID: FavoritePresets.defaultID(for: .movie)).id
        scenarios.append(Scenario(kind: .movie, filename: "dock-shortcuts.png", dock: "light",
                                  defaults: ["fluxiptv.fixture.dockPointer": 7]))
        scenarios.append(Scenario(kind: .movie, filename: "dock-full.png", dock: "full"))
        scenarios.append(Scenario(kind: .movie, filename: "dock-folder.png", dock: "light",
                                  defaults: ["fluxiptv.fixture.dockFan": folder]))
        scenarios.append(Scenario(kind: .movie, filename: "dock-overflow.png", dock: "many",
                                  defaults: ["fluxiptv.fixture.dockFan": DockEntry.moreID], gallery: true))
        scenarios.append(Scenario(kind: .live, filename: "home-dock.png", home: true, dock: "full"))
        // On another edge the dock keeps the same things, and its folder
        // opens away from that edge.
        for position in [FluxDockPosition.top, .leading, .trailing] {
            scenarios.append(Scenario(kind: .movie, filename: "dock-folder-\(position.rawValue).png", dock: "light",
                                      defaults: [FluxDockPosition.storageKey: position.rawValue, "fluxiptv.fixture.dockFan": folder],
                                      gallery: true))
        }
        scenarios.append(Scenario(kind: .series, filename: "lists-dock.png", dock: "full", lists: true))
        // From the films, Down reaches the dock on Films; the arrows walk
        // it to the folder, OK opens it on its first title — the titles of
        // a list stand in the order of their names —, Up goes to the next
        // one, and Back closes it on its icon.
        scenarios.append(Scenario(kind: .movie, filename: "keys-folder.png",
                                  actions: [.down, .down, .down] + Array(repeating: .right, count: 9) + [.select, .up],
                                  expectedFocus: DockEntry.fanPrefix + "fixture-movie-0", dock: "light"))
        scenarios.append(Scenario(kind: .movie, filename: "keys-folder-back.png",
                                  actions: [.down, .down, .down] + Array(repeating: .right, count: 9) + [.select, .up, .back],
                                  expectedFocus: folder, dock: "light", gallery: true))
        scenarios.append(Scenario(kind: .live, filename: "zones-top.png", zone: .top, gallery: true))
        // The pointer on Films and on Séries: each brings its own room forward.
        scenarios.append(Scenario(kind: .live, filename: "home-films.png", home: true,
                                  defaults: ["fluxiptv.fixture.dockPointer": 1], gallery: true))
        scenarios.append(Scenario(kind: .live, filename: "home-series.png", home: true,
                                  defaults: ["fluxiptv.fixture.dockPointer": 2], gallery: true))
        let labelled = items.enumerated().map { offset, item in
            item.kind == .live ? item : IPTVItem(id: item.id, sourceID: item.sourceID,
                name: (offset.isMultiple(of: 3) ? "EN - " : "FR - ") + item.name, group: item.group, logoURL: item.logoURL,
                kind: item.kind, directURL: nil, xtreamStreamID: nil, fileExtension: nil,
                isSeriesCollection: item.isSeriesCollection, details: item.details)
        }
        for position in FluxDockPosition.allCases where position != FluxDockPosition.defaultValue {
            scenarios.append(Scenario(kind: .movie, filename: "dock-\(position.rawValue).png",
                                      defaults: [FluxDockPosition.storageKey: position.rawValue], gallery: true))
        }
        // Titles that carry their language and their year, categories by
        // language, and no jacket: only the first films have one.
        let manyFilms: [IPTVItem] = (titles.count..<58_093).map { (index: Int) in
            let groups = ["FR - LES DERNIERS AJOUTS", "FR - HORREUR", "FR - DRAME", "FR - ACTION", "FR - COMÉDIE", "FR - THRILLER",
                          "EN - ACTION", "EN - DRAMA", "EN - HORROR", "ES - ACCIÓN", "ES - DRAMA", "IT - AZIONE"]
            let group = groups[index % groups.count]
            return IPTVItem(id: "fixture-movie-\(index)", sourceID: source.id,
                            name: "\(group.prefix(2)) - \(titles[index % titles.count]) \(index / titles.count + 1) (\(1990 + index % 37))",
                            group: group, logoURL: nil, kind: .movie, directURL: nil, xtreamStreamID: nil, fileExtension: nil,
                            details: IPTVDetails(synopsis: "Un film local de démonstration, sans adresse de flux.", year: "\(1990 + index % 37)"))
        }
        var captureFailures: [String] = []
        for scenario in scenarios where CatalogCaptureOptions.only?.contains(scenario.filename) ?? (!scenario.gallery || CatalogCaptureOptions.gallery) {
            let kind = scenario.kind
            configureDefaults(scenario.defaults)
            let library = IPTVLibrary(catalogFixture: source,
                                      items: scenario.languages ? labelled : scenario.manyFilms ? items + manyFilms : items, kind: kind)
            try require(library.catalogResults.all.items.first != nil && !library.isLoading && !library.isFiltering, "Fixture catalogue was not installed synchronously.")
            if scenario.languages {
                try require(library.mediaLanguages.map(\.code) == ["en", "fr"], "The labelled fixture did not yield its two languages: \(library.mediaLanguages.map(\.code)).")
                library.countryCode = "fr"
                for _ in 0..<100 where library.isFiltering { try await Task.sleep(nanoseconds: 20_000_000) }
                try require(library.catalogResults.all.items.allSatisfy { $0.name.hasPrefix("FR - ") } && !library.catalogResults.all.items.isEmpty,
                            "The language filter did not keep the French titles only.")
            }
            if scenario.favorites {
                // A favourites list with content, through the production model.
                for item in library.catalogResults.all.items.prefix(5) { library.toggleFavorite(item) }
                library.selectedPresetID = FavoritePresets.defaultID(for: kind)
                for _ in 0..<100 where library.isFiltering { try await Task.sleep(nanoseconds: 20_000_000) }
                try require(library.catalogResults.all.items.count == 5, "The favourites fixture did not filter the catalogue.")
            }
            if let dock = scenario.dock {
                // What a user keeps in the dock, through the production model:
                // shortcuts in two sections, a film left unfinished, a
                // channel watched, and a list of favourites as a folder.
                func title(_ id: String) throws -> IPTVItem {
                    guard let item = library.catalogItem(id: id) else { throw CatalogUIFailure.assertion("Missing fixture title \(id).") }
                    return item
                }
                let series = try title("fixture-series")
                let general: Set<String> = [DockShelf.defaultSectionID]
                try require(library.assignDock(DockShortcut(item: try title("fixture-live-0")), to: general)
                            && library.assignDock(DockShortcut(item: try title("fixture-movie-1")), to: general),
                            "The dock fixture could not keep its first shortcuts.")
                if dock != "light" {
                    try require(library.assignDock(DockShortcut(item: series), to: [], creating: "Le soir"), "The dock fixture could not create its section.")
                    let evening: Set<String> = [library.dockShelf.sections[1].id]
                    try require(library.assignDock(DockShortcut(series: series, season: 3), to: evening)
                                && library.assignDock(DockShortcut(series: series, episode: seasons[11].episodes[14]), to: evening),
                                "The dock fixture could not keep a season and an episode.")
                } else {
                    try require(library.assignDock(DockShortcut(item: series), to: general), "The dock fixture could not keep its series.")
                }
                if dock == "many" {
                    for index in 6...11 {
                        try require(library.assignDock(DockShortcut(item: try title("fixture-movie-\(index)")), to: general),
                                    "The dock fixture could not keep its many shortcuts.")
                    }
                }
                let list = FavoritePresets.defaultID(for: .movie)
                for id in ["fixture-movie-0", "fixture-movie-2", "fixture-movie-3", "fixture-movie-5", "fixture-movie-8"] {
                    library.toggleFavorite(try title(id), in: list)
                }
                library.setDockStack(list, shown: true)
                if dock != "light" { library.visitDock(DockShortcut(item: try title("fixture-live-5"))) }
                library.visitDock(DockShortcut(item: try title("fixture-movie-4")))
                playback.recordFixtureProgress(id: "fixture-movie-4", seconds: 2_520, duration: 6_480)
                try require(library.dockShelf.contains("fixture-live-0") && library.dockShelf.showsStack(list)
                            && library.dockShelf.recents.first?.id == "fixture-movie-4", "The dock fixture is not what the scenario expects.")
            }
            defer { playback.clearFixtureProgress() }
            let selected = library.catalogResults.all.items.first
            if let mode = scenario.player, let item = selected {
                // The published state of a media that plays, and nothing else:
                // no engine starts and no connection opens.
                if mode == "live" || mode == "banner" {
                    playback.showFixture(item, playing: true,
                                         audio: [PlaybackTrack(id: "a1", title: "Français", selected: true),
                                                 PlaybackTrack(id: "a2", title: "Audiodescription", selected: false)])
                } else {
                    playback.showFixture(item, playing: true, fraction: 0.357, elapsed: "42:10", duration: "1:58:00",
                                         audio: [PlaybackTrack(id: "a1", title: "Français", selected: true),
                                                 PlaybackTrack(id: "a2", title: "Anglais (version originale)", selected: false),
                                                 PlaybackTrack(id: "a3", title: "Espagnol", selected: false)],
                                         subtitles: [PlaybackTrack(id: "s1", title: "Français", selected: false),
                                                     PlaybackTrack(id: "s2", title: "Français (malentendants)", selected: false),
                                                     PlaybackTrack(id: "s3", title: "Anglais", selected: false)])
                }
            }
            defer { if scenario.player != nil { playback.stop() } }
            var observedFocus: String?
            let root = ContentView(fixtureSelection: selected, fixtureSeasons: kind == .series ? seasons : [],
                                   fixtureOpenSeason: scenario.season, fixtureEpisodeID: scenario.season == nil ? nil : restoredEpisodeID, fixtureOpenItem: scenario.detail,
                                   fixtureSearchObservation: scenario.expectedFocus == nil ? nil : { observedFocus = $0.focusID },
                                   fixtureOpenCountries: scenario.languages,
                                   fixtureSettingsPage: scenario.settings, fixtureFavorites: scenario.favorites,
                                   fixtureHome: scenario.home, fixturePlayerSettings: scenario.playerSettings,
                                   fixtureZone: scenario.zone, fixtureActions: scenario.actions,
                                   fixtureZapList: scenario.zapList, fixtureLists: scenario.lists,
                                   fixturePlayer: scenario.player != nil, fixtureHoldsControls: scenario.player != nil,
                                   fixtureTracksPanel: scenario.player == "tracks",
                                   fixtureBanner: scenario.player == "banner")
                .environmentObject(library).environmentObject(playback)
                .preferredColorScheme(.dark)
                .environment(\.scenePhase, .active)
            let host = NSHostingView(rootView: root)
            let size = CatalogCaptureOptions.size
            let window = CatalogCaptureOptions.window(title: "FluxIPTV — \(scenario.filename.replacingOccurrences(of: ".png", with: ""))")
            window.contentView = host
            host.frame = CGRect(origin: .zero, size: size)
            CatalogCaptureOptions.show(window)
            // Let actual SwiftUI tasks fill artwork and the bundled room image,
            // then let the native compositor settle before caching the view.
            try await Task.sleep(nanoseconds: 1_500_000_000)
            if scenario.season != nil {try await Task.sleep(nanoseconds: 1_500_000_000)}
            host.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            CATransaction.flush()
            try await Task.sleep(nanoseconds: 300_000_000)
            try require((playback.playingItem == nil || scenario.player != nil) && playback.player.currentItem == nil,
                        "A visual capture unexpectedly started main playback.")
            let filename = scenario.filename
            if let expected = scenario.expectedFocus {
                try require(observedFocus == expected,
                            "\(filename): the keys \(scenario.actions) left the selection on \(observedFocus ?? "nothing"), not on \(expected).")
                print("Keys \(scenario.actions.map { "\($0)" }.joined(separator: " ")) → \(expected).")
            }
            if let expected = scenario.expectedPlaying {
                try require(playback.playingItem?.id == expected && playback.isPlaying,
                            "\(filename): the keys \(scenario.actions) left \(playback.playingItem?.id ?? "nothing") on screen, not \(expected).")
            }
            do {
                try await capture(host, window: window, to: output.appendingPathComponent(filename))
                if scenario.detail {
                    try verifyDetailBox(in: host, reportURL: output.appendingPathComponent(filename.replacingOccurrences(of: ".png", with: "-box.json")))
                }
            }
            catch { captureFailures.append("\(filename): \(error)") }
            window.orderOut(nil)
            window.contentView = nil
            window.close()
            await Task.yield()
        }
        try require(captureFailures.isEmpty, captureFailures.joined(separator: "\n"))
        if CatalogCaptureOptions.background || CatalogCaptureOptions.only != nil {
            print("Local capture run: the native search-focus scenarios need the key window and were not exercised.")
            return
        }
        try await verifySearchSubmission(source: source, items: items, playback: playback)
    }

    /// Exercise the production submit handler against the real 150 ms filter,
    /// including an immediate second OK while old matches are still visible.
    @MainActor private static func verifySearchSubmission(source: IPTVSource, items: [IPTVItem], playback: PlaybackController) async throws {
        let scenarios: [(query: String, expected: String?, replacement: String?)] = [
            ("dunes", "fixture-movie-1", nil),
            ("no-matching-flux-title", "tab-movie", nil),
            ("dunes", nil, "port")
        ]
        for scenario in scenarios {
            let library = IPTVLibrary(catalogFixture: source, items: items, kind: .movie)
            let original = library.catalogResults.all.items.first
            try require(original?.id != "fixture-movie-1", "The search fixture needs a different old first item.")
            var observations: [CatalogSearchFocusSnapshot] = []
            let root = ContentView(fixtureSelection: original, fixtureSearchSubmission: scenario.query,
                                   fixtureSearchObservation: { observations.append($0) })
                .environmentObject(library).environmentObject(playback)
                .preferredColorScheme(.dark).environment(\.scenePhase, .active)
            let host = NSHostingView(rootView: root)
            let window = NSWindow(contentRect: CGRect(x: 30, y: 30, width: 1440, height: 900),
                                  styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            window.makeKeyAndOrderFront(nil)
            defer { window.orderOut(nil); window.close() }

            for _ in 0..<100 {
                if observations.contains(where: { $0.query == scenario.query && $0.filtering && $0.pending }) { break }
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            try require(observations.contains(where: { $0.query == scenario.query && $0.filtering && $0.pending }),
                        "Search submission did not defer focus while the real filter was running.")
            if let replacement = scenario.replacement { library.search = replacement }
            let finalQuery = scenario.replacement ?? scenario.query
            var stableSamples = 0
            for _ in 0..<160 {
                if let last = observations.last, last.query == finalQuery, !last.filtering, !last.pending,
                   scenario.expected == nil || (last.focusID == scenario.expected && last.nativeFocusID == scenario.expected) {
                    stableSamples += 1
                    if stableSamples >= 4 { break }
                } else { stableSamples = 0 }
                try await Task.sleep(nanoseconds: 25_000_000)
            }
            guard let final = observations.last else { throw CatalogUIFailure.assertion("No search focus observation arrived.") }
            let trace = observations.map {
                "query=\($0.query), filtering=\($0.filtering), pending=\($0.pending), focus=\($0.focusID ?? "nil"), native=\($0.nativeFocusID ?? "nil")"
            }.joined(separator: " | ")
            print("SEARCH_FOCUS_TRACE: \(trace)")
            try require(final.query == finalQuery && !final.filtering && !final.pending && stableSamples >= 4,
                        "Search focus did not settle or cancel within the bounded deadline.")
            if let expected = scenario.expected {
                try require(final.focusID == expected && final.nativeFocusID == expected,
                            "Submit focused logical=\(final.focusID ?? "nil"), native=\(final.nativeFocusID ?? "nil") instead of the current result \(expected).")
            } else {
                try require(library.catalogResults.all.items.map(\.id) == ["fixture-movie-2"],
                            "The replacement query did not supply the current catalogue.")
                try require(!observations.contains(where: { $0.query == finalQuery && $0.focusID == "fixture-movie-1" }),
                            "A superseded search stole focus after its query changed.")
            }
            try require(observations.allSatisfy { $0.heldItemID == nil } && library.selectedItemID == nil && playback.playingItem == nil,
                        "The early OK opened an old search result while filtering.")
            print("PASS: debounced search '\(scenario.query)'\(scenario.replacement.map { " → '\($0)'" } ?? "") deferred/cancelled focus and rejected stale OK.")
        }
    }

    @MainActor private static func verifyDetailBox(in host: NSView, reportURL: URL) throws {
        func views(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(views) }
        func playerLayers(_ layer: CALayer?) -> Int {
            guard let layer else { return 0 }
            return (layer is AVPlayerLayer ? 1 : 0) + (layer.sublayers ?? []).reduce(0) { $0 + playerLayers($1) }
        }
        let nativeViews = views(host)
        let probes = nativeViews.compactMap { $0 as? CatalogDetailControlProbeView }
            .filter { !$0.isHiddenOrHasHiddenAncestor && $0.window === host.window }
        let boxes = probes.filter { $0.controlIdentifier == "media-detail-box" }
        let frame = boxes.count == 1 ? boxes[0].convert(boxes[0].bounds, to: host) : CGRect.zero
        let visible = boxes.count == 1 ? boxes[0].convert(boxes[0].visibleRect, to: host) : CGRect.zero
        let large = frame.width >= 200 && frame.height >= 280 && frame.width < frame.height
        let fullyVisible = !frame.isEmpty && visible.insetBy(dx: -1, dy: -1).contains(frame) && host.bounds.insetBy(dx: -1, dy: -1).contains(frame)
        let playControls = probes.filter { $0.controlIdentifier == "media-detail-play" }
        let playFrame = playControls.count == 1 ? playControls[0].convert(playControls[0].bounds, to: host) : CGRect.zero
        let playViewport = playControls.count == 1 ? playControls[0].convert(playControls[0].visibleRect, to: host) : CGRect.zero
        let playLarge = playFrame.width >= 100 && playFrame.height >= 40
        let playVisible = !playFrame.isEmpty && playViewport.insetBy(dx: -1, dy: -1).contains(playFrame) && host.bounds.insetBy(dx: -1, dy: -1).contains(playFrame)
        let forbidden = probes.map(\.controlIdentifier).filter { $0 == "media-detail-trailer" || $0 == "media-detail-mute" }.sorted()
        let players = playerLayers(host.layer), webViews = nativeViews.filter { $0 is WKWebView }.count
        let report: [String: Any] = [
            "detailBoxTested": true, "detailBoxProbeCount": boxes.count,
            "detailBoxFrame": [frame.minX, frame.minY, frame.width, frame.height],
            "detailBoxLargeEnough": large, "detailBoxFullyVisible": fullyVisible,
            "detailControlObservationMethod": "Noninteractive AppKit probes behind the actual box and controls; no accessibility-tree assertion.",
            "detailPlayControlProbeCount": playControls.count,
            "detailPlayControlFrame": [playFrame.minX, playFrame.minY, playFrame.width, playFrame.height],
            "detailPlayControlLargeEnough": playLarge, "detailPlayControlFullyVisible": playVisible,
            "detailTrailerControlIDs": forbidden, "detailPlayerLayerCount": players, "detailWebViewCount": webViews
        ]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: reportURL, options: .atomic)
        try require(boxes.count == 1 && large && fullyVisible && playControls.count == 1 && playLarge && playVisible && forbidden.isEmpty && players == 0 && webViews == 0,
                    "The detail must contain one large visible box and Play, without a trailer control, web player or video layer. See \(reportURL.lastPathComponent).")
        print("PASS: \(reportURL.lastPathComponent): large visible native box, Play present, no trailer control/web player/video layer.")
    }

    private static func cache(_ image: CGImage, at url: URL) {
        ArtworkLoader.cache.setObject(FluxBitmap(image), forKey: url.absoluteString as NSString,
                                     cost: image.bytesPerRow * image.height)
    }

    @MainActor private static func capture(_ view: NSView, window: NSWindow, to url: URL) async throws {
        // Keep the view-cache diagnostic even if a compositor-dependent effect
        // cannot draw into this bitmap. Assertions must never discard evidence.
        var cachedImage: CGImage?
        var cachedPNG: Data?
        if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: bitmap)
            cachedImage = bitmap.cgImage
            cachedPNG = bitmap.representation(using: .png, properties: [:])
            if let cachedPNG {
                let cacheURL = url.deletingLastPathComponent().appendingPathComponent(url.deletingPathExtension().lastPathComponent + "-cache.png")
                try cachedPNG.write(to: cacheURL, options: .atomic)
                print("View-cache diagnostic: \(cacheURL.path)")
            }
        }

        try? FileManager.default.removeItem(at: url)
        let canCaptureWindow = CGPreflightScreenCaptureAccess()
        print("Existing WindowServer capture permission: \(canCaptureWindow)")
        var image: CGImage?
        var method = "NSView cacheDisplay"
        // A busy machine may not have composited a window that was just
        // ordered in: ask again before falling back to a lesser capture.
        var ownImage = CatalogCaptureOptions.ownWindowImage(window)
        for _ in 0..<4 where ownImage == nil {
            try await Task.sleep(nanoseconds: 500_000_000)
            window.displayIfNeeded()
            CATransaction.flush()
            ownImage = CatalogCaptureOptions.ownWindowImage(window)
        }
        if let own = ownImage,
           let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) {
            CGImageDestinationAddImage(destination, own, nil)
            if CGImageDestinationFinalize(destination) {
                image = own
                method = "own-window WindowServer image"
            }
        }
        if image != nil {
            // The composited window is the reference; nothing else to try.
        } else if canCaptureWindow, FileManager.default.isExecutableFile(atPath: "/usr/sbin/screencapture") {
            let status = try await captureWindow(window.windowNumber, to: url)
            if status == 0, let source = CGImageSourceCreateWithURL(url as CFURL, nil) {
                image = CGImageSourceCreateImageAtIndex(source, 0, nil)
                method = "WindowServer screencapture"
            } else { print("WindowServer capture returned status \(status); retaining the view-cache diagnostic.") }
        } else {
            // Never request permission, alter TCC, or capture another window.
            print("WindowServer capture is unavailable with existing permissions; retaining the view-cache diagnostic.")
        }
        if image == nil, let cachedImage, let cachedPNG {
            image = cachedImage
            try cachedPNG.write(to: url, options: .atomic)
        }
        guard let image else { throw CatalogUIFailure.assertion("Native ContentView capture is missing.") }
        print("Capture: \(url.path) (\(image.width)×\(image.height), \(method))")
        try require(image.width >= Int(CatalogCaptureOptions.size.width) - 40 && image.height >= Int(CatalogCaptureOptions.size.height) - 50, "Native ContentView capture is too small.")
        print("Capture window frame: \(window.frame)")
        let headerHasDetail = hasDetail(image, region: CGRect(x: 0, y: 0, width: image.width, height: max(100, image.height / 6)))
        let catalogueHasDetail = hasDetail(image, region: CGRect(x: 0, y: image.height / 3, width: image.width, height: image.height / 2))
        print("Capture detail: header=\(headerHasDetail), catalogue=\(catalogueHasDetail). PNG retained regardless of result.")
        try require(headerHasDetail, "Native header capture is empty or uniform.")
        try require(catalogueHasDetail, "Native catalogue capture is empty or uniform.")
    }

    @MainActor private static func captureWindow(_ windowNumber: Int, to url: URL) async throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", "-o", "-l", String(windowNumber), url.path]
        let timeout = Task { @MainActor in
            do { try await Task.sleep(nanoseconds: 5_000_000_000) } catch { return }
            if process.isRunning { process.terminate() }
        }
        defer { timeout.cancel() }
        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { completed in continuation.resume(returning: completed.terminationStatus) }
            do { try process.run() } catch { continuation.resume(throwing: error) }
        }
    }

    private static func hasDetail(_ image: CGImage, region: CGRect) -> Bool {
        guard let crop = image.cropping(to: region),
              let context = CGContext(data: nil, width: 64, height: 24, bitsPerComponent: 8, bytesPerRow: 64 * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let bytes = context.data?.assumingMemoryBound(to: UInt8.self) else { return false }
        context.draw(crop, in: CGRect(x: 0, y: 0, width: 64, height: 24))
        var lowest = 255, highest = 0, visible = 0
        for index in 0..<(64 * 24) where bytes[index * 4 + 3] > 20 {
            visible += 1
            let luminance = (3 * Int(bytes[index * 4]) + 6 * Int(bytes[index * 4 + 1]) + Int(bytes[index * 4 + 2])) / 10
            lowest = min(lowest, luminance)
            highest = max(highest, luminance)
        }
        return visible > 200 && highest - lowest > 30
    }

    private static func fixtureArtwork(width: Int, height: Int, index: Int, title: String, subtitle: String) throws -> CGImage {
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw CatalogUIFailure.assertion("Unable to create deterministic local artwork.")
        }
        let colors: [(CGFloat, CGFloat, CGFloat)] = [(0.15, 0.47, 0.68), (0.77, 0.25, 0.16), (0.25, 0.50, 0.32), (0.48, 0.29, 0.62), (0.67, 0.48, 0.12), (0.13, 0.53, 0.52)]
        let color = colors[index % colors.count]
        context.setFillColor(CGColor(red: color.0 * 0.28, green: color.1 * 0.28, blue: color.2 * 0.28, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(red: color.0, green: color.1, blue: color.2, alpha: 1))
        let w = CGFloat(width), h = CGFloat(height)
        context.fillEllipse(in: CGRect(x: -w * 0.18, y: h * 0.27, width: w * 1.3, height: w * 1.3))
        context.setFillColor(CGColor(gray: 0, alpha: 0.45))
        context.fill(CGRect(x: 0, y: 0, width: w, height: h * 0.32))
        let words = title.split(separator: " ")
        let split = words.count > 3 ? words.count / 2 : words.count
        let lines = split < words.count ? [words[..<split].joined(separator: " "), words[split...].joined(separator: " ")] : [title]
        for (line, text) in lines.enumerated() {
            drawText(text, size: min(w * 0.075, w * 1.35 / CGFloat(max(1, text.count))),
                     at: CGPoint(x: w / 2, y: h * 0.18 - CGFloat(line) * h * 0.045), in: context)
        }
        drawText(subtitle, size: w * 0.027, at: CGPoint(x: w / 2, y: h * 0.055), in: context)
        guard let image = context.makeImage() else { throw CatalogUIFailure.assertion("Unable to finish fixture artwork.") }
        return image
    }

    private static func drawText(_ text: String, size: CGFloat, at point: CGPoint, in context: CGContext) {
        let font = CTFontCreateWithName("HelveticaNeue-Bold" as CFString, size, nil)
        let value = NSAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 1, alpha: 1)
        ])
        let line = CTLineCreateWithAttributedString(value)
        context.textPosition = CGPoint(x: point.x - CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)) / 2, y: point.y)
        CTLineDraw(line, context)
    }

    private static func require(_ value: Bool, _ message: String) throws {
        if !value { throw CatalogUIFailure.assertion(message) }
    }
}
#endif
