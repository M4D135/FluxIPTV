#if os(macOS) && FLUX_CATALOG_UI_TESTING
import AppKit
import CoreGraphics
import CoreText
import Darwin
import Foundation
import ImageIO
import QuartzCore
import SwiftUI
import UniformTypeIdentifiers

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
                print("PASS: real ContentView TV, DVD/VHS catalogue, twelve-season shelf and open-season Dock rendered nonempty native captures.")
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
                                  details: IPTVDetails(year: year)))
        }
        let seriesArtwork = artworkRoot.appendingPathComponent("series.png")
        cache(try fixtureArtwork(width: 360, height: 540, index: 7, title: "LES SAISONS", subtitle: "JAQUETTE LOCALE · 2014"), at: seriesArtwork)
        let collection = IPTVItem(id: "fixture-series", sourceID: source.id, name: "Les saisons", group: "Séries · Drame",
                                  logoURL: seriesArtwork, kind: .series, directURL: nil, xtreamStreamID: nil, fileExtension: nil,
                                  isSeriesCollection: true,
                                  details: IPTVDetails(synopsis: "Une description IPTV locale accompagne ce rayon de douze saisons. Chaque boîtier ouvre les épisodes de la saison choisie.", year: "2014", genre: "Drame"))
        items.append(collection)
        let seasons = (1...12).map { number in
            IPTVSeason(number: number, episodes: (1...16).map { episode in
                IPTVItem(id: "fixture-series-s\(number)-e\(episode)", sourceID: source.id,
                         name: "Épisode \(episode)", group: collection.group, logoURL: nil,
                         kind: .series, directURL: nil, xtreamStreamID: nil, fileExtension: nil,
                         details: IPTVDetails(synopsis: "Épisode de démonstration locale.", year: "2014", duration: "42 min"),
                         seasonNumber: number, episodeNumber: episode)
            })
        }
        let playback = PlaybackController()
        defer { playback.stop(); ArtworkLoader.cache.removeAllObjects() }
        let scenarios: [(kind: IPTVMediaKind, filename: String, season: Int?)] = [
            (.live, "catalog-tv.png", nil),
            (.movie, "catalog-dvd-vhs.png", nil),
            (.series, "series-seasons.png", nil),
            (.series, "series-season-dock.png", 12)
        ]
        var captureFailures: [String] = []
        for scenario in scenarios {
            let kind = scenario.kind
            let library = IPTVLibrary(catalogFixture: source, items: items, kind: kind)
            let selected = library.catalogResults.all.items.first
            try require(selected != nil && !library.isLoading && !library.isFiltering, "Fixture catalogue was not installed synchronously.")
            let root = ContentView(fixtureSelection: selected, fixtureSeasons: kind == .series ? seasons : [],
                                   fixtureOpenSeason: scenario.season, fixtureEpisodeID: scenario.season == nil ? nil : "fixture-series-s12-e15")
                .environmentObject(library).environmentObject(playback)
                .preferredColorScheme(.dark)
                .environment(\.scenePhase, .active)
            let host = NSHostingView(rootView: root)
            let size = CGSize(width: 1440, height: 900)
            let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: 30, y: 30), size: size),
                                  styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.title = kind == .live ? "FluxIPTV — catalogue TV local" : kind == .movie ? "FluxIPTV — rayon DVD/VHS local" : scenario.season == nil ? "FluxIPTV — douze saisons" : "FluxIPTV — saison 12, épisode 15 et Dock"
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
            do { try await capture(host, window: window, to: output.appendingPathComponent(filename)) }
            catch { captureFailures.append("\(filename): \(error)") }
            window.orderOut(nil)
            window.contentView = nil
            window.close()
            await Task.yield()
        }
        try require(captureFailures.isEmpty, captureFailures.joined(separator: "\n"))
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
