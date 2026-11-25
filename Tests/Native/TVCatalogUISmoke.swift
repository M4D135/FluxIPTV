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

/// The script substitutes this entry point in a temporary repository copy. It
/// hosts the real application views in a booted tvOS Simulator, including the
/// system focus engine. It never loads saved accounts or remote media.
@main @MainActor private struct TVCatalogUISmoke: App {
    @StateObject private var library: IPTVLibrary
    @StateObject private var playback: PlaybackController
    private let fixture: TVCatalogFixture

    init() {
        do {
            try TVCatalogCapture.require(Bundle.main.bundleIdentifier == TVCatalogCapture.bundleID,
                                         "Run this fixture through scripts/test-tvos-catalog-ui.sh.")
            TVCatalogCapture.configureDefaults()
            let fixture = try TVCatalogFixture.make()
            let library: IPTVLibrary
            if fixture.scenario == "welcome" {
                library = IPTVLibrary(emptyCatalogFixture: .live)
                try TVCatalogCapture.require(library.sources.isEmpty, "The welcome fixture unexpectedly contains a source.")
            } else {
                library = IPTVLibrary(catalogFixture: fixture.source, items: fixture.items, kind: fixture.kind)
                try TVCatalogCapture.require(!library.isLoading && !library.isFiltering &&
                                             library.catalogItem(id: fixture.selection?.id) != nil,
                                             "The local catalogue was not installed synchronously.")
            }
            self.fixture = fixture
            _library = StateObject(wrappedValue: library)
            _playback = StateObject(wrappedValue: PlaybackController())
        } catch {
            TVCatalogCapture.fail(error)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(fixtureSelection: fixture.selection, fixtureSeasons: fixture.seasons,
                        fixtureOpenSeason: fixture.openSeason, fixtureEpisodeID: fixture.episodeID,
                        fixtureOpenItem: fixture.kind == .movie)
                .environmentObject(library)
                .environmentObject(playback)
                .preferredColorScheme(.dark)
                .task { await TVCatalogCapture.awaitInitialFocus(fixture: fixture, playback: playback) }
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
        case "welcome": return "welcome-load-source"
        default: return "media-detail-play"
        }
    }

    var minimumFocusSize: CGSize {
        switch scenario {
        case "live": return CGSize(width: 300, height: 230)
        case "welcome": return CGSize(width: 300, height: 72)
        default: return CGSize(width: 180, height: 64)
        }
    }

    static func make() throws -> TVCatalogFixture {
        let scenario = ProcessInfo.processInfo.environment["FLUX_UI_SCENARIO"] ?? ""
        try TVCatalogCapture.require(["movie", "series", "live", "welcome"].contains(scenario),
                                     "FLUX_UI_SCENARIO must be movie, series, live or welcome.")
        let source = IPTVSource(id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
                                name: "Catalogue local de démonstration", kind: .m3uFile)
        if scenario == "welcome" {
            return TVCatalogFixture(scenario: scenario, source: source, items: [], kind: .live,
                                    selection: nil, seasons: [], openSeason: nil, episodeID: nil)
        }
        let artworkRoot = FileManager.default.temporaryDirectory.appendingPathComponent("FluxTVUIArtwork", isDirectory: true)
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
        return TVCatalogFixture(scenario: scenario, source: source, items: items,
                                kind: scenario == "movie" ? .movie : .series,
                                selection: scenario == "movie" ? items[1] : collection,
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

    static func awaitInitialFocus(fixture: TVCatalogFixture, playback: PlaybackController) async {
        do {
            // Wait for real SwiftUI tasks and the native compositor, not a
            // synthetic scenePhase override or an image-renderer snapshot.
            try await Task.sleep(nanoseconds: 2_000_000_000)
            var previousFocus = "", stableSamples = 0
            var lastObservation: [String: Any] = [:]
            for _ in 0..<80 {
                try Task.checkCancellation()
                try require(playback.playingItem == nil && playback.player.currentItem == nil,
                            "The visual fixture unexpectedly started main playback.")
                let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                    .filter { $0.activationState == .foregroundActive }.flatMap(\.windows)
                if let window = windows.first(where: { $0.isKeyWindow && !$0.isHidden }),
                   window.bounds.width > 800, window.bounds.height > 400 {
                    try require(!containsSceneKit(window), "A SceneKit view is still mounted in the full-screen detail hierarchy.")
                    if let focused = UIFocusSystem.focusSystem(for: window)?.focusedItem {
                        let frame = focused.frame
                        let windowArea = window.bounds.width * window.bounds.height
                        let fraction = frame.width * frame.height / windowArea
                        let bounded = !frame.isEmpty && !frame.isInfinite && !frame.isNull && fraction.isFinite &&
                            fraction < 0.18 && frame.width < window.bounds.width * 0.75 && frame.height < window.bounds.height * 0.45
                        let identity = focusIdentity(focused)
                        // Some SwiftUI focus items expose an accessibility ID
                        // directly, others only their UIKit geometry. An ID,
                        // when exposed, must match the intended initial control.
                        let expectedFocus = identity.identifier.isEmpty || identity.identifier == fixture.expectedInitialControl
                        let largeEnough = frame.width >= fixture.minimumFocusSize.width && frame.height >= fixture.minimumFocusSize.height
                        lastObservation = [
                            "windowPoints": [window.bounds.width, window.bounds.height],
                            "focusedType": String(describing: type(of: focused)),
                            "focusedIdentifier": identity.identifier,
                            "focusedLabel": identity.label,
                            "focusFrame": [frame.origin.x, frame.origin.y, frame.width, frame.height],
                            "focusAreaFraction": fraction.isFinite ? Double(fraction) : -1,
                            "boundedNativeFocus": bounded,
                            "largeEnoughNativeControl": largeEnough,
                            "minimumFocusPoints": [fixture.minimumFocusSize.width, fixture.minimumFocusSize.height],
                            "expectedInitialControlIdentifier": fixture.expectedInitialControl,
                            "expectedControlIdentifierObserved": identity.identifier == fixture.expectedInitialControl,
                            "sceneKitViewMounted": false
                        ]
                        let key = "\(identity.identifier)|\(frame)"
                        stableSamples = bounded && expectedFocus && largeEnough && key == previousFocus ? stableSamples + 1 : 0
                        previousFocus = key
                        if stableSamples >= 4 {
                            var report = lastObservation
                            report["status"] = "ready"
                            report["scenario"] = fixture.scenario
                            report["selectedItemID"] = fixture.selection?.id ?? ""
                            report["requestedSeason"] = fixture.openSeason ?? 0
                            report["requestedEpisodeID"] = fixture.episodeID ?? ""
                            report["captureMode"] = "native tvOS Simulator; actual initial focus only"
                            report["mediaPlaybackTested"] = false
                            report["mediaFixture"] = "Local artwork only; no playable URL. Trailer and live playback are not exercised."
                            try write(report)
                            print("FLUX_TV_UI_READY \(fixture.scenario): native focus=\(identity.identifier), frame=\(frame).")
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
            report["error"] = "No stable native focus on the expected bounded, sufficiently large control within 22 seconds."
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
