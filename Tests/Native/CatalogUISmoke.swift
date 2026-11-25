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

/// Measures the actual sleeve without contributing accessibility or input.
struct CatalogDetailBoxFrameProbe: NSViewRepresentable {
    func makeNSView(context: Context) -> CatalogDetailBoxProbeView {
        let view = CatalogDetailBoxProbeView(frame: .zero)
        view.setAccessibilityElement(false)
        return view
    }
    func updateNSView(_ view: CatalogDetailBoxProbeView, context: Context) {}
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: CatalogDetailBoxProbeView, context: Context) -> CGSize? {
        guard let width = proposal.width, let height = proposal.height else { return nil }
        return CGSize(width: width, height: height)
    }
}

final class CatalogDetailBoxProbeView: NSView {
    override var acceptsFirstResponder: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
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
            try? await Task.sleep(nanoseconds: 60_000_000_000)
            fputs("FAIL: catalogue UI smoke exceeded its 60-second rendering deadline.\n", stderr)
            exit(1)
        }
        application.run()
    }

    @MainActor private static func configureDefaults() {
        // This dedicated bundle has a separate preferences domain from FluxIPTV.
        UserDefaults.standard.removePersistentDomain(forName: bundleID)
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
            LiveTVPreviewDelay.storageKey: LiveTVPreviewDelay.three.rawValue,
            TrailerPreviewDelay.automaticKey: false
        ], forName: UserDefaults.argumentDomain)
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
        let scenarios: [(kind: IPTVMediaKind, filename: String, season: Int?, detail: Bool)] = [
            (.live, "catalog-tv.png", nil, false),
            (.movie, "catalog-dvd-vhs.png", nil, false),
            (.movie, "movie-detail.png", nil, true),
            (.series, "series-seasons.png", nil, false),
            (.series, "series-episode-detail.png", 12, true)
        ]
        var captureFailures: [String] = []
        for scenario in scenarios {
            let kind = scenario.kind
            let library = IPTVLibrary(catalogFixture: source, items: items, kind: kind)
            let selected = library.catalogResults.all.items.first
            try require(selected != nil && !library.isLoading && !library.isFiltering, "Fixture catalogue was not installed synchronously.")
            let root = ContentView(fixtureSelection: selected, fixtureSeasons: kind == .series ? seasons : [],
                                   fixtureOpenSeason: scenario.season, fixtureEpisodeID: scenario.season == nil ? nil : restoredEpisodeID, fixtureOpenItem: scenario.detail)
                .environmentObject(library).environmentObject(playback)
                .preferredColorScheme(.dark)
                .environment(\.scenePhase, .active)
            let host = NSHostingView(rootView: root)
            let size = CGSize(width: 1440, height: 900)
            let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: 30, y: 30), size: size),
                                  styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.title = kind == .live ? "FluxIPTV — catalogue TV local" : kind == .movie ? (scenario.detail ? "FluxIPTV — fiche film plein écran" : "FluxIPTV — rayon DVD/VHS local") : scenario.season == nil ? "FluxIPTV — douze saisons" : "FluxIPTV — fiche saison 12, épisode 15"
            window.appearance = NSAppearance(named: .darkAqua)
            window.contentView = host
            host.frame = CGRect(origin: .zero, size: size)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            // Let actual SwiftUI tasks fill artwork and the bundled room image,
            // then let the native compositor settle before caching the view.
            try await Task.sleep(nanoseconds: 1_500_000_000)
            if scenario.season != nil {try await Task.sleep(nanoseconds: 1_500_000_000)}
            host.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            CATransaction.flush()
            try await Task.sleep(nanoseconds: 300_000_000)
            try require(playback.playingItem == nil && playback.player.currentItem == nil, "A visual capture unexpectedly started main playback.")
            let filename = scenario.filename
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
        // Query the native accessibility objects, including SwiftUI's virtual
        // children. Requiring Play and the box prevents an empty tree passing.
        var pending: [NSObject] = [host], visited: Set<ObjectIdentifier> = [], identifiers: Set<String> = []
        while let node = pending.popLast(), visited.count < 4096 {
            guard visited.insert(ObjectIdentifier(node)).inserted else { continue }
            let identifier = NSSelectorFromString("accessibilityIdentifier")
            if node.responds(to: identifier), let value = node.perform(identifier)?.takeUnretainedValue() as? String {
                identifiers.insert(value)
            }
            let children = NSSelectorFromString("accessibilityChildren")
            if node.responds(to: children), let values = node.perform(children)?.takeUnretainedValue() as? [NSObject] {
                pending.append(contentsOf: values)
            }
            if let view = node as? NSView { pending.append(contentsOf: view.subviews) }
        }
        let nativeViews = views(host)
        let boxes = nativeViews.compactMap { $0 as? CatalogDetailBoxProbeView }.filter { !$0.isHiddenOrHasHiddenAncestor && $0.window === host.window }
        let frame = boxes.count == 1 ? boxes[0].convert(boxes[0].bounds, to: host) : CGRect.zero
        let visible = boxes.count == 1 ? boxes[0].convert(boxes[0].visibleRect, to: host) : CGRect.zero
        let large = frame.width >= 200 && frame.height >= 280 && frame.width < frame.height
        let fullyVisible = !frame.isEmpty && visible.insetBy(dx: -1, dy: -1).contains(frame) && host.bounds.insetBy(dx: -1, dy: -1).contains(frame)
        let forbidden = identifiers.filter { $0 == "media-detail-trailer" || $0 == "media-detail-mute" }.sorted()
        let players = playerLayers(host.layer), webViews = nativeViews.filter { $0 is WKWebView }.count
        let report: [String: Any] = [
            "detailBoxTested": true, "detailBoxProbeCount": boxes.count,
            "detailBoxFrame": [frame.minX, frame.minY, frame.width, frame.height],
            "detailBoxLargeEnough": large, "detailBoxFullyVisible": fullyVisible,
            "detailBoxIdentifierObserved": identifiers.contains("media-detail-box"),
            "detailPlayControlObserved": identifiers.contains("media-detail-play"),
            "detailTrailerControlIDs": forbidden, "detailPlayerLayerCount": players, "detailWebViewCount": webViews
        ]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: reportURL, options: .atomic)
        try require(boxes.count == 1 && large && fullyVisible && identifiers.contains("media-detail-box") && identifiers.contains("media-detail-play") && forbidden.isEmpty && players == 0 && webViews == 0,
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
        if canCaptureWindow, FileManager.default.isExecutableFile(atPath: "/usr/sbin/screencapture") {
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
        try require(image.width >= 1400 && image.height >= 850, "Native ContentView capture is too small.")
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
