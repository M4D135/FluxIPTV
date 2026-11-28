#if os(tvOS) && FLUX_CATALOG_UI_TESTING
import AVFoundation
import CoreGraphics
import CoreText
import Darwin
import Foundation
import SceneKit
import SwiftUI
import UIKit

private enum TVCatalogUIFailure: Error, CustomStringConvertible {
    case assertion(String)
    var description: String { switch self { case .assertion(let message): return message } }
}

/// Installed behind the actual production control only in this fixture build.
/// Its bounds are laid out by SwiftUI, then read back from UIKit in the same
/// window as the real focused item. It never takes focus or handles input.
struct TVCatalogControlFrameProbe: UIViewRepresentable {
    let identifier: String

    func makeUIView(context: Context) -> TVCatalogControlProbeView {
        let view = TVCatalogControlProbeView()
        view.controlIdentifier = identifier
        view.backgroundColor = .clear
        view.isOpaque = false
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        view.accessibilityElementsHidden = true
        return view
    }

    func updateUIView(_ view: TVCatalogControlProbeView, context: Context) {
        view.controlIdentifier = identifier
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: TVCatalogControlProbeView, context: Context) -> CGSize? {
        guard let width = proposal.width, let height = proposal.height else { return nil }
        return CGSize(width: width, height: height)
    }
}

final class TVCatalogControlProbeView: UIView {
    var controlIdentifier = ""
    override var canBecomeFocused: Bool { false }
}

/// What the screen has rebuilt since it started, as the value of an element
/// that a remote flow reads before and after a move. It is drawn outside
/// the screen it counts, and refreshes by itself.
private struct TVProbeReadout: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.2)) { _ in
            Color.clear.frame(width: 1, height: 1).allowsHitTesting(false)
                .accessibilityElement().accessibilityLabel("Compteurs")
                .accessibilityIdentifier("flux-probe")
                .accessibilityValue(FluxProbe.counts.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "))
        }
    }
}

@MainActor private final class TVCatalogSearchObservations: ObservableObject {
    var snapshots: [CatalogSearchFocusSnapshot] = []
}

/// The script substitutes this entry point in a temporary repository copy. It
/// hosts the real application views in a booted tvOS Simulator, including the
/// system focus engine. It never loads saved accounts or remote media.
@main @MainActor private struct TVCatalogUISmoke: App {
    @StateObject private var library: IPTVLibrary
    @StateObject private var playback: PlaybackController
    @StateObject private var searchObservations = TVCatalogSearchObservations()
    private let fixture: TVCatalogFixture
    private let restoredDefaultsSuite: String?

    init() {
        do {
            try TVCatalogCapture.require(Bundle.main.bundleIdentifier == TVCatalogCapture.bundleID,
                                         "Run this fixture through scripts/test-tvos-catalog-ui.sh.")
            TVCatalogCapture.configureDefaults()
            let fixture = try TVCatalogFixture.make()
            let library: IPTVLibrary
            var restoredDefaultsSuite: String?
            if fixture.scenario == "welcome" || fixture.scenario == "add-source" {
                library = IPTVLibrary(emptyCatalogFixture: .live)
                try TVCatalogCapture.require(library.sources.isEmpty, "The welcome fixture unexpectedly contains a source.")
            } else if fixture.scenario == "live-error" {
                library = IPTVLibrary(unavailableCatalogFixture: fixture.source, kind: .live)
                try TVCatalogCapture.require(!library.sources.isEmpty && !library.isLoading &&
                                             !library.browsingCatalogReady && library.credentialIssue != nil,
                                             "The failed-source fixture must have no loaded catalogue and require reconnection.")
            } else if fixture.usesPersistedSelection {
                let restored = try TVCatalogCapture.makeRestoredBrowsingLibrary(fixture: fixture)
                library = restored.library
                restoredDefaultsSuite = restored.suiteName
                // Saved country/search filters run asynchronously. Restore
                // their selection through production after results mount,
                // rather than seeding focus before a channel exists.
                try TVCatalogCapture.require(!library.isLoading &&
                                             library.catalogItem(id: fixture.selection?.id) != nil,
                                             "The restored library did not install its complete local catalogue.")
            } else {
                library = IPTVLibrary(catalogFixture: fixture.source, items: fixture.items, kind: fixture.kind)
                try TVCatalogCapture.require(!library.isLoading && !library.isFiltering &&
                                             library.catalogItem(id: fixture.selection?.id) != nil,
                                             "The local catalogue was not installed synchronously.")
                // Use the actual library filter, not a prefiltered fixture.
                // Its asynchronous result is checked before capture readiness.
                if let countryCode = fixture.countryCode { library.countryCode = countryCode }
                if fixture.fillsDock {
                    try TVCatalogCapture.fillDock(of: library, source: fixture.source)
                    if let series = library.catalogItem(id: "fixture-series") {
                        library.cacheFixtureSeasons(fixture.dockSeasons, for: series)
                    }
                }
            }
            self.fixture = fixture
            self.restoredDefaultsSuite = restoredDefaultsSuite
            _library = StateObject(wrappedValue: library)
            let playback = PlaybackController()
            // The film that the dock offers to go on with.
            if fixture.fillsDock {
                playback.recordFixtureProgress(id: "fixture-movie-2", seconds: 2_520, duration: 6_480)
                // The shortcut of a channel plays it: shown as playing, without a connection.
                playback.simulateFixturePlayback()
            }
            // The click of the pointer watches the channel under it, as above.
            if fixture.scenario == "pointer" || fixture.scenario == "pointer-list" { playback.simulateFixturePlayback() }
            if fixture.showsPlayer, let item = fixture.selection {
                // A media that plays, without any connection: the commands
                // hide and the remote behaves as during a stream.
                if fixture.playsFilm {
                    playback.showFixture(item, playing: true, fraction: 0.357, elapsed: "42:10", duration: "1:58:00",
                                         audio: [PlaybackTrack(id: "a1", title: "Français", selected: true),
                                                 PlaybackTrack(id: "a2", title: "Anglais (version originale)", selected: false),
                                                 PlaybackTrack(id: "a3", title: "Espagnol", selected: false)],
                                         subtitles: [PlaybackTrack(id: "s1", title: "Français", selected: false),
                                                     PlaybackTrack(id: "s2", title: "Français (malentendants)", selected: false),
                                                     PlaybackTrack(id: "s3", title: "Anglais", selected: false)])
                    // FLUX_UI_TICK=1: the film goes on, as a stream tells it.
                    if ProcessInfo.processInfo.environment["FLUX_UI_TICK"] == "1" { playback.tickFixture() }
                } else {
                    // "player-banner-opening": the channel has just changed
                    // and its stream is still opening.
                    let opening = fixture.scenario == "player-banner-opening"
                    playback.showFixture(item, playing: !opening, opening: opening,
                                         audio: [PlaybackTrack(id: "a1", title: "Français", selected: true),
                                                 PlaybackTrack(id: "a2", title: "Audiodescription", selected: false)])
                    // The simulated playback changes channel as an engine
                    // would. One channel cannot be shown: it takes the
                    // ordinary path, which fails for a catalogue without
                    // addresses and raises its message.
                    playback.fixtureUnplayable = ["fixture-live-59"]
                    // And one is a dead channel: its stream opens, then fails.
                    playback.fixtureFailing = ["fixture-live-55"]
                }
            }
            _playback = StateObject(wrappedValue: playback)
        } catch {
            TVCatalogCapture.fail(error)
        }
    }

    var body: some Scene {
        WindowGroup {
            // As the application: the screens stand under the controller of
            // the pointer of the remote.
            FluxRemoteHost {
            ContentView(fixtureSelection: fixture.usesPersistedSelection ? nil : fixture.selection, fixtureSeasons: fixture.seasons,
                        fixtureOpenSeason: fixture.openSeason, fixtureEpisodeID: fixture.episodeID,
                        fixtureOpenItem: fixture.scenario == "movie",
                        fixtureSearchSubmission: fixture.searchQuery,
                        fixtureSearchObservation: { searchObservations.snapshots.append($0) },
                        fixtureOpenCountries: fixture.opensCountryPicker,
                        fixtureRestoreBrowsing: fixture.usesPersistedSelection || fixture.scenario == "live-error",
                        fixtureSettingsPage: fixture.settingsPage,
                        fixtureHome: fixture.scenario == "home" || fixture.scenario == "dock-home",
                        fixturePlayerSettings: fixture.scenario == "player-settings",
                        fixtureZapList: fixture.scenario == "zapping",
                        fixtureAddSource: fixture.scenario == "add-source",
                        fixtureLists: fixture.scenario == "lists" || fixture.scenario == "dock-lists",
                        fixturePlayer: fixture.showsPlayer,
                        fixtureHoldsControls: fixture.holdsPlayerControls,
                        fixtureTracksPanel: fixture.scenario == "player-tracks",
                        fixtureBanner: fixture.showsBanner)
                .environmentObject(library)
                .environmentObject(playback)
                .preferredColorScheme(.dark)
                .task {
                    // A capture has no thumb on the remote: "x,y" places one,
                    // to show what has the focus leaning with it.
                    // "movies-many-lean": the thumb rests up and right of where it landed.
                    let lean = ProcessInfo.processInfo.environment["FLUX_UI_LEAN"]
                        ?? (fixture.scenario == "movies-many-lean" ? "0.9,-0.6" : "")
                    let parts = lean.split(separator: ",").compactMap { Double($0) }
                    guard parts.count == 2 else { return }
                    for _ in 0..<40 {
                        try? await Task.sleep(nanoseconds: 250_000_000)
                        RemoteTouch.shared.place(CGSize(width: parts[0], height: parts[1]))
                    }
                }
                // What the screen rebuilds, for the flow that counts it.
                .overlay(alignment: .topLeading) {
                    if ProcessInfo.processInfo.environment["FLUX_UI_PROBE"] == "1" { TVProbeReadout() }
                }
                .task {
                    // XCUIRemote owns readiness and subsequent input during
                    // interaction tests. The initial-capture observer must not
                    // keep asserting an old destination while the user moves.
                    if ProcessInfo.processInfo.environment["FLUX_UI_REMOTE_TESTING"] == "1" { return }
                    await TVCatalogCapture.awaitInitialFocus(fixture: fixture, library: library,
                                                             playback: playback, searches: searchObservations)
                    if let restoredDefaultsSuite {
                        library.flushBrowsingPreferences()
                        UserDefaults(suiteName: restoredDefaultsSuite)?.removePersistentDomain(forName: restoredDefaultsSuite)
                    }
                }
            }
        }
    }
}

@MainActor private struct TVCatalogFixture {
    let scenario: String
    let source: IPTVSource
    let items: [IPTVItem]
    let kind: IPTVMediaKind
    let selection: IPTVItem?
    let seasons: [IPTVSeason]
    let openSeason: Int?
    let episodeID: String?
    /// The seasons that the shortcuts of the dock lead to: the library
    /// serves them, and the screen does not start on them.
    var dockSeasons: [IPTVSeason] = []

    var expectedInitialControl: String {
        switch scenario {
        case "live", "live-many", "live-many-light": return "live-channel-fixture-live-0"
        case "live-fr": return "live-channel-fixture-country-fr-0"
        case "live-es": return "live-channel-fixture-country-es-0"
        case "live-restored": return "live-channel-fixture-country-fr-1"
        case "country-picker": return "live-country-option-FR"
        case "movies", "movies-many", "movies-many-lean", "dock", "dock-folders": return "catalog-card-fixture-movie-1"
        // The bar of the home screen with what the user keeps in it; a
        // folder of the dock open on its first title.
        case "dock-home": return "navigation-tab-movie"
        case "dock-folder": return DockEntry.fanPrefix + "fixture-movie-0"
        // Nothing found: the row of the column where the search looked.
        case "search-empty": return "search-kind-movie"
        case "search-result": return "catalog-card-fixture-movie-0"
        case "welcome": return "welcome-load-source"
        case "add-source": return "source-server"
        // The shelf of a series opens on its first season.
        case "seasons": return "season-sleeve-1"
        // The lists of a title open on the first of them.
        case "lists", "dock-lists": return "favorite-list-0"
        // The commands of the player open on play and pause; its languages
        // on the audio in use.
        case "player", "player-film", "player-flow", "player-film-flow", "player-deep": return "player-playpause"
        // Under the banner of a channel the picture itself holds the remote.
        case "player-banner", "player-banner-opening": return "player-catcher"
        case "player-tracks": return "track-audio-a1"
        // The desk: the bar of the home screen, the destination of the
        // settings, the channel on screen in the list of the player.
        case "home": return "navigation-tab-live"
        // Without a catalogue the remote starts on the first control of the column.
        case "live-error": return "navigation-countries"
        // Réglages opens with the remote on the page it shows.
        case "settings": return "settings-page-sources"
        case "settings-graphics": return "settings-page-graphics"
        case "settings-remote": return "settings-page-remote"
        case "pointer", "pointer-list": return "live-channel-fixture-live-0"
        case "player-settings": return "settings-page-video"
        case "zapping": return "zap-channel-fixture-live-0"
        default: return "media-detail-play"
        }
    }

    var minimumFocusSize: CGSize {
        switch scenario {
        // A channel is a row of the list, not a tile.
        case "live", "live-many", "live-many-light", "live-fr", "live-es", "live-restored", "zapping": return CGSize(width: 300, height: 60)
        case "home": return CGSize(width: 150, height: 150)
        // Its one full bar keeps icons larger than those of the dock.
        case "dock-home": return CGSize(width: 100, height: 100)
        // A title of the open folder: the size of an icon of the dock.
        case "dock-folder": return CGSize(width: 76, height: 48)
        case "settings", "settings-graphics", "settings-remote", "player-settings": return CGSize(width: 240, height: 48)
        case "live-error": return CGSize(width: 150, height: 50)
        case "country-picker": return CGSize(width: 240, height: 54)
        case "movies", "movies-many", "movies-many-lean", "search-result", "seasons", "dock": return CGSize(width: 240, height: 350)
        case "search-empty": return CGSize(width: 240, height: 48)
        case "welcome": return CGSize(width: 300, height: 72)
        case "add-source": return CGSize(width: 500, height: 50)
        case "lists", "dock-lists": return CGSize(width: 400, height: 48)
        case "player", "player-film", "player-flow", "player-film-flow": return CGSize(width: 70, height: 70)
        case "player-tracks": return CGSize(width: 300, height: 44)
        default: return CGSize(width: 180, height: 64)
        }
    }

    var searchQuery: String? {
        switch scenario {
        case "search-empty": return "no-matching-flux-title"
        case "search-result": return "dunes"
        default: return nil
        }
    }

    var expectedSearchFocus: String? {
        switch scenario {
        case "search-empty": return "search-kind-movie"
        case "search-result": return "fixture-movie-0"
        default: return nil
        }
    }

    var expectedSearchResults: [String] {
        scenario == "search-result" ? ["fixture-movie-0"] : []
    }

    var usesPortraitControl: Bool { scenario == "movies" || scenario.hasPrefix("movies-many") || scenario == "search-result" || scenario == "dock" }
    /// The films with what a user keeps in the dock: shortcuts in two
    /// sections, a film left unfinished, and a list as a folder.
    /// "dock-folders": the same dock with a folder of shortcuts that holds another.
    static let dockScenarios = ["dock", "dock-home", "dock-folder", "dock-lists", "dock-folders"]
    var fillsDock: Bool { Self.dockScenarios.contains(scenario) }

    var countryCode: String? {
        switch scenario {
        case "live-fr", "country-picker", "live-restored": return "FR"
        case "live-es": return "ES"
        default: return nil
        }
    }

    /// Screens of the desk shown over the catalogue of the live scenario.
    /// "pointer": the live catalogue under the pointer of the remote;
    /// "pointer-list": the same, the pointer riding the list of the channels.
    static let deskScenarios = ["home", "settings", "settings-dock", "settings-graphics", "settings-remote", "zapping", "player-settings",
                                "player", "player-flow", "player-deep", "player-banner", "player-banner-opening", "pointer", "pointer-list"]
    /// The bare picture just after a change of channel, under its banner.
    var showsBanner: Bool { scenario.hasPrefix("player-banner") }
    /// The commands of a film: its timeline, its languages.
    static let filmPlayerScenarios = ["player-film", "player-film-flow", "player-tracks"]
    var showsPlayer: Bool { scenario.hasPrefix("player") }
    var playsFilm: Bool { Self.filmPlayerScenarios.contains(scenario) }
    /// A capture keeps the commands on a media that plays; a remote flow lets
    /// them hide, as they do during a stream.
    var holdsPlayerControls: Bool { ["player", "player-film", "player-tracks"].contains(scenario) }
    var settingsPage: PlaybackSettingsView.Page? {
        switch scenario {
        case "settings": return .sources
        case "settings-dock": return .dock
        case "settings-graphics": return .graphics
        case "settings-remote": return .remote
        default: return nil
        }
    }

    var opensCountryPicker: Bool { scenario == "country-picker" }
    var restoresBrowsing: Bool { scenario == "live-restored" }
    var usesPersistedSelection: Bool { restoresBrowsing || scenario == "live-fr" || scenario == "live-es" }

    var expectedCountryResults: [String] {
        // The restored group is a part of these: no query narrows them.
        switch countryCode {
        case "FR": return ["fixture-country-fr-0", "fixture-country-fr-1", "fixture-country-fr-2"]
        case "ES": return ["fixture-country-es-0", "fixture-country-es-1"]
        default: return []
        }
    }

    static func make() throws -> TVCatalogFixture {
        let scenario = ProcessInfo.processInfo.environment["FLUX_UI_SCENARIO"] ?? ""
        // A screen of the desk reuses the catalogue of the live scenario.
        let content = deskScenarios.contains(scenario) || scenario.hasPrefix("live-many") ? "live" : scenario
        try TVCatalogCapture.require((["movie", "movies", "movies-many", "movies-many-lean", "lists", "series", "seasons", "live", "live-many", "live-many-light", "welcome", "add-source", "search-empty", "search-result",
                                       "live-fr", "live-es", "country-picker", "live-restored", "live-error"] + deskScenarios + filmPlayerScenarios + dockScenarios).contains(scenario),
                                     "FLUX_UI_SCENARIO must name a supported catalogue, detail, welcome or search scenario.")
        let source = IPTVSource(id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
                                name: "Catalogue local de démonstration", kind: scenario == "live-error" ? .xtream : .m3uFile)
        if scenario == "welcome" || scenario == "live-error" || scenario == "add-source" {
            return TVCatalogFixture(scenario: scenario, source: source, items: [], kind: .live,
                                    selection: nil, seasons: [], openSeason: nil, episodeID: nil)
        }
        let artworkRoot = FileManager.default.temporaryDirectory.appendingPathComponent("FluxTVUIArtwork", isDirectory: true)
        if ["live-fr", "live-es", "country-picker", "live-restored"].contains(scenario) {
            // Mixed provider prefixes share one catalogue. Unclassified rows
            // must remain selectable through the country picker, and must not
            // leak into FR or ES. The old live fixture stays unchanged.
            let entries: [(id: String, name: String, group: String)] = [
                ("fr-0", "Horizon France", "FR | Généralistes"),
                ("fr-1", "Grand écran France", "[FR] Cinéma"),
                ("fr-2", "Découverte France", "FR - Documentaires"),
                ("es-0", "Deporte España", "ES - Deportes"),
                ("es-1", "Noticias España", "[ES] Noticias"),
                ("gb-0", "World News UK", "UK | News"),
                ("gb-1", "Discover UK", "[UK] Documentary"),
                ("unknown-0", "Canal local", "Généralistes"),
                ("unknown-1", "Monde partagé", "International")
            ]
            let channels = try entries.enumerated().map { index, entry in
                let url = artworkRoot.appendingPathComponent("country-\(entry.id).png")
                cache(try artwork(width: 480, height: 270, index: index, title: entry.name.uppercased(),
                                  subtitle: entry.group.uppercased()), at: url)
                return IPTVItem(id: "fixture-country-\(entry.id)", sourceID: source.id, name: entry.name,
                                group: entry.group, logoURL: url, kind: .live,
                                directURL: nil, xtreamStreamID: nil, fileExtension: nil)
            }
            let selectedID = scenario == "live-es" ? "fixture-country-es-0"
                : scenario == "live-restored" ? "fixture-country-fr-1" : "fixture-country-fr-0"
            guard let selected = channels.first(where: { $0.id == selectedID }) else {
                throw TVCatalogUIFailure.assertion("The expected country channel is absent from the mixed fixture.")
            }
            return TVCatalogFixture(scenario: scenario, source: source, items: channels, kind: .live,
                                    selection: selected, seasons: [], openSeason: nil, episodeID: nil)
        }
        func films() throws -> [IPTVItem] {
            let titles = ["Au-delà des dunes", "La dernière séance", "Les lumières du port"]
            var items: [IPTVItem] = []
            for (index, title) in titles.enumerated() {
                let url = artworkRoot.appendingPathComponent("movie-\(index).png")
                cache(try artwork(index: index, title: title.uppercased(), subtitle: "JAQUETTE LOCALE · 2024"), at: url)
                items.append(IPTVItem(id: "fixture-movie-\(index)", sourceID: source.id, name: title,
                                      group: "Cinéma · Aventure", logoURL: url, kind: .movie,
                                      directURL: nil, xtreamStreamID: nil, fileExtension: nil,
                                      details: IPTVDetails(
                                        synopsis: "À la veille de la fermeture de son cinéma, une projectionniste retrouve une bobine oubliée. Les images la conduisent vers une petite ville du littoral, où personne ne semble se souvenir du tournage. Avec un jeune musicien et une ancienne comédienne, elle remonte le fil d’une histoire qui relie trois générations. Un voyage entre mémoire, transmission et promesses, porté par les paysages de la côte et les lumières de la dernière séance.",
                                        year: "2024", duration: "1 h 58 min", rating: "8.4", genre: "Aventure · Drame",
                                        cast: "Camille Morel, Gabriel Martin, Louise Perrin", director: "Alexandre Laurent")))
            }
            return items
        }
        if content == "live" {
            let categories = ["Généralistes", "Cinéma", "Documentaires", "Jeunesse", "Musique", "Sports"]
            let channelNames = ["Horizon", "Panorama", "Grand écran", "Découverte", "Évasion", "Scène"]
            // "player-deep" has more channels than the sixty its list builds
            // at a time, and than a page of the catalogue. Their logos are
            // smaller, so that the cache of the application keeps them all.
            let deep = scenario == "player-deep"
            // The banner is read on the catalogue of a real subscription:
            // tens of thousands of channels, so a number of five digits.
            let banner = scenario.hasPrefix("player-banner")
            // "live-many": the same catalogue on the page of the channels,
            // with the categories of several countries.
            let many = scenario.hasPrefix("live-many")
            let countries = ["FR", "UK", "ES", "IT", "DE", "PT", "BE", "CH"]
            let watched = banner ? 24_013 : deep ? 58 : 0
            // What is drawn over the picture is read with names shaped like
            // those of a real playlist: a prefix, a long title, a mark of
            // quality, and categories that carry their country.
            let real = scenario.hasPrefix("player") || scenario == "zapping" || many
            let realNames = ["FR: HORIZON INFO", "PRISME: GRAND ÉCRAN FESTIVAL", "FR| DÉCOUVERTE NATURE & VOYAGES",
                             "PRISME: PANORAMA JEUNESSE", "ÉVASION MUSIQUE HITS", "FR: SCÈNE SPORT 360"]
            let marks = ["ᴴᴰ", "ᴿᴬᵂ", "ᶠᴴᴰ", "⁴ᴷ", "ᴴᴰ", "ᴿᴬᵂ"]
            let channels = try (0..<(banner || many ? 24_665 : deep ? 110 : 18)).map { (index: Int) in
                let kind = index % channelNames.count
                let name: String
                if real {
                    // The first of each keeps its bare title; the others are numbered.
                    name = index < realNames.count || index == watched && banner
                        ? "\(realNames[kind]) \(marks[kind])" : "\(realNames[kind]) \(index / realNames.count + 1) \(marks[kind])"
                } else { name = "\(channelNames[kind]) \(index + 1)" }
                // A logo for what can come on screen: the cache of the
                // application would not keep thousands of them.
                var url: URL? = nil
                if !(banner || many) || abs(index - watched) < (many ? 84 : 40) {
                    let file = artworkRoot.appendingPathComponent("live-\(index).png")
                    let small = deep || banner || many
                    cache(try artwork(width: small ? 240 : 480, height: small ? 135 : 270, index: index,
                                      title: (real ? realNames[kind] : name).uppercased(), subtitle: "CHAÎNE LOCALE"), at: file)
                    url = file
                }
                return IPTVItem(id: "fixture-live-\(index)", sourceID: source.id, name: name,
                                group: many ? "DIRECT - \(countries[index / 420 % countries.count])| " + categories[kind].uppercased()
                                    : real ? "DIRECT - FR| " + categories[kind].uppercased() : categories[kind],
                                logoURL: url, kind: .live,
                                directURL: nil, xtreamStreamID: nil, fileExtension: nil)
            }
            // The home screen leads to every section: its catalogue has films too.
            // "player-deep": a channel far down the list, whose row the
            // channel list has to scroll to before it can take the remote,
            // one row before the end of the sixty it builds.
            return TVCatalogFixture(scenario: scenario, source: source,
                                    items: channels + (scenario == "home" ? try films() : []), kind: .live,
                                    selection: channels[watched], seasons: [], openSeason: nil, episodeID: nil)
        }
        var items = try films()
        if dockScenarios.contains(scenario) {
            // Channels for the shortcuts of the dock, beside the films and the series.
            for (index, name) in ["Horizon", "Panorama", "Grand écran"].enumerated() {
                let url = artworkRoot.appendingPathComponent("dock-live-\(index).png")
                cache(try artwork(width: 240, height: 135, index: index + 1, title: name.uppercased(), subtitle: "CHAÎNE LOCALE"), at: url)
                items.append(IPTVItem(id: "fixture-live-\(index)", sourceID: source.id, name: "\(name) \(index + 1)",
                                      group: "Généralistes", logoURL: url, kind: .live,
                                      directURL: nil, xtreamStreamID: nil, fileExtension: nil))
            }
        }
        if scenario.hasPrefix("movies-many") {
            // The catalogue of a real subscription: tens of thousands of films,
            // titles that carry their language and their year, categories by
            // language. The first page alone has jackets, small enough for
            // the cache of the application to keep them all.
            let titles = ["La colline aux secrets", "Le dernier rivage", "Les ombres du fleuve", "Un hiver à Trieste", "La nuit des cerfs-volants",
                          "Le chant des dunes", "Les portes du soir", "Minuit sur la baie", "La maison des vents", "Le passager du nord",
                          "Trois jours en mer", "Les jardins suspendus", "Le silence des marées", "La route des orages"]
            let categories = ["FR - LES DERNIERS AJOUTS", "FR - HORREUR", "FR - DRAME", "FR - ACTION", "FR - COMÉDIE", "FR - THRILLER",
                              "FR - SCIENCE-FICTION", "FR - ANIMATION", "FR - FAMILLE", "FR - DOCUMENTAIRE", "FR - WESTERN", "FR - GUERRE",
                              "FR - ROMANCE", "FR - POLICIER", "FR - FANTASTIQUE", "FR - AVENTURE", "FR - HISTOIRE", "FR - CLASSIQUES",
                              "EN - ACTION", "EN - DRAMA", "EN - HORROR", "EN - COMEDY", "EN - THRILLER", "EN - FAMILY",
                              "ES - ACCIÓN", "ES - DRAMA", "ES - COMEDIA", "IT - AZIONE", "IT - DRAMMA", "IT - COMMEDIA"]
            for index in items.count..<58_093 {
                let group = categories[index % categories.count]
                let language = String(group.prefix(2))
                let sequel = index / titles.count % 4
                let name = "\(language) - \(titles[index % titles.count])\(sequel == 0 ? "" : " \(sequel + 1)") (\(1990 + index % 37))"
                var url: URL? = nil
                if index < 84 {
                    let file = artworkRoot.appendingPathComponent("movie-many-\(index).png")
                    cache(try artwork(width: 180, height: 270, index: index, title: titles[index % titles.count].uppercased(),
                                      subtitle: "JAQUETTE LOCALE"), at: file)
                    url = file
                }
                items.append(IPTVItem(id: "fixture-movie-\(index)", sourceID: source.id, name: name, group: group,
                                      logoURL: url, kind: .movie, directURL: nil, xtreamStreamID: nil, fileExtension: nil,
                                      details: IPTVDetails(synopsis: "Un film local de démonstration, sans adresse de flux.",
                                                           year: "\(1990 + index % 37)", duration: "1 h 4\(index % 10) min")))
            }
        }
        let seriesURL = artworkRoot.appendingPathComponent("series.png")
        cache(try artwork(index: 3, title: "LES SAISONS", subtitle: "JAQUETTE LOCALE · 2014"), at: seriesURL)
        let collection = IPTVItem(id: "fixture-series", sourceID: source.id, name: "Les saisons",
                                  group: "Séries · Drame", logoURL: seriesURL, kind: .series,
                                  directURL: nil, xtreamStreamID: nil, fileExtension: nil, isSeriesCollection: true,
                                  details: IPTVDetails(
                                    synopsis: "Dans une maison ouverte sur les montagnes, les membres d’une famille se retrouvent chaque année à la même date. Les retrouvailles font émerger des souvenirs, des secrets et de nouveaux départs. Douze saisons racontent les liens qui les unissent, au fil des paysages et des générations. Cette fiche conserve la saison 12 et l’épisode 15 sélectionnés lorsque l’on revient du lecteur.",
                                    year: "2014", duration: "42 min", genre: "Drame · Famille",
                                    cast: "Sarah Valette, Julien Roche, Anaïs Mercier", director: "Émilie Bernard"))
        items.append(collection)
        // Explicit Int types prevent Optional interpolation in fixture IDs.
        let seasons = (1...12).map { (number: Int) in
            IPTVSeason(number: number, episodes: (1...16).map { (episode: Int) in
                IPTVItem(id: "fixture-series-s\(number)-e\(episode)", sourceID: source.id,
                         name: episode == 15 ? "Le chemin du retour" : "Les retrouvailles — chapitre \(episode)",
                         group: collection.group, logoURL: seriesURL, kind: .series,
                         directURL: nil, xtreamStreamID: nil, fileExtension: nil,
                         details: IPTVDetails(synopsis: "Un épisode local de démonstration, sans adresse de flux.", year: "2025", duration: "42 min"),
                         seasonNumber: number, episodeNumber: episode)
            })
        }
        let episodeID = "fixture-series-s12-e15"
        try TVCatalogCapture.require(seasons.first(where: { $0.number == 12 })?.episodes.contains(where: { $0.id == episodeID }) == true,
                                     "The exact requested S12/E15 fixture identifier is absent.")
        let isMovie = scenario == "movie" || scenario == "movies" || scenario.hasPrefix("movies-many") || scenario == "lists" || scenario.hasPrefix("search-")
            || filmPlayerScenarios.contains(scenario) || dockScenarios.contains(scenario)
        return TVCatalogFixture(scenario: scenario, source: source, items: items,
                                kind: isMovie ? .movie : .series,
                                selection: isMovie ? items[1] : collection,
                                seasons: scenario == "series" || scenario == "seasons" ? seasons : [],
                                openSeason: scenario == "series" ? 12 : nil,
                                episodeID: scenario == "series" ? episodeID : nil,
                                dockSeasons: dockScenarios.contains(scenario) ? seasons : [])
    }

    private static func cache(_ image: CGImage, at url: URL) {
        let bitmap = FluxBitmap(image)
        let cost = image.bytesPerRow * image.height
        ArtworkLoader.cache.setObject(bitmap, forKey: url.absoluteString as NSString, cost: cost)
        ArtworkLoader.wallpaperCache.setObject(bitmap, forKey: url.absoluteString as NSString, cost: cost)
        ArtworkLoader.caseCache.setObject(bitmap, forKey: url.absoluteString as NSString, cost: cost)
    }

    private static func artwork(width: Int = 480, height: Int = 720, index: Int, title: String, subtitle: String) throws -> CGImage {
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw TVCatalogUIFailure.assertion("Cannot create deterministic local artwork.")
        }
        let colors: [(CGFloat, CGFloat, CGFloat)] = [(0.76, 0.44, 0.19), (0.15, 0.47, 0.68), (0.13, 0.53, 0.42), (0.48, 0.29, 0.62)]
        let color = colors[index % colors.count]
        let w = CGFloat(width), h = CGFloat(height)
        context.setFillColor(CGColor(red: color.0 * 0.2, green: color.1 * 0.2, blue: color.2 * 0.2, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: w, height: h))
        context.setFillColor(CGColor(red: color.0, green: color.1, blue: color.2, alpha: 1))
        context.fillEllipse(in: CGRect(x: -w * 0.25, y: h * 0.26, width: w * 1.5, height: w * 1.5))
        context.setFillColor(CGColor(gray: 0.03, alpha: 0.82))
        context.fill(CGRect(x: 0, y: 0, width: w, height: h * 0.3))
        drawText(title, size: min(34, w * 1.4 / CGFloat(max(1, title.count))), y: h * 0.18, width: w, in: context)
        drawText(subtitle, size: 14, y: h * 0.075, width: w, in: context)
        guard let image = context.makeImage() else { throw TVCatalogUIFailure.assertion("Cannot finish local artwork.") }
        return image
    }

    private static func drawText(_ text: String, size: CGFloat, y: CGFloat, width: CGFloat, in context: CGContext) {
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("HelveticaNeue-Bold" as CFString, size, nil),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 1, alpha: 1)
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        context.textPosition = CGPoint(x: (width - CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))) / 2, y: y)
        CTLineDraw(line, context)
    }
}

@MainActor private enum TVCatalogCapture {
    static let bundleID = "com.m4d135.FluxIPTV.TVCatalogUISmoke"
    private static var reportURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FluxTVCatalogUI-ready.json")
    }

    /// What a user keeps in the dock, through the production model: two
    /// shortcuts, a section named for a series with one of its seasons
    /// and one of its episodes, a film watched, and the favourite films
    /// as a folder.
    static func fillDock(of library: IPTVLibrary, source: IPTVSource) throws {
        func title(_ id: String) throws -> IPTVItem {
            guard let item = library.catalogItem(id: id) else { throw TVCatalogUIFailure.assertion("Missing fixture title \(id).") }
            return item
        }
        let series = try title("fixture-series")
        let episode = IPTVItem(id: "fixture-series-s12-e15", sourceID: source.id, name: "Le chemin du retour", group: series.group,
                               logoURL: nil, kind: .series, directURL: nil, xtreamStreamID: nil, fileExtension: nil,
                               seasonNumber: 12, episodeNumber: 15)
        let general: Set<String> = [DockShelf.defaultSectionID]
        try require(library.assignDock(DockShortcut(item: try title("fixture-live-0")), to: general)
                    && library.assignDock(DockShortcut(item: try title("fixture-movie-1")), to: general)
                    && library.assignDock(DockShortcut(item: series), to: [], creating: "Le soir"),
                    "The dock fixture could not keep its shortcuts.")
        let evening: Set<String> = [library.dockShelf.sections[1].id]
        try require(library.assignDock(DockShortcut(series: series, season: 3), to: evening)
                    && library.assignDock(DockShortcut(series: series, episode: episode), to: evening),
                    "The dock fixture could not keep a season and an episode.")
        let list = FavoritePresets.defaultID(for: .movie)
        for id in ["fixture-movie-0", "fixture-movie-2"] { library.toggleFavorite(try title(id), in: list) }
        library.setDockStack(list, shown: true)
        library.visitDock(DockShortcut(item: try title("fixture-live-2")))
        library.visitDock(DockShortcut(item: try title("fixture-movie-2")))
        try require(library.dockShelf.showsStack(list) && library.dockShelf.recents.first?.id == "fixture-movie-2",
                    "The dock fixture is not what its scenarios expect.")
        guard ProcessInfo.processInfo.environment["FLUX_UI_SCENARIO"] == "dock-folders" else { return }
        // A folder made in the dock, with an icon of its own, a film, and a
        // folder inside it that holds a film and a series.
        func keep(_ shortcut: DockShortcut, in folder: String) -> Bool {
            library.assignDock(shortcut, to: library.dockShelf.sections(holding: shortcut.id).union([folder]))
        }
        guard let evening = library.createDockSection(name: "Soirée", folded: true),
              let classics = library.createDockSection(name: "Classiques", folded: true, in: evening) else {
            throw TVCatalogUIFailure.assertion("The dock fixture could not make its folders.")
        }
        library.setDockSymbol(evening, "popcorn.fill")
        try require(keep(DockShortcut(item: try title("fixture-movie-0")), in: evening)
                    && keep(DockShortcut(item: try title("fixture-movie-2")), in: classics)
                    && keep(DockShortcut(item: series), in: classics),
                    "The dock fixture could not fill its folders.")
        try require(library.dockShelf.topFolders.map(\.name) == ["Soirée"]
                    && library.dockShelf.titles(under: evening, sourceID: source.id).count == 3,
                    "The folders of the dock fixture are not what the flow expects.")
    }

    /// The glass and the movements, unless the scenario or the bench asks
    /// for the lightest screen.
    private static var fullEffects: Bool {
        ProcessInfo.processInfo.environment["FLUX_UI_EFFECTS"] != "light"
            && !(ProcessInfo.processInfo.environment["FLUX_UI_SCENARIO"] ?? "").hasSuffix("-light")
    }

    static func configureDefaults() {
        // A separate bundle in a newly created simulator has no user profiles.
        // Volatile overrides leave even that disposable persistent domain alone.
        var folder: [String: Any] = [:]
        // "dock-folder": the folder of the favourite films, open above the dock.
        if ProcessInfo.processInfo.environment["FLUX_UI_SCENARIO"] == "dock-folder" {
            folder["fluxiptv.fixture.dockFan"] = DockEntry.stack(listID: FavoritePresets.defaultID(for: .movie)).id
        }
        // FLUX_UI_DOCK_HIDDEN=1: the dock hidden under the screens.
        if ProcessInfo.processInfo.environment["FLUX_UI_DOCK_HIDDEN"] == "1" {
            folder[FluxDockVisibility.storageKey] = false
        }
        // The mode of the remote is saved by Play/Pause held down: each
        // launch starts from the classic one, or from the pointer it asks
        // for: "pointer", or any screen with FLUX_UI_POINTER=1.
        UserDefaults.standard.removeObject(forKey: FluxRemoteMode.storageKey)
        if ["pointer", "pointer-list"].contains(ProcessInfo.processInfo.environment["FLUX_UI_SCENARIO"] ?? "")
            || ProcessInfo.processInfo.environment["FLUX_UI_POINTER"] == "1" {
            UserDefaults.standard.set(FluxRemoteMode.pointer.rawValue, forKey: FluxRemoteMode.storageKey)
        }
        // The look of the pointer is chosen in a flow of the settings, and
        // the theme of the dock in a flow of the studio: each launch starts
        // from the ones by default.
        for key in [FluxPointerShape.storageKey, FluxPointerColor.storageKey, FluxPointerSize.storageKey,
                    FluxPointerSpeed.storageKey, FluxPointerAcceleration.storageKey] {
            UserDefaults.standard.removeObject(forKey: key)
        }
        UserDefaults.standard.removeObject(forKey: FluxDockTheme.storageKey)
        UserDefaults.standard.removeObject(forKey: FluxDockThemeChoices.storageKey)
        UserDefaults.standard.setVolatileDomain(folder.merging([
            // Liquid Glass is what the application shows by default: the
            // captures and the focus checks run on it.
            // "…-light", or the bench asking for it: the dark surfaces and
            // the immediate focus, the lightest that a television can show.
            // "material" keeps the glass and draws it as an Apple TV HD
            // does, from the blur of the system.
            FluxAppearance.glassKey: Self.fullEffects,
            FluxAppearance.motionKey: Self.fullEffects,
            FluxAppearance.artworkKey: true,
            FluxAppearance.densityKey: "cinema",
            MediaThemePreferences.tvKey: VideoClubTheme.neo90.rawValue,
            MediaThemePreferences.cinemaKey: VideoClubTheme.neo90.rawValue,
            MediaThemePreferences.seriesKey: VideoClubTheme.neo90.rawValue,
            ClubInterfaceProfile.storageKey: ClubInterfaceProfile.neoVideoClub.rawValue,
            LiveTVPreviewDelay.automaticKey: false,
            TrailerPreviewDelay.automaticKey: false
        ]) { _, base in base }, forName: UserDefaults.argumentDomain)
    }

    /// Write with one real library, then recreate another from the same
    /// isolated preferences. ContentView receives no selected-item fixture;
    /// its production restore path must recover the intended native focus.
    static func makeRestoredBrowsingLibrary(fixture: TVCatalogFixture) throws
        -> (library: IPTVLibrary, suiteName: String) {
        guard fixture.usesPersistedSelection, let countryCode = fixture.countryCode,
              let selectedID = fixture.selection?.id else {
            throw TVCatalogUIFailure.assertion("The restoration fixture needs its expected country and channel.")
        }
        let expectedGroup: String? = fixture.restoresBrowsing ? "[FR] Cinéma" : nil
        // What 0.9.6 kept with a section, and 0.9.7 no longer shows: the
        // series of David showed the pictures of the search because of it.
        let oldSearch = fixture.restoresBrowsing ? "Grand écran" : ""
        let expectedGroupSearch = fixture.restoresBrowsing ? "Cin" : ""
        let suiteName = "\(bundleID).RestoredUI.\(UUID().uuidString)"
        guard let storedDefaults = UserDefaults(suiteName: suiteName) else {
            throw TVCatalogUIFailure.assertion("Cannot create the isolated UI restoration suite.")
        }
        do {
            let original = IPTVLibrary(catalogFixture: fixture.source, items: fixture.items, kind: .live,
                                       browsingDefaults: storedDefaults)
            original.countryCode = countryCode
            original.group = expectedGroup
            original.groupSearch = expectedGroupSearch
            original.browseItemID = selectedID
            original.flushBrowsingPreferences()
            guard let data = storedDefaults.data(forKey: CatalogBrowsingPreferences.storageKey), !data.isEmpty else {
                throw TVCatalogUIFailure.assertion("UI restoration has no persisted browsing state to read.")
            }
            var preferences = CatalogBrowsingPreferences.decoded(data)
            var saved = preferences.state(for: fixture.source.id, kind: .live)
            try require(saved.countryCode == countryCode && saved.group == expectedGroup && saved.search.isEmpty &&
                        saved.groupSearch == expectedGroupSearch && saved.browseItemID == selectedID,
                        "The initial library did not persist the exact UI restoration fixture.")
            if !oldSearch.isEmpty {
                saved.search = oldSearch
                preferences.remember(saved, sourceID: fixture.source.id, kind: .live)
                storedDefaults.set(try JSONEncoder().encode(preferences), forKey: CatalogBrowsingPreferences.storageKey)
            }
            guard let reopenedDefaults = UserDefaults(suiteName: suiteName) else {
                throw TVCatalogUIFailure.assertion("Cannot reopen the isolated UI restoration suite.")
            }
            let reopened = IPTVLibrary(catalogFixture: fixture.source, items: fixture.items, kind: .live,
                                       browsingDefaults: reopenedDefaults)
            return (reopened, suiteName)
        } catch {
            storedDefaults.removePersistentDomain(forName: suiteName)
            throw error
        }
    }

    static func awaitInitialFocus(fixture: TVCatalogFixture, library: IPTVLibrary,
                                  playback: PlaybackController, searches: TVCatalogSearchObservations) async {
        do {
            let persistence: [String: Any]
            if fixture.opensCountryPicker {
                persistence = try await verifyBrowsingPersistence(fixture: fixture)
            } else {
                persistence = ["browsingPersistenceTested": false]
            }
            // Wait for real SwiftUI tasks and the native compositor, not a
            // synthetic scenePhase override or an image-renderer snapshot.
            try await Task.sleep(nanoseconds: 2_000_000_000)
            var previousFocus = "", stableSamples = 0
            var lastObservation: [String: Any] = [:]
            for _ in 0..<80 {
                try Task.checkCancellation()
                let precedingFocus = previousFocus
                previousFocus = ""
                // The screens of the player show the state of a media that
                // plays; no engine holds anything for them either.
                try require((playback.playingItem == nil || (fixture.showsPlayer && playback.showsFixture))
                            && playback.player.currentItem == nil,
                            "The visual fixture unexpectedly started main playback.")
                let search = searchEvidence(fixture: fixture, library: library, observations: searches.snapshots)
                lastObservation = search.report
                let country = countryEvidence(fixture: fixture, library: library)
                lastObservation.merge(country.report) { _, new in new }
                lastObservation.merge(persistence) { _, new in new }
                let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                    .filter { $0.activationState == .foregroundActive }.flatMap(\.windows)
                if let window = windows.first(where: { $0.isKeyWindow && !$0.isHidden }),
                   window.bounds.width > 800, window.bounds.height > 400 {
                    try require(!containsSceneKit(window), "A SceneKit view is still mounted in the full-screen detail hierarchy.")
                    let detail = detailBoxEvidence(fixture: fixture, window: window)
                    lastObservation.merge(detail.report) { _, new in new }
                    let form = sourceFormEvidence(fixture: fixture, window: window)
                    lastObservation.merge(form.report) { _, new in new }
                    let banner = bannerEvidence(fixture: fixture, playback: playback, window: window)
                    lastObservation.merge(banner.report) { _, new in new }
                    if let focused = UIFocusSystem.focusSystem(for: window)?.focusedItem {
                        let native = nativeFrame(focused, in: window)
                        let frame = native.frame
                        let measuredProbes = controlProbes(in: window).filter {
                            $0.controlIdentifier == fixture.expectedInitialControl && $0.window === window
                        }
                        // ViewThatFits may measure a fallback before choosing
                        // its visible child. A zero-sized/offscreen probe is
                        // not a second mounted control; two visible probes
                        // remain ambiguous and must fail.
                        let probes = measuredProbes.filter {
                            let bounds = $0.convert($0.bounds, to: window)
                            return valid(bounds) && valid(bounds.intersection(window.bounds))
                        }
                        let expectedFrame = probes.count == 1 ? probes[0].convert(probes[0].bounds, to: window) : CGRect.null
                        let viewport = probes.count == 1 ? visibleViewport(from: probes[0].superview, in: window) : CGRect.null
                        let comparison = compareFocus(frame, with: expectedFrame, in: window.bounds)
                        let windowArea = window.bounds.width * window.bounds.height
                        let fraction = area(frame) / windowArea
                        // A portrait catalogue card includes its 2:3 artwork
                        // and labels. Keep the tighter bound for all controls
                        // and landscape tiles in the other scenarios.
                        let maximumHeightFraction: CGFloat = fixture.usesPortraitControl ? 0.60 : 0.45
                        // Under the banner of a channel the picture itself
                        // holds the remote: what waits for it covers the
                        // screen by design, and is not a control to bound.
                        let bounded = valid(frame) && fraction.isFinite && (fixture.showsBanner ||
                            fraction < 0.18 && frame.width < window.bounds.width * 0.75 && frame.height < window.bounds.height * maximumHeightFraction)
                        let identity = focusIdentity(focused)
                        // An empty accessibility identifier supplies no proof.
                        // Every pass requires the native focused item's real
                        // geometry to match one unique measured control.
                        let identifierConflict = !identity.identifier.isEmpty && identity.identifier != fixture.expectedInitialControl
                        let expectedFocus = probes.count == 1 && comparison.matches && !identifierConflict
                        let largeEnough = frame.width >= fixture.minimumFocusSize.width && frame.height >= fixture.minimumFocusSize.height
                        // A small enough card can still extend below its grid.
                        // The actual control probe supplies the clipping chain,
                        // while the native focused item's frame is independently
                        // converted through its verified focus container.
                        let fullyVisible = valid(frame) && valid(expectedFrame) && valid(viewport) &&
                            viewport.insetBy(dx: -1, dy: -1).contains(frame) &&
                            viewport.insetBy(dx: -1, dy: -1).contains(expectedFrame)
                        let visibilityAccepted = !(fixture.usesPortraitControl || fixture.countryCode != nil
                                                   || fixture.scenario == "add-source") || fullyVisible
                        let nativeReport: [String: Any] = [
                            "windowPoints": [window.bounds.width, window.bounds.height],
                            "focusedType": String(describing: type(of: focused)),
                            "focusedIdentifier": identity.identifier,
                            "focusedLabel": identity.label,
                            "focusFrame": coordinates(frame),
                            "focusFrameInWindow": coordinates(frame),
                            "focusViewportInWindow": coordinates(viewport),
                            "fullyVisibleNativeFocus": fullyVisible,
                            "rawFocusFrame": coordinates(focused.frame),
                            "focusFrameConversion": native.method,
                            "focusContainerTrace": native.trace,
                            "focusAreaFraction": fraction.isFinite ? Double(fraction) : -1,
                            "boundedNativeFocus": bounded,
                            "largeEnoughNativeControl": largeEnough,
                            "minimumFocusPoints": [fixture.minimumFocusSize.width, fixture.minimumFocusSize.height],
                            "maximumFocusHeightFraction": maximumHeightFraction,
                            "expectedInitialControlIdentifier": fixture.expectedInitialControl,
                            "expectedControlIdentifierObserved": identity.identifier == fixture.expectedInitialControl,
                            "expectedControlProbeCount": probes.count,
                            "measuredControlProbeCount": measuredProbes.count,
                            "expectedControlFrameObserved": probes.count == 1 && valid(expectedFrame),
                            "expectedControlFrame": coordinates(expectedFrame),
                            "nativeFocusMatchesExpectedControl": expectedFocus,
                            "focusCoveredByExpectedControl": comparison.focusCoverage,
                            "expectedControlCoveredByFocus": comparison.controlCoverage,
                            "focusCenterDistance": comparison.centerDistance,
                            "expectedControlVisibleFraction": comparison.visibleFraction,
                            "focusProof": "UIFocusSystem.focusedItem geometry compared with a noninteractive UIKit probe laid out behind the actual control",
                            "sceneKitViewMounted": false
                        ]
                        lastObservation.merge(nativeReport) { _, new in new }
                        let key = "\(identity.identifier)|\(frame)|\(expectedFrame)|\(viewport)"
                        stableSamples = bounded && expectedFocus && largeEnough && visibilityAccepted && search.passed && country.passed && detail.passed && form.passed && banner.passed && key == precedingFocus ? stableSamples + 1 : 0
                        previousFocus = key
                        if stableSamples >= 4 {
                            var report = lastObservation
                            report["status"] = "ready"
                            report["scenario"] = fixture.scenario
                            report["selectedItemID"] = fixture.selection?.id ?? ""
                            report["requestedSeason"] = fixture.openSeason ?? 0
                            report["requestedEpisodeID"] = fixture.episodeID ?? ""
                            if fixture.usesPersistedSelection {
                                report["captureMode"] = "native tvOS Simulator; recreated library and production browsing restoration with no initial UI selection fixture"
                            } else {
                                report["captureMode"] = fixture.searchQuery == nil
                                    ? "native tvOS Simulator; measured actual initial focus"
                                    : "native tvOS Simulator; production search-submit hook and measured actual resulting focus"
                            }
                            report["physicalRemoteNavigationTested"] = false
                            report["mediaPlaybackTested"] = false
                            report["mediaFixture"] = "Local artwork only; no playable URL. Trailer and live playback are not exercised."
                            try write(report)
                            print("FLUX_TV_UI_READY \(fixture.scenario): native focus=\(identity.identifier), frame=\(frame), measured control=\(expectedFrame).")
                            print("No account, credential, network media, SceneKit surface or remote input injection was used.")
                            return
                        }
                    }
                }
                try await Task.sleep(nanoseconds: 250_000_000)
            }
            var report = lastObservation
            report["status"] = "failed"
            report["scenario"] = fixture.scenario
            report["error"] = "No stable native focus matching the measured expected control, fully visible portrait viewport and scenario assertions within 22 seconds."
            try write(report)
            fputs("FAIL: tvOS UI did not reach the expected stable bounded native focus.\n", stderr)
        } catch is CancellationError {
            // The script treats a cancelled/unmounted screen without a ready
            // marker as failure and preserves its compositor screenshot.
            fputs("FAIL: tvOS capture task was cancelled before readiness.\n", stderr)
        } catch {
            try? write(["status": "failed", "scenario": fixture.scenario, "error": String(describing: error)])
            fputs("FAIL: \(error)\n", stderr)
        }
    }

    private static func searchEvidence(fixture: TVCatalogFixture, library: IPTVLibrary,
                                       observations: [CatalogSearchFocusSnapshot]) -> (passed: Bool, report: [String: Any]) {
        guard let query = fixture.searchQuery, let expectedFocus = fixture.expectedSearchFocus else {
            return (true, ["searchSubmissionTested": false])
        }
        let deferred = observations.contains { $0.query == query && $0.filtering && $0.pending }
        let last = observations.last
        let settled = last?.query == query && last?.filtering == false && last?.pending == false && last?.focusID == expectedFocus
        let resultIDs = library.catalogResults.all.items.map(\.id)
        let resultsMatch = library.search == query && !library.isFiltering && resultIDs == fixture.expectedSearchResults
        let rejectedEarlyOK = !observations.isEmpty && observations.allSatisfy { $0.heldItemID == nil } && library.selectedItemID == nil
        let trace: [[String: Any]] = observations.map {
            ["query": $0.query, "focusID": $0.focusID ?? "", "filtering": $0.filtering,
             "pending": $0.pending, "heldItemID": $0.heldItemID ?? ""]
        }
        return (deferred && settled && resultsMatch && rejectedEarlyOK, [
            "searchSubmissionTested": true,
            "searchQuery": query,
            "searchDeferredDuringFiltering": deferred,
            "searchSettledOnExpectedTarget": settled,
            "searchResultsMatch": resultsMatch,
            "searchExpectedFocusID": expectedFocus,
            "searchResultIDs": resultIDs,
            "searchRejectedStaleActivation": rejectedEarlyOK,
            "searchObservations": trace,
            "searchSubmissionMethod": "Existing fixture hook invokes the production submit handler and immediate activation while the real debounced filter runs; no Siri Remote input is injected"
        ])
    }

    private static func countryEvidence(fixture: TVCatalogFixture, library: IPTVLibrary)
        -> (passed: Bool, report: [String: Any]) {
        guard let expectedCode = fixture.countryCode else { return (true, ["countryFilterTested": false]) }
        let resultIDs = library.catalogResults.all.items.map(\.id)
        let counts = Dictionary(uniqueKeysWithValues: library.liveCountries.map { ($0.code, $0.channelCount) })
        let expectedCounts = ["FR": 3, "ES": 2, "GB": 2, LiveCountry.unknownCode: 2]
        let countryMatches = library.contentKind == .live && library.countryCode == expectedCode
        let resultsMatch = !library.isFiltering && resultIDs == fixture.expectedCountryResults
        let countriesMatch = counts == expectedCounts
        let expectedGroup: String? = fixture.restoresBrowsing ? "[FR] Cinéma" : nil
        let expectedGroupSearch = fixture.restoresBrowsing ? "Cin" : ""
        // A section keeps no query, even one an older version saved with it.
        let restorationMatches = !fixture.usesPersistedSelection ||
            (library.group == expectedGroup && library.search.isEmpty && !library.searchScreen &&
             library.groupSearch == expectedGroupSearch &&
             library.browseItemID == fixture.selection?.id && library.catalogPage == 0)
        return (countryMatches && resultsMatch && countriesMatch && restorationMatches, [
            "countryFilterTested": true,
            "countryExpectedCode": expectedCode,
            "countryCode": library.countryCode ?? "",
            "countrySelectionMatches": countryMatches,
            "countryFilteringSettled": !library.isFiltering,
            "countryResultIDs": resultIDs,
            "countryExpectedResultIDs": fixture.expectedCountryResults,
            "countryResultsMatch": resultsMatch,
            "countryAvailableCounts": counts,
            "countryAvailableCountsMatch": countriesMatch,
            "countryUnclassifiedRetained": counts[LiveCountry.unknownCode] == 2,
            "countryPickerRequested": fixture.opensCountryPicker,
            "browsingUIRestorationTested": fixture.usesPersistedSelection,
            "browsingUIRestorationMatches": fixture.usesPersistedSelection && restorationMatches,
            "browsingUISelectionSeeded": !fixture.usesPersistedSelection && fixture.selection != nil,
            "browsingRestoredGroup": library.group ?? "",
            "browsingRestoredSearch": library.search,
            "browsingRestoredGroupSearch": library.groupSearch,
            "browsingRestoredItemID": library.browseItemID ?? "",
            "countryFilterMethod": "A single mixed catalogue is filtered by the production IPTVLibrary.countryCode; expected IDs are checked after asynchronous filtering."
        ])
    }

    /// Exercise storage and restoration through the real library in a second,
    /// isolated fixture. The on-screen country picker remains untouched. A
    /// section keeps its country, its group, the search among its groups and
    /// its title. A query is a screen of its own, over the whole kind: it
    /// leaves the section as it found it, and no section keeps it.
    private static func verifyBrowsingPersistence(fixture: TVCatalogFixture) async throws -> [String: Any] {
        let suiteName = "\(bundleID).BrowsingPersistence.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw TVCatalogUIFailure.assertion("Cannot create an isolated browsing preferences suite.")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let original = IPTVLibrary(catalogFixture: fixture.source, items: fixture.items, kind: .live,
                                   browsingDefaults: defaults)
        original.countryCode = "FR"
        original.group = "[FR] Cinéma"
        original.groupSearch = "Cin"
        try await awaitFilter(original, stage: "initial country/category selection")
        original.browseItemID = "fixture-country-fr-1"

        let french = ["fixture-country-fr-0", "fixture-country-fr-1", "fixture-country-fr-2"]
        func requireRestored(_ candidate: IPTVLibrary, stage: String) throws {
            try require(candidate.contentKind == .live && candidate.countryCode == "FR" &&
                        candidate.group == "[FR] Cinéma" && candidate.search.isEmpty && !candidate.searchScreen &&
                        candidate.groupSearch == "Cin" && candidate.browseItemID == "fixture-country-fr-1" &&
                        candidate.catalogPage == 0 && !candidate.isFiltering,
                        "Browsing preferences were not restored after \(stage).")
            try require(candidate.catalogResults.all.items.map(\.id) == french,
                        "The restored filters produced the wrong channels after \(stage).")
        }
        try requireRestored(original, stage: "initial selection")

        // A query opens the screen of the search, over all the channels: the
        // country of the section does not narrow it, and stays the section's.
        original.search = "UK"
        try await awaitFilter(original, stage: "search over the television")
        try require(original.searchScreen && original.countryCode == "FR" &&
                    original.catalogResults.all.items.map(\.id) == ["fixture-country-gb-0", "fixture-country-gb-1"],
                    "The search did not look through the whole television.")
        // Leaving it gives the section back as it was, without the query.
        original.leaveSearchScreen()
        try await awaitFilter(original, stage: "leaving the search")
        try requireRestored(original, stage: "leaving the search")

        original.contentKind = .movie
        try await awaitFilter(original, stage: "switch to Films")
        try require(original.countryCode == nil && original.group == nil && original.search.isEmpty,
                    "TV filters leaked into a previously unused Films context.")
        original.contentKind = .live
        try await awaitFilter(original, stage: "return from Films")
        try requireRestored(original, stage: "return from Films")

        original.flushBrowsingPreferences()
        try require(defaults.data(forKey: CatalogBrowsingPreferences.storageKey)?.isEmpty == false,
                    "No browsing preferences were written to the isolated persistent suite.")
        guard let reopenedDefaults = UserDefaults(suiteName: suiteName) else {
            throw TVCatalogUIFailure.assertion("Cannot reopen the isolated preferences suite.")
        }
        let reopened = IPTVLibrary(catalogFixture: fixture.source, items: fixture.items, kind: .live,
                                   browsingDefaults: reopenedDefaults)
        try await awaitFilter(reopened, stage: "new library instance")
        try requireRestored(reopened, stage: "new library instance reading persisted preferences")
        reopened.reloadCatalogFixture(fixture.items)
        try await awaitFilter(reopened, stage: "catalogue refresh")
        try requireRestored(reopened, stage: "catalogue refresh")
        reopened.contentKind = .movie
        try await awaitFilter(reopened, stage: "restored Films context")
        try require(reopened.search.isEmpty && reopened.countryCode == nil && !reopened.searchScreen,
                    "The Films context did not open without a query across recreation and refresh.")
        reopened.flushBrowsingPreferences()
        return [
            "browsingPersistenceTested": true,
            "browsingSectionRoundTripPassed": true,
            "browsingStoredDataObserved": true,
            "browsingRecreationPassed": true,
            "browsingRefreshPassed": true,
            "browsingMediaContextsIndependent": true,
            "browsingSearchScreenPassed": true,
            "browsingPersistenceMethod": "Separate IPTVLibrary instances share one disposable UserDefaults suite; TV country/category/category-search/item survive a search over all the channels, a Films round-trip, persisted preferences recreation and the production catalogue-install path, and no section keeps a query. No account or real source is read."
        ]
    }

    private static func awaitFilter(_ library: IPTVLibrary, stage: String) async throws {
        let deadline = Date().addingTimeInterval(4)
        while library.isFiltering {
            try Task.checkCancellation()
            try require(Date() < deadline, "Catalogue filtering did not settle during \(stage).")
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    /// The form of a source fills the screen: its last control, the button
    /// that submits it, is inside the safe area and no scroll view holds it.
    private static func sourceFormEvidence(fixture: TVCatalogFixture, window: UIWindow) -> (passed: Bool, report: [String: Any]) {
        guard fixture.scenario == "add-source" else { return (true, ["sourceFormTested": false]) }
        let probes = controlProbes(in: window).filter { $0.controlIdentifier == "source-submit" && $0.window === window }
        let frames = probes.map { $0.convert($0.bounds, to: window) }.filter { $0.width > 1 && $0.height > 1 }
        let safe = window.bounds.inset(by: window.safeAreaInsets).insetBy(dx: -1, dy: -1)
        let visible = frames.count == 1 && safe.contains(frames[0])
        let scrolls = probes.contains { probe in
            var view = probe.superview
            while let current = view {
                if current is UIScrollView { return true }
                view = current.superview
            }
            return false
        }
        return (visible && !scrolls, [
            "sourceFormTested": true,
            "sourceFormSubmitProbeCount": frames.count,
            "sourceFormSubmitVisible": visible,
            "sourceFormScrolls": scrolls,
            "sourceFormSubmitFrame": frames.first.map(coordinates) ?? [],
            "sourceFormSafeArea": coordinates(safe)
        ])
    }

    /// The banner of a channel stands alone at the foot of the picture, wide
    /// enough for a name that is not cut, inside the safe area, and nothing
    /// else is drawn over the picture: no command, no card in its middle.
    private static func bannerEvidence(fixture: TVCatalogFixture, playback: PlaybackController, window: UIWindow)
        -> (passed: Bool, report: [String: Any]) {
        guard fixture.showsBanner else { return (true, ["channelBannerTested": false]) }
        let probes = controlProbes(in: window).filter { $0.window === window }
        let frames = probes.filter { $0.controlIdentifier == "player-banner" }
            .map { $0.convert($0.bounds, to: window) }.filter { $0.width > 1 && $0.height > 1 }
        let safe = window.bounds.inset(by: window.safeAreaInsets).insetBy(dx: -1, dy: -1)
        let frame = frames.first ?? .null
        let placed = frames.count == 1 && safe.contains(frame)
            && frame.width >= window.bounds.width * 0.5 && frame.height <= window.bounds.height * 0.16
            && frame.minY >= window.bounds.height * 0.7
        // The commands of the player have probes of their own.
        let commands = probes.map(\.controlIdentifier).filter { $0.hasPrefix("player-") && $0 != "player-banner" && $0 != "player-catcher" }
        let state = fixture.scenario == "player-banner-opening" ? playback.opening && !playback.isPlaying : playback.isPlaying && !playback.opening
        return (placed && commands.isEmpty && state, [
            "channelBannerTested": true,
            "channelBannerProbeCount": frames.count,
            "channelBannerFrame": frames.first.map(coordinates) ?? [],
            "channelBannerInsideSafeArea": frames.count == 1 && safe.contains(frame),
            "channelBannerPlaced": placed,
            "channelBannerCommandsOnScreen": commands,
            "channelBannerPlaybackStateMatches": state
        ])
    }

    private static func detailBoxEvidence(fixture: TVCatalogFixture, window: UIWindow)
        -> (passed: Bool, report: [String: Any]) {
        guard fixture.scenario == "movie" || fixture.scenario == "series" else { return (true, ["detailBoxTested": false]) }
        let probes = controlProbes(in: window)
        let boxes = probes.filter { $0.controlIdentifier == "media-detail-box" && $0.window === window }
        let frame = boxes.count == 1 ? boxes[0].convert(boxes[0].bounds, to: window) : CGRect.null
        let viewport = boxes.count == 1 ? visibleViewport(from: boxes[0].superview, in: window) : CGRect.null
        let large = valid(frame) && frame.width >= 200 && frame.height >= 280 && frame.width < frame.height
        let visible = valid(frame) && valid(viewport) && viewport.insetBy(dx: -1, dy: -1).contains(frame)
        let forbidden = probes.map(\.controlIdentifier).filter { $0 == "media-detail-trailer" || $0 == "media-detail-mute" }
        func playerLayers(_ layer: CALayer) -> Int {
            (layer is AVPlayerLayer ? 1 : 0) + (layer.sublayers ?? []).reduce(0) { $0 + playerLayers($1) }
        }
        func webViews(_ view: UIView) -> Int {
            (String(describing: type(of: view)).contains("WKWebView") ? 1 : 0) + view.subviews.reduce(0) { $0 + webViews($1) }
        }
        let players = playerLayers(window.layer), web = webViews(window)
        return (boxes.count == 1 && large && visible && forbidden.isEmpty && players == 0 && web == 0, [
            "detailBoxTested": true, "detailBoxProbeCount": boxes.count,
            "detailBoxFrame": coordinates(frame), "detailBoxLargeEnough": large, "detailBoxFullyVisible": visible,
            "detailTrailerControlIDs": forbidden, "detailPlayerLayerCount": players, "detailWebViewCount": web
        ])
    }

    private static func controlProbes(in view: UIView) -> [TVCatalogControlProbeView] {
        guard !view.isHidden, view.alpha > 0.01 else { return [] }
        var result: [TVCatalogControlProbeView] = []
        if let probe = view as? TVCatalogControlProbeView { result.append(probe) }
        for child in view.subviews { result.append(contentsOf: controlProbes(in: child)) }
        return result
    }

    private static func visibleViewport(from view: UIView?, in window: UIWindow) -> CGRect {
        var visible = window.safeAreaLayoutGuide.layoutFrame.intersection(window.bounds)
        var ancestor = view
        while let candidate = ancestor {
            if candidate.isHidden || candidate.alpha <= 0.01 { return .null }
            if candidate.clipsToBounds {
                visible = visible.intersection(candidate.convert(candidate.bounds, to: window))
            }
            ancestor = candidate.superview
        }
        return visible
    }

    /// UIFocusItem.frame belongs to its containing UIFocusItemContainer, not
    /// necessarily the window. The parent focus environment supplies that
    /// container for its child items. SwiftUI can expose different responder
    /// proxies through focusedItem and focusItems(in:), so proxy identity is
    /// not a valid way to discover the coordinate space.
    /// Resolve the nearest parent container and require its ancestry to reach
    /// this window. Never select a space by comparing with the expected probe.
    /// https://developer.apple.com/documentation/uikit/uifocusitem/frame
    /// https://developer.apple.com/documentation/uikit/uifocusenvironment/focusitemcontainer
    /// https://developer.apple.com/documentation/uikit/uifocusenvironment/parentfocusenvironment
    private static func nativeFrame(_ focused: any UIFocusItem, in window: UIWindow)
        -> (frame: CGRect, method: String, trace: [String]) {
        if let view = focused as? UIView, view.window === window {
            return (view.convert(view.bounds, to: window), "UIView.bounds converted to the active UIWindow", [])
        }
        var environment = focused.parentFocusEnvironment
        var visited: Set<ObjectIdentifier> = []
        var trace: [String] = []
        var owningContainer: (any UIFocusItemContainer)?
        var owningEnvironmentType = ""
        var belongsToWindow = false
        for _ in 0..<24 {
            guard let ancestor = environment, visited.insert(ObjectIdentifier(ancestor)).inserted else { break }
            if let view = ancestor as? UIView, view.window === window { belongsToWindow = true }
            if let container = ancestor.focusItemContainer {
                let isOwner = owningContainer == nil
                trace.append("\(type(of: ancestor)): \(type(of: container)), nearest parent container=\(isOwner)")
                if isOwner {
                    owningContainer = container
                    owningEnvironmentType = String(describing: type(of: ancestor))
                }
            } else {
                trace.append("\(type(of: ancestor)): no child focus container")
            }
            if ObjectIdentifier(ancestor) == ObjectIdentifier(window) {
                belongsToWindow = true
                break
            }
            environment = ancestor.parentFocusEnvironment
        }
        guard belongsToWindow, let container = owningContainer else {
            return (.null, "No parent focus container attached to the active UIWindow; cannot pass", trace)
        }
        let space = container.coordinateSpace
        let frame = window.convert(focused.frame, from: space)
        trace.append("Owning environment: \(owningEnvironmentType); coordinate space: \(type(of: space)); bounds=\(space.bounds); bounds in window=\(window.convert(space.bounds, from: space)); converted focus=\(frame)")
        guard valid(frame) else {
            return (.null, "The parent focus container produced an invalid native frame; cannot pass", trace)
        }
        return (frame, "Nearest parentFocusEnvironment.focusItemContainer.coordinateSpace converted to the active UIWindow", trace)
    }

    private static func valid(_ frame: CGRect) -> Bool {
        !frame.isNull && !frame.isInfinite && !frame.isEmpty &&
        frame.origin.x.isFinite && frame.origin.y.isFinite && frame.width.isFinite && frame.height.isFinite
    }

    private static func area(_ frame: CGRect) -> CGFloat { valid(frame) ? frame.width * frame.height : 0 }

    private static func coordinates(_ frame: CGRect) -> [CGFloat] {
        valid(frame) ? [frame.origin.x, frame.origin.y, frame.width, frame.height] : []
    }

    private static func compareFocus(_ focus: CGRect, with control: CGRect, in window: CGRect)
        -> (matches: Bool, focusCoverage: Double, controlCoverage: Double, centerDistance: [Double], visibleFraction: Double) {
        guard valid(focus), valid(control) else { return (false, 0, 0, [], 0) }
        let intersection = area(focus.intersection(control))
        let focusCoverage = intersection / area(focus)
        let controlCoverage = intersection / area(control)
        let dx = abs(focus.midX - control.midX), dy = abs(focus.midY - control.midY)
        let visibleFraction = area(control.intersection(window)) / area(control)
        // Small scale animations may change the outline, but cannot move its
        // centre to another button or make a large ancestor count as the item.
        let centered = dx <= max(6, control.width * 0.04) && dy <= max(6, control.height * 0.04)
        let matches = centered && focusCoverage >= 0.88 && controlCoverage >= 0.88 && visibleFraction >= 0.98
        return (matches, Double(focusCoverage), Double(controlCoverage), [Double(dx), Double(dy)], Double(visibleFraction))
    }

    private static func containsSceneKit(_ view: UIView) -> Bool {
        view is SCNView || view.subviews.contains(where: containsSceneKit)
    }

    private static func focusIdentity(_ focused: any UIFocusItem) -> (identifier: String, label: String) {
        if let element = focused as? UIAccessibilityIdentification,
           let identifier = element.accessibilityIdentifier, !identifier.isEmpty {
            let label = (focused as? UIView)?.accessibilityLabel ?? (focused as? UIAccessibilityElement)?.accessibilityLabel ?? ""
            return (identifier, label)
        }
        var view = focused as? UIView
        var label = view?.accessibilityLabel ?? ""
        while let candidate = view {
            if label.isEmpty { label = candidate.accessibilityLabel ?? "" }
            if let identifier = candidate.accessibilityIdentifier, !identifier.isEmpty { return (identifier, label) }
            view = candidate.superview
        }
        return ("", label)
    }

    private static func write(_ report: [String: Any]) throws {
        try FileManager.default.createDirectory(at: reportURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: reportURL, options: .atomic)
    }

    static func fail(_ error: Error) -> Never {
        try? write(["status": "failed", "scenario": ProcessInfo.processInfo.environment["FLUX_UI_SCENARIO"] ?? "", "error": String(describing: error)])
        fputs("FAIL: \(error)\n", stderr)
        exit(1)
    }

    static func require(_ value: Bool, _ message: String) throws {
        if !value { throw TVCatalogUIFailure.assertion(message) }
    }
}
#endif
