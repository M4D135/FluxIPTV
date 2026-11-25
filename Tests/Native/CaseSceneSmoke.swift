#if os(macOS) && FLUX_CASE_TESTING
import AppKit
import CoreGraphics
import CoreText
import Darwin
import Foundation
import ImageIO
import SceneKit
import UniformTypeIdentifiers

private enum CaseSceneFailure: Error, CustomStringConvertible {
    case assertion(String)
    var description: String { switch self { case .assertion(let message): return message } }
}

/// Real production SceneKit meshes, materials, textures, camera and hit testing.
/// Artwork is a deterministic local fixture; no provider or video is contacted.
@main private struct CaseSceneSmoke {
    @MainActor static func main() {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        Task { @MainActor in
            do {
                guard CommandLine.arguments.count == 2 else { throw CaseSceneFailure.assertion("Pass the capture output directory.") }
                let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
                try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
                try await run(output: output)
                print("PASS: production SceneKit DVD/VHS/season rendering, fixed shelf projection, collision clearance through animation, back projection and UV hits, open-lid preview, idle rendering and teardown.")
                print("Captured deterministic fixture artwork; no live video or remote catalogue was tested.")
                exit(0)
            } catch {
                fputs("FAIL: \(error)\n", stderr)
                exit(1)
            }
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000_000)
            fputs("FAIL: SceneKit smoke test exceeded its 120-second deadline.\n", stderr)
            exit(1)
        }
        application.run()
    }

    @MainActor private static func run(output: URL) async throws {
        try require(Bundle.main.bundleIdentifier == "com.m4d135.FluxIPTV.CaseSceneSmoke",
                    "Run the harness from scripts/test-case-scene.sh.")
        let size = CGSize(width: 1280, height: 800)
        let harness = CaseSceneSmokeHarness(size: size)
        let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: 40, y: 40), size: size),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = harness.view
        window.orderFront(nil)
        defer { harness.release(); window.orderOut(nil); window.close() }
        let cover = try fixtureImage(width: 900, height: 1280, title: "LA DERNIÈRE SÉANCE", subtitle: "JAQUETTE TEST • 2011")
        let seriesCover = try fixtureImage(width: 900, height: 1280, title: "LES SAISONS", subtitle: "SAISON 3 • 2011")
        let preview = try fixtureImage(width: 960, height: 540, title: "APERÇU", subtitle: "IMAGE FIXE DE TEST")
        let movie = item(id: "movie", name: "La dernière séance", year: "2011")
        let neighbors = (0..<4).map { item(id: "neighbor-\($0)", name: "Rayon \($0+1)", year: $0 % 2 == 0 ? "1998" : "2011") }
        var data = CasePrintData()
        data.trailerAvailable = true
        data.previewStatus = "APERÇU"
        data.descriptionText = "Cette jaquette de test conserve ses repères en haut et en bas. Le verso présente le véritable cadre vidéo et les zones imprimées de FluxIPTV."

        harness.show(item: movie, data: data, artwork: cover, previewStill: preview, yaw: -12, neighbors: neighbors)
        let front = try await capture(harness)
        let fixedCamera=harness.cameraDistance,fixedShelf=harness.neighborBounds
        try verifyGeometry(harness,camera:fixedCamera,shelf:fixedShelf,context:"DVD front",large:true)
        try require(!harness.bridge.previewBackFacing, "A new front-facing scene reported a visible case back.")
        try require(harness.bridge.previewProjection == nil, "A front-facing case produced a usable mirrored back projection.")

        harness.show(item: movie, data: data, artwork: cover, previewStill: preview, yaw: 168, focused: .trailer, neighbors: neighbors)
        let back = try await capture(harness)
        try verifyBack(harness, context: "DVD back")
        try verifyGeometry(harness,camera:fixedCamera,shelf:fixedShelf,context:"DVD back",large:true)
        try writeContactSheet([(front, "DVD — RECTO"), (back, "DVD — VERSO / APERÇU SÉLECTIONNÉ")],
                              to: output.appendingPathComponent("dvd-front-back.png"))

        // Test interpolation as well as settled poses: the old camera fitted
        // only destination corners, so a valid endpoint hid mid-turn collisions.
        var rotationCaptures:[(CGImage,String)]=[]
        let vhs=item(id:"vhs",name:"Séance VHS",year:"1998")
        for selected in [movie,vhs] {
            for (yaw,pitch) in [(0.0,0.0),(90.0,65.0),(180.0,-65.0),(270.0,80.0)] {
                harness.show(item:selected,data:data,artwork:cover,previewStill:preview,yaw:yaw,pitch:pitch,neighbors:neighbors,motion:true)
                for _ in 0..<8 {
                    try await Task.sleep(nanoseconds:35_000_000)
                    _=harness.view.snapshot()
                    try verifyGeometry(harness,camera:fixedCamera,shelf:fixedShelf,context:"\(selected.name), animated \(yaw)/\(pitch)")
                }
                let image=try await capture(harness)
                if selected.id == movie.id && yaw != 270 {rotationCaptures.append((image,"DVD — \(Int(yaw))° / \(Int(pitch))°"))}
                try verifyGeometry(harness,camera:fixedCamera,shelf:fixedShelf,context:"\(selected.name), settled \(yaw)/\(pitch)")
            }
        }
        try writeContactSheet(rotationCaptures,to:output.appendingPathComponent("fixed-shelf-rotation.png"))

        let series = item(id: "series", name: "Les saisons", year: "2011", collection: true)
        data.season = 3
        harness.show(item:series,data:data,artwork:seriesCover,previewStill:preview,yaw:-8,neighbors:neighbors)
        let closed=try await capture(harness)
        try verifyGeometry(harness,camera:fixedCamera,shelf:fixedShelf,context:"Closed season",large:true)
        data.page = .episodes
        data.episodes = (1...3).map { item(id: "episode-\($0)", name: "Épisode \($0)", year: "2011") }
        harness.show(item: series, data: data, artwork: seriesCover, previewStill: preview, yaw: -8, focused: .trailer, neighbors: neighbors,motion:true)
        for _ in 0..<10 {
            try await Task.sleep(nanoseconds:35_000_000)
            _=harness.view.snapshot()
            try verifyGeometry(harness,camera:fixedCamera,shelf:fixedShelf,context:"Opening season")
        }
        let opened = try await capture(harness)
        try require(harness.previewOnLid, "Opening the selected season left the real preview attached to the body.")
        try verifyBack(harness, context: "Open season lid")
        try verifyGeometry(harness,camera:fixedCamera,shelf:fixedShelf,context:"Open season",large:true)
        try writeContactSheet([(closed, "SAISON 3 — BOÎTIER INDIVIDUEL"), (opened, "SAISON 3 — ÉPISODES / APERÇU")],
                              to: output.appendingPathComponent("series-season-open.png"))
        for (yaw,pitch) in [(90.0,65.0),(180.0,-65.0),(270.0,80.0)] {
            harness.show(item:series,data:data,artwork:seriesCover,previewStill:preview,yaw:yaw,pitch:pitch,neighbors:neighbors,motion:true)
            for _ in 0..<8 {
                try await Task.sleep(nanoseconds:35_000_000)
                _=harness.view.snapshot()
                try verifyGeometry(harness,camera:fixedCamera,shelf:fixedShelf,context:"Open season, animated \(yaw)/\(pitch)")
            }
            _=try await capture(harness)
            try verifyGeometry(harness,camera:fixedCamera,shelf:fixedShelf,context:"Open season, settled \(yaw)/\(pitch)")
        }

        let releasedView = harness.view
        harness.release()
        try require(releasedView.scene == nil && releasedView.pointOfView == nil && !releasedView.isPlaying,
                    "Dismantling the production coordinator retained an active renderer.")
    }

    @MainActor private static func verifyGeometry(_ harness:CaseSceneSmokeHarness,camera:Double,shelf:[CGRect],context:String,large:Bool=false) throws {
        try require(abs(harness.cameraDistance-camera)<0.0001,"\(context): camera moved while manipulating the case.")
        let neighbors=harness.neighborBounds
        try require(neighbors.count == shelf.count && !neighbors.isEmpty,"\(context): shelf fixtures disappeared.")
        for (actual,expected) in zip(neighbors,shelf) {
            try require(abs(actual.minX-expected.minX)<0.15 && abs(actual.minY-expected.minY)<0.15 && abs(actual.width-expected.width)<0.15 && abs(actual.height-expected.height)<0.15,
                        "\(context): a neighbor moved or changed projected size (\(actual), expected \(expected)).")
        }
        try require(harness.depthClearance>=CaseCarousel.shelfClearance-0.02,"\(context): held geometry intersects the shelf depth envelope.")
        let held=harness.heldBounds,viewport=harness.view.bounds
        try require(viewport.insetBy(dx:-1,dy:-1).contains(held),"\(context): held geometry was clipped (\(held) in \(viewport)).")
        if large {
            try require(max(held.width/viewport.width,held.height/viewport.height)>0.95,"\(context): the held case does not fill the useful viewport.")
        }
    }

    @MainActor private static func capture(_ harness: CaseSceneSmokeHarness) async throws -> CGImage {
        let deadline = ProcessInfo.processInfo.systemUptime + 20
        while !(harness.texturesReady && !harness.view.isPlaying) {
            guard ProcessInfo.processInfo.systemUptime < deadline else {
                throw CaseSceneFailure.assertion("Production sleeve textures or idle rendering did not settle within 20 seconds.")
            }
            try await Task.sleep(nanoseconds: 40_000_000)
        }
        harness.view.layoutSubtreeIfNeeded()
        SCNTransaction.flush()
        let image = harness.view.snapshot()
        harness.refreshProjection()
        var rect = CGRect(origin: .zero, size: image.size)
        guard let bitmap = image.cgImage(forProposedRect: &rect, context: nil, hints: nil), bitmap.width > 0, bitmap.height > 0 else {
            throw CaseSceneFailure.assertion("SceneKit did not produce a native snapshot.")
        }
        // A valid-sized PNG can still be an empty GPU render on a headless
        // runner. Sample the actual capture, without matching fragile pixels.
        guard let sample = CGContext(data: nil, width: 32, height: 20, bitsPerComponent: 8, bytesPerRow: 32*4,
                                     space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let bytes = sample.data?.assumingMemoryBound(to: UInt8.self) else {
            throw CaseSceneFailure.assertion("Unable to inspect the SceneKit snapshot.")
        }
        sample.draw(bitmap, in: CGRect(x: 0, y: 0, width: 32, height: 20))
        var visible = 0, lowest = 255, highest = 0
        for index in 0..<(32*20) where bytes[index*4+3] > 20 {
            visible += 1
            for channel in 0..<3 {
                lowest = min(lowest, Int(bytes[index*4+channel]))
                highest = max(highest, Int(bytes[index*4+channel]))
            }
        }
        try require(visible > 64 && highest-lowest > 20, "SceneKit returned an empty or uniform render.")
        return bitmap
    }

    @MainActor private static func verifyBack(_ harness: CaseSceneSmokeHarness, context: String) throws {
        try require(harness.bridge.previewBackFacing, "\(context): rendered orientation did not expose the preview.")
        guard let projection = harness.bridge.previewProjection else { throw CaseSceneFailure.assertion("\(context): missing live preview projection.") }
        let frame = harness.bridge.previewContentUVFrame
        // Projected video points must hit the same production sleeve UVs. This
        // catches flipped Y, mirrored artwork and the open lid's distinct
        // coordinate system without fragile golden pixels.
        for sample in [CGPoint(x: 0.25, y: 0.25), CGPoint(x: 0.75, y: 0.75)] {
            let screen = projection.project(CGPoint(x: sample.x*projection.surfaceSize.width, y: sample.y*projection.surfaceSize.height))
            guard let (surface, uv) = harness.hit(screen) else { throw CaseSceneFailure.assertion("\(context): projected preview did not hit the physical sleeve.") }
            try require(surface == .back, "\(context): projected preview hit a different physical surface.")
            let expected = CGPoint(x: frame.minX+sample.x*frame.width, y: frame.minY+sample.y*frame.height)
            try require(abs(uv.x-expected.x) < 0.025 && abs(uv.y-expected.y) < 0.025,
                        "\(context): preview projection and printed sleeve UVs disagree (\(uv), expected \(expected)).")
        }
    }

    private static func item(id: String, name: String, year: String, collection: Bool = false) -> IPTVItem {
        IPTVItem(id: id, sourceID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, name: name, group: "Test local",
                 logoURL: nil, kind: collection ? .series : .movie, directURL: nil, xtreamStreamID: nil, fileExtension: nil,
                 isSeriesCollection: collection,
                 details: IPTVDetails(synopsis: "Jaquette locale utilisée pour vérifier le vrai rendu natif.", year: year, duration: "1 h 42", genre: "Cinéma"))
    }

    private static func require(_ value: Bool, _ message: String) throws {
        if !value { throw CaseSceneFailure.assertion(message) }
    }

    private static func fixtureImage(width: Int, height: Int, title: String, subtitle: String) throws -> CGImage {
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width*4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw CaseSceneFailure.assertion("Unable to allocate fixture artwork.")
        }
        let w = CGFloat(width), h = CGFloat(height)
        context.setFillColor(CGColor(red: 0.05, green: 0.09, blue: 0.17, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: w, height: h))
        context.setFillColor(CGColor(red: 0.94, green: 0.34, blue: 0.19, alpha: 1))
        context.fill(CGRect(x: 0, y: h*0.82, width: w, height: h*0.18))
        context.setFillColor(CGColor(red: 0.07, green: 0.57, blue: 0.66, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: w, height: h*0.12))
        context.setStrokeColor(CGColor(gray: 0.95, alpha: 0.85))
        context.setLineWidth(5)
        context.stroke(CGRect(x: 12, y: 12, width: w-24, height: h-24))
        drawText("HAUT", size: w*0.07, at: CGPoint(x: w/2, y: h*0.885), in: context)
        drawText(title, size: w*0.057, at: CGPoint(x: w/2, y: h*0.52), in: context)
        drawText(subtitle, size: w*0.032, at: CGPoint(x: w/2, y: h*0.40), in: context)
        drawText("BAS", size: w*0.048, at: CGPoint(x: w/2, y: h*0.047), in: context)
        guard let result = context.makeImage() else { throw CaseSceneFailure.assertion("Unable to create fixture artwork.") }
        return result
    }

    private static func drawText(_ text: String, size: CGFloat, at point: CGPoint, in context: CGContext) {
        let font = CTFontCreateWithName("HelveticaNeue-Bold" as CFString, size, nil)
        let value = NSAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 1, alpha: 1)
        ])
        let line = CTLineCreateWithAttributedString(value)
        let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        context.textPosition = CGPoint(x: point.x-width/2, y: point.y)
        CTLineDraw(line, context)
    }

    private static func writeContactSheet(_ images: [(CGImage, String)], to url: URL) throws {
        let panelWidth = 1280, panelHeight = 800, captionHeight = 64
        let width = panelWidth*images.count, height = panelHeight+captionHeight
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width*4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw CaseSceneFailure.assertion("Unable to allocate capture sheet.")
        }
        context.setFillColor(CGColor(red: 0.035, green: 0.047, blue: 0.073, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.interpolationQuality = .high
        for (index, entry) in images.enumerated() {
            context.draw(entry.0, in: CGRect(x: index*panelWidth, y: 0, width: panelWidth, height: panelHeight))
            drawText(entry.1, size: 22, at: CGPoint(x: CGFloat(index*panelWidth+panelWidth/2), y: CGFloat(panelHeight+22)), in: context)
        }
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw CaseSceneFailure.assertion("Unable to create the capture PNG destination.")
        }
        CGImageDestinationAddImage(destination, image, nil)
        try require(CGImageDestinationFinalize(destination), "Unable to finish capture PNG \(url.lastPathComponent).")
        print("Capture: \(url.path)")
    }
}
#endif
