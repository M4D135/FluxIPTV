#if os(tvOS) && FLUX_CATALOG_UI_TESTING
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
            if fixture.scenario == "welcome" {
                library = IPTVLibrary(emptyCatalogFixture: .live)
                try TVCatalogCapture.require(library.sources.isEmpty, "The welcome fixture unexpectedly contains a source.")
            } else if fixture.restoresBrowsing {
                let restored = try TVCatalogCapture.makeRestoredBrowsingLibrary(fixture: fixture)
                library = restored.library
                restoredDefaultsSuite = restored.suiteName
                // A restored nonempty search genuinely starts asynchronous
                // filtering. Only this scenario accepts that initial state.
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
            }
            self.fixture = fixture
            self.restoredDefaultsSuite = restoredDefaultsSuite
            _library = StateObject(wrappedValue: library)
            _playback = StateObject(wrappedValue: PlaybackController())
        } catch {
            TVCatalogCapture.fail(error)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(fixtureSelection: fixture.restoresBrowsing ? nil : fixture.selection, fixtureSeasons: fixture.seasons,
                        fixtureOpenSeason: fixture.openSeason, fixtureEpisodeID: fixture.episodeID,
                        fixtureOpenItem: fixture.scenario == "movie",
                        fixtureSearchSubmission: fixture.searchQuery,
                        fixtureSearchObservation: { searchObservations.snapshots.append($0) },
                        fixtureOpenCountries: fixture.opensCountryPicker,
                        fixtureRestoreBrowsing: fixture.restoresBrowsing)
                .environmentObject(library)
                .environmentObject(playback)
                .preferredColorScheme(.dark)
                .task {
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

@MainActor private struct TVCatalogFixture {
    let scenario: String
    let source: IPTVSource
    let items: [IPTVItem]
    let kind: IPTVMediaKind
    let selection: IPTVItem?
    let seasons: [IPTVSeason]
    let openSeason: Int?
    let episodeID: String?

    var expectedInitialControl: String {
        switch scenario {
        case "live": return "live-channel-fixture-live-0"
        case "live-fr": return "live-channel-fixture-country-fr-0"
        case "live-es": return "live-channel-fixture-country-es-0"
        case "live-restored": return "live-channel-fixture-country-fr-1"
        case "country-picker": return "live-country-option-FR"
        case "movies": return "catalog-card-fixture-movie-1"
        case "search-empty": return "navigation-tab-movie"
        case "search-result": return "catalog-card-fixture-movie-0"
        case "welcome": return "welcome-load-source"
        default: return "media-detail-play"
        }
    }

    var minimumFocusSize: CGSize {
        switch scenario {
        case "live", "live-fr", "live-es", "live-restored": return CGSize(width: 300, height: 230)
        case "country-picker": return CGSize(width: 240, height: 54)
        case "movies", "search-result": return CGSize(width: 240, height: 350)
        case "search-empty": return CGSize(width: 150, height: 112)
        case "welcome": return CGSize(width: 300, height: 72)
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
        case "search-empty": return "tab-movie"
        case "search-result": return "fixture-movie-0"
        default: return nil
        }
    }

    var expectedSearchResults: [String] {
        scenario == "search-result" ? ["fixture-movie-0"] : []
    }

    var usesPortraitControl: Bool { scenario == "movies" || scenario == "search-result" }

    var countryCode: String? {
        switch scenario {
        case "live-fr", "country-picker", "live-restored": return "FR"
        case "live-es": return "ES"
        default: return nil
        }
    }

    var opensCountryPicker: Bool { scenario == "country-picker" }
    var restoresBrowsing: Bool { scenario == "live-restored" }

    var expectedCountryResults: [String] {
        if restoresBrowsing { return ["fixture-country-fr-1"] }
        switch countryCode {
        case "FR": return ["fixture-country-fr-0", "fixture-country-fr-1", "fixture-country-fr-2"]
        case "ES": return ["fixture-country-es-0", "fixture-country-es-1"]
        default: return []
        }
    }

    static func make() throws -> TVCatalogFixture {
        let scenario = ProcessInfo.processInfo.environment["FLUX_UI_SCENARIO"] ?? ""
        try TVCatalogCapture.require(["movie", "movies", "series", "live", "welcome", "search-empty", "search-result",
                                      "live-fr", "live-es", "country-picker", "live-restored"].contains(scenario),
                                     "FLUX_UI_SCENARIO must name a supported catalogue, detail, welcome or search scenario.")
        let source = IPTVSource(id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
                                name: "Catalogue local de démonstration", kind: .m3uFile)
        if scenario == "welcome" {
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
        if scenario == "live" {
            let categories = ["Généralistes", "Cinéma", "Documentaires", "Jeunesse", "Musique", "Sports"]
            let channelNames = ["Horizon", "Panorama", "Grand écran", "Découverte", "Évasion", "Scène"]
            let channels = try (0..<18).map { (index: Int) in
                let url = artworkRoot.appendingPathComponent("live-\(index).png")
                let name = "\(channelNames[index % channelNames.count]) \(index + 1)"
                cache(try artwork(width: 480, height: 270, index: index, title: name.uppercased(), subtitle: "CHAÎNE LOCALE"), at: url)
                return IPTVItem(id: "fixture-live-\(index)", sourceID: source.id, name: name,
                                group: categories[index % categories.count], logoURL: url, kind: .live,
                                directURL: nil, xtreamStreamID: nil, fileExtension: nil)
            }
            return TVCatalogFixture(scenario: scenario, source: source, items: channels, kind: .live,
                                    selection: channels[0], seasons: [], openSeason: nil, episodeID: nil)
        }
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
        let isMovie = scenario == "movie" || scenario == "movies" || scenario.hasPrefix("search-")
        return TVCatalogFixture(scenario: scenario, source: source, items: items,
                                kind: isMovie ? .movie : .series,
                                selection: isMovie ? items[1] : collection,
                                seasons: scenario == "series" ? seasons : [],
                                openSeason: scenario == "series" ? 12 : nil,
                                episodeID: scenario == "series" ? episodeID : nil)
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

    static func configureDefaults() {
        // A separate bundle in a newly created simulator has no user profiles.
        // Volatile overrides leave even that disposable persistent domain alone.
        UserDefaults.standard.setVolatileDomain([
            FluxAppearance.glassKey: true,
            FluxAppearance.artworkKey: true,
            FluxAppearance.wallpaperKey: false,
            FluxAppearance.densityKey: "cinema",
            MediaThemePreferences.tvKey: VideoClubTheme.neo90.rawValue,
            MediaThemePreferences.cinemaKey: VideoClubTheme.neo90.rawValue,
            MediaThemePreferences.seriesKey: VideoClubTheme.neo90.rawValue,
            ClubInterfaceProfile.storageKey: ClubInterfaceProfile.neoVideoClub.rawValue,
            LiveTVPreviewDelay.automaticKey: false,
            TrailerPreviewDelay.automaticKey: false
        ], forName: UserDefaults.argumentDomain)
    }

    /// Write with one real library, then recreate another from the same
    /// isolated preferences. ContentView receives no selected-item fixture;
    /// its production restore path must recover the intended native focus.
    static func makeRestoredBrowsingLibrary(fixture: TVCatalogFixture) throws
        -> (library: IPTVLibrary, suiteName: String) {
        let suiteName = "\(bundleID).RestoredUI.\(UUID().uuidString)"
        guard let storedDefaults = UserDefaults(suiteName: suiteName) else {
            throw TVCatalogUIFailure.assertion("Cannot create the isolated UI restoration suite.")
        }
        do {
            let original = IPTVLibrary(catalogFixture: fixture.source, items: fixture.items, kind: .live,
                                       browsingDefaults: storedDefaults)
            original.countryCode = "FR"
            original.group = "[FR] Cinéma"
            original.search = "Grand écran"
            original.groupSearch = "Cin"
            original.browseItemID = "fixture-country-fr-1"
            original.flushBrowsingPreferences()
            guard let data = storedDefaults.data(forKey: CatalogBrowsingPreferences.storageKey), !data.isEmpty else {
                throw TVCatalogUIFailure.assertion("UI restoration has no persisted browsing state to read.")
            }
            let saved = CatalogBrowsingPreferences.decoded(data).state(for: fixture.source.id, kind: .live)
            try require(saved.countryCode == "FR" && saved.group == "[FR] Cinéma" && saved.search == "Grand écran" &&
                        saved.groupSearch == "Cin" && saved.browseItemID == "fixture-country-fr-1",
                        "The initial library did not persist the exact UI restoration fixture.")
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
                try require(playback.playingItem == nil && playback.player.currentItem == nil,
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
                        let bounded = valid(frame) && fraction.isFinite &&
                            fraction < 0.18 && frame.width < window.bounds.width * 0.75 && frame.height < window.bounds.height * maximumHeightFraction
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
                        let visibilityAccepted = !(fixture.usesPortraitControl || fixture.countryCode != nil) || fullyVisible
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
                        stableSamples = bounded && expectedFocus && largeEnough && visibilityAccepted && search.passed && country.passed && key == precedingFocus ? stableSamples + 1 : 0
                        previousFocus = key
                        if stableSamples >= 4 {
                            var report = lastObservation
                            report["status"] = "ready"
                            report["scenario"] = fixture.scenario
                            report["selectedItemID"] = fixture.selection?.id ?? ""
                            report["requestedSeason"] = fixture.openSeason ?? 0
                            report["requestedEpisodeID"] = fixture.episodeID ?? ""
                            if fixture.restoresBrowsing {
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
        let restorationMatches = !fixture.restoresBrowsing ||
            (library.group == "[FR] Cinéma" && library.search == "Grand écran" && library.groupSearch == "Cin" &&
             library.browseItemID == "fixture-country-fr-1" && library.catalogPage == 0)
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
            "browsingUIRestorationTested": fixture.restoresBrowsing,
            "browsingUIRestorationMatches": fixture.restoresBrowsing && restorationMatches,
            "browsingUISelectionSeeded": !fixture.restoresBrowsing && fixture.selection != nil,
            "browsingRestoredGroup": library.group ?? "",
            "browsingRestoredSearch": library.search,
            "browsingRestoredGroupSearch": library.groupSearch,
            "browsingRestoredItemID": library.browseItemID ?? "",
            "countryFilterMethod": "A single mixed catalogue is filtered by the production IPTVLibrary.countryCode; expected IDs are checked after asynchronous filtering."
        ])
    }

    /// Exercise storage and restoration through the real library in a second,
    /// isolated fixture. The on-screen country picker remains untouched.
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
        original.search = "Grand écran"
        original.groupSearch = "Cin"
        try await awaitFilter(original, stage: "initial country/category/search selection")
        original.browseItemID = "fixture-country-fr-1"

        func requireRestored(_ candidate: IPTVLibrary, stage: String) throws {
            try require(candidate.contentKind == .live && candidate.countryCode == "FR" &&
                        candidate.group == "[FR] Cinéma" && candidate.search == "Grand écran" &&
                        candidate.groupSearch == "Cin" && candidate.browseItemID == "fixture-country-fr-1" &&
                        candidate.catalogPage == 0 && !candidate.isFiltering,
                        "Browsing preferences were not restored after \(stage).")
            try require(candidate.catalogResults.all.items.map(\.id) == ["fixture-country-fr-1"],
                        "The restored filters produced the wrong channels after \(stage).")
        }
        try requireRestored(original, stage: "initial selection")
        original.contentKind = .movie
        try await awaitFilter(original, stage: "switch to Films")
        try require(original.countryCode == nil && original.group == nil && original.search.isEmpty,
                    "TV filters leaked into a previously unused Films context.")
        original.search = "choix de film"
        try await awaitFilter(original, stage: "separate Films search")
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
        try require(reopened.search == "choix de film" && reopened.countryCode == nil,
                    "The separate Films search was not preserved across recreation and refresh.")
        reopened.flushBrowsingPreferences()
        return [
            "browsingPersistenceTested": true,
            "browsingSectionRoundTripPassed": true,
            "browsingStoredDataObserved": true,
            "browsingRecreationPassed": true,
            "browsingRefreshPassed": true,
            "browsingMediaContextsIndependent": true,
            "browsingPersistenceMethod": "Separate IPTVLibrary instances share one disposable UserDefaults suite; TV country/category/search/category-search/item survive Films round-trip, persisted preferences recreation and the production catalogue-install path. No account or real source is read."
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
