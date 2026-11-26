import SwiftUI
import CoreGraphics
import ImageIO

/// The pictures behind the screens are drawn for each screen and shipped
/// with the app. The app decodes one bounded native image when the picture
/// changes; there is no display link, WebView or active renderer during
/// browsing or video playback.
private final class StageBitmap: NSObject, @unchecked Sendable {
    let image: CGImage
    init(_ image: CGImage) { self.image = image }
}

private enum StageRaster {
    // Decorative tvOS pictures use a 1080p raster; text, covers and video
    // retain their own native resolution. A picture never needs a 4K
    // offscreen layer while the focus animation moves a foreground card.
    static func pixelBudget(_ requested: Int) -> Int {
        #if os(tvOS)
        max(320, min(1920, requested))
        #else
        max(320, min(3840, requested))
        #endif
    }

    // It holds the picture shown, the next one of a slideshow, and those
    // of the home screen's icons.
    private static let screens: NSCache<NSString, StageBitmap> = {
        let result = NSCache<NSString, StageBitmap>()
        #if os(tvOS)
        result.countLimit = 8
        result.totalCostLimit = 56 * 1024 * 1024
        #else
        result.countLimit = 10
        result.totalCostLimit = 128 * 1024 * 1024
        #endif
        return result
    }()
    /// The thumbnails of the studio and of the settings keep their own
    /// cache: walking a shelf never drops a picture of the screens.
    private static let thumbnails: NSCache<NSString, StageBitmap> = {
        let result = NSCache<NSString, StageBitmap>()
        result.countLimit = 64
        result.totalCostLimit = 32 * 1024 * 1024
        return result
    }()
    static func cache(for maxPixels: Int) -> NSCache<NSString, StageBitmap> {
        pixelBudget(maxPixels) <= 640 ? thumbnails : screens
    }

    static func key(_ picture: FluxBackdropPicture, _ maxPixels: Int) -> String {
        "\(picture.resource.name)-\(pixelBudget(maxPixels))"
    }

    static func load(_ picture: FluxBackdropPicture, maxPixels: Int) -> StageBitmap? {
        guard !Task.isCancelled else { return nil }
        let resource = picture.resource
        let url = Bundle.main.url(forResource: resource.name, withExtension: "jpg", subdirectory: resource.folder)
            ?? Bundle.main.url(forResource: resource.name, withExtension: "jpg")
        if let url,
           let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: pixelBudget(maxPixels),
                kCGImageSourceShouldCacheImmediately: true
            ]
            if let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary), !Task.isCancelled {
                return StageBitmap(image)
            }
        }
        // A missing picture leaves the colour of the screen behind it.
        return nil
    }

    /// Decodes a picture before its turn, so that it shows at once.
    static func preload(_ picture: FluxBackdropPicture, maxPixels: Int) async {
        let key = key(picture, maxPixels), cache = cache(for: maxPixels)
        guard cache.object(forKey: key as NSString) == nil else { return }
        let budget = pixelBudget(maxPixels)
        let worker = Task.detached(priority: .utility) { load(picture, maxPixels: budget) }
        let result = await withTaskCancellationHandler(operation: { await worker.value }, onCancel: { worker.cancel() })
        guard let result else { return }
        cache.setObject(result, forKey: key as NSString, cost: result.image.bytesPerRow * result.image.height)
    }
}

/// One picture, decoded off the main thread at the size it is shown.
private struct StagePictureImage: View {
    let picture: FluxBackdropPicture
    let maxPixels: Int
    var cachedOnly = false
    @State private var bitmap: StageBitmap?
    @State private var displayedKey = ""
    private var key: String { StageRaster.key(picture, maxPixels) }

    /// A decoded picture shows in the first frame: a cut between two
    /// pictures never lets the colour behind them through.
    init(picture: FluxBackdropPicture, maxPixels: Int, cachedOnly: Bool = false) {
        self.picture = picture; self.maxPixels = maxPixels; self.cachedOnly = cachedOnly
        let key = StageRaster.key(picture, maxPixels)
        let cached = StageRaster.cache(for: maxPixels).object(forKey: key as NSString)
        _bitmap = State(initialValue: cached)
        _displayedKey = State(initialValue: cached == nil ? "" : key)
    }

    var body: some View {
        GeometryReader { geometry in
            if let bitmap, displayedKey == key {
                Image(decorative: bitmap.image, scale: 1, orientation: .up)
                    .resizable().scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height).clipped()
            }
        }
        .allowsHitTesting(false).accessibilityHidden(true)
        .task(id: "\(key)|\(cachedOnly)") {
            let requested = key
            let cache = StageRaster.cache(for: maxPixels)
            if let cached = cache.object(forKey: requested as NSString) {
                bitmap = cached; displayedKey = requested; return
            }
            bitmap = nil; displayedKey = ""
            guard !cachedOnly else { return }
            let selected = picture, pixelLimit = StageRaster.pixelBudget(maxPixels)
            let worker = Task.detached(priority: .utility) { StageRaster.load(selected, maxPixels: pixelLimit) }
            let result = await withTaskCancellationHandler(operation: { await worker.value }, onCancel: { worker.cancel() })
            guard !Task.isCancelled, let result else { return }
            cache.setObject(result, forKey: requested as NSString, cost: result.image.bytesPerRow * result.image.height)
            bitmap = result; displayedKey = requested
        }
        .onDisappear { bitmap = nil; displayedKey = "" }
    }
}

/// The size a full-screen picture is decoded at, from the size it covers.
private func stagePixels(_ size: CGSize, scale: CGFloat, limit: Int?) -> Int {
    let requested = max(size.width, size.height) * scale
    let wanted = requested <= 960 ? 960 : requested <= 1920 ? 1920 : requested <= 2560 ? 2560 : 3840
    return min(wanted, limit ?? wanted)
}

/// Pictures in turn behind a screen, each decoded before its turn comes.
/// Every view of the same pictures shows the same one: the clock says which.
struct BackdropSlideshow: View {
    let pictures: [FluxBackdropPicture]
    let plan: FluxBackdropPlan
    var pixelLimit: Int?
    /// A screen kept mounted behind another one waits: it decodes nothing
    /// until it comes in front, then catches up with the clock.
    var active = true
    /// Seconds of the fade from one picture to the next.
    var fade = 1.4
    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: FluxBackdropPicture?
    @State private var budget = 0

    private struct Turn: Equatable {
        let pictures: [String]
        let interval: FluxSlideInterval
        let order: FluxSlideOrder
        let budget: Int
        let active: Bool
    }

    var body: some View {
        GeometryReader { geometry in
            let pixels = stagePixels(geometry.size, scale: displayScale, limit: pixelLimit)
            ZStack {
                if let shown {
                    StagePictureImage(picture: shown, maxPixels: pixels)
                        .id(shown.id)
                        .transition(.opacity)
                }
            }
            .animation(plan.transition == .fade && !reduceMotion ? .easeInOut(duration: fade) : nil, value: shown)
            .onChange(of: pixels, initial: true) { _, value in budget = value }
        }
        .ignoresSafeArea().allowsHitTesting(false).accessibilityHidden(true)
        .task(id: Turn(pictures: pictures.map(\.id), interval: plan.interval, order: plan.order,
                       budget: budget, active: active)) { await turn() }
    }

    private func turn() async {
        guard !pictures.isEmpty else { return }
        let clock = pictures[plan.slot(at: Date().timeIntervalSinceReferenceDate, count: pictures.count).current]
        if shown == nil || (!active && shown != clock) {
            // Nothing shown yet, or out of sight: no fade.
            var quiet = Transaction(); quiet.disablesAnimations = true
            withTransaction(quiet) { shown = clock }
        } else if shown != clock {
            // In front again, or other pictures chosen: the picture of the
            // clock comes once it is decoded.
            guard budget > 0 else { return }
            await StageRaster.preload(clock, maxPixels: budget)
            guard !Task.isCancelled else { return }
            shown = clock
        }
        guard active, pictures.count > 1, budget > 0 else { return }
        while !Task.isCancelled {
            let now = Date().timeIntervalSinceReferenceDate
            let slot = plan.slot(at: now, count: pictures.count)
            // The next picture is decoded a few seconds before its turn.
            let early = slot.change - now - 4
            if early > 0 { try? await Task.sleep(nanoseconds: UInt64(early * 1_000_000_000)) }
            guard !Task.isCancelled else { return }
            await StageRaster.preload(pictures[slot.next], maxPixels: budget)
            let wait = slot.change - Date().timeIntervalSinceReferenceDate
            if wait > 0 { try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }
            guard !Task.isCancelled else { return }
            shown = pictures[slot.next]
        }
    }
}

/// What stands behind a screen, as the settings say: the pictures drawn
/// for it, those chosen for it, or nothing. In its own setting the home
/// screen shows what stands behind the screen its selected icon opens.
struct FluxSpaceStage: View {
    let space: FluxSpace
    /// On the home screen, the screen that its selected icon opens.
    var pointed: FluxSpace?
    /// What the screen holds: the home screen, which has no picture of its
    /// own, shows those of its screen.
    let kind: IPTVMediaKind
    var pixelLimit: Int?
    /// Pictures chosen in the studio, shown before they are kept.
    var trying: FluxBackdropPlan?
    /// Mounted behind the screen in front, ready to come forward.
    var active = true
    /// The studio fades quicker from one picture tried to the next.
    var fade = 1.4
    @AppStorage(FluxBackdropChoices.storageKey) private var stored = ""
    @AppStorage("fluxiptv.appearance.stage") private var style: ProceduralCinema.Style = .orbit
    @Environment(\.accessibilityReduceTransparency) private var reduced
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shown = Self.resolve(space: space, pointed: pointed, choices: FluxBackdropChoices(stored: stored), trying: trying)
        ZStack {
            if !reduced, style != .off || trying != nil, shown.plan.mode != .plain {
                BackdropSlideshow(pictures: pictures(shown.plan, space: shown.space), plan: shown.plan,
                                  pixelLimit: pixelLimit, active: active, fade: fade)
                    .id(shown.space)
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.45), value: shown.space)
        .ignoresSafeArea().allowsHitTesting(false).accessibilityHidden(true)
    }

    /// The screen whose pictures are shown, and its plan.
    static func resolve(space: FluxSpace, pointed: FluxSpace?, choices: FluxBackdropChoices,
                        trying: FluxBackdropPlan? = nil) -> (space: FluxSpace, plan: FluxBackdropPlan) {
        let plan = trying ?? choices.plan(for: space)
        if space == .home, plan.mode == .automatic, let pointed, pointed != .home {
            return (pointed, choices.plan(for: pointed))
        }
        return (space, plan)
    }

    private func pictures(_ plan: FluxBackdropPlan, space: FluxSpace) -> [FluxBackdropPicture] {
        if plan.mode == .pictures, !plan.shown.isEmpty { return plan.shown }
        // The home screen without a selected icon shows the pictures of the
        // screen of what it holds.
        return FluxBackdropLibrary.pictures(for: space, holding: kind)
    }
}

/// A picture of the library, small.
struct BackdropThumbnail: View {
    let picture: FluxBackdropPicture
    var maxPixels = 480
    var body: some View {
        StagePictureImage(picture: picture, maxPixels: maxPixels)
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .background(Color.black)
    }
}
