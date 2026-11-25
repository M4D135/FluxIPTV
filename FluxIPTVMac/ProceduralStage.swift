import SwiftUI
import CoreGraphics
import ImageIO

/// Procedural rooms are rendered during asset preparation. The app decodes one
/// bounded native image when the place/theme changes; there is no display link,
/// WebView or active room renderer during browsing or video playback.
private final class StageBitmap: NSObject, @unchecked Sendable {
    let image: CGImage
    init(_ image: CGImage) { self.image = image }
}

private enum StageRaster {
    // Decorative tvOS rooms use a 1080p raster; text, covers and video retain
    // their own native resolution. The room never needs a 4K offscreen layer
    // while the focus animation moves a foreground card.
    static func pixelBudget(_ requested: Int) -> Int {
        #if os(tvOS)
        max(320, min(1920, requested))
        #else
        max(320, min(3840, requested))
        #endif
    }

    // Settings thumbnails share this bounded cache with the visible scene.
    static let cache: NSCache<NSString, StageBitmap> = {
        let result = NSCache<NSString, StageBitmap>()
        result.countLimit = 4
        #if os(tvOS)
        result.totalCostLimit = 32 * 1024 * 1024
        #else
        result.totalCostLimit = 64 * 1024 * 1024
        #endif
        return result
    }()

    static func load(environment: MediaEnvironment, theme: VideoClubTheme, maxPixels: Int) -> StageBitmap? {
        guard !Task.isCancelled else { return nil }
        let name = environment.assetName(theme: theme)
        let url = Bundle.main.url(forResource: name, withExtension: "jpg", subdirectory: "RoomBakes")
            ?? Bundle.main.url(forResource: name, withExtension: "jpg")
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
        guard !Task.isCancelled else { return nil }
        return fallback(environment: environment, theme: theme, maxPixels: maxPixels)
    }

    /// A missing bundle resource must not leave a black screen. This bounded
    /// software frame still respects the cinema / video club / living room map.
    private static func fallback(environment: MediaEnvironment, theme: VideoClubTheme, maxPixels: Int) -> StageBitmap? {
        let width = min(960, max(320, maxPixels)), height = min(960, max(320, maxPixels)) * 9 / 16
        let mesh = theme.room(kind: environment.kind)
        let faces = ProceduralCinema.project(mesh, width: Double(width), height: Double(height))
        guard !Task.isCancelled, !faces.isEmpty,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.translateBy(x: 0, y: CGFloat(height)); context.scaleBy(x: 1, y: -1)
        for face in faces {
            guard !Task.isCancelled else { return nil }
            context.setFillColor(red: CGFloat(face.color.x), green: CGFloat(face.color.y), blue: CGFloat(face.color.z), alpha: 1)
            context.beginPath(); context.move(to: CGPoint(x: face.a.x, y: face.a.y))
            context.addLine(to: CGPoint(x: face.b.x, y: face.b.y)); context.addLine(to: CGPoint(x: face.c.x, y: face.c.y))
            context.closePath(); context.fillPath()
        }
        return context.makeImage().map(StageBitmap.init)
    }
}

private struct RoomStageImage: View {
    let environment: MediaEnvironment
    let theme: VideoClubTheme
    let maxPixels: Int
    var cachedOnly = false
    @State private var bitmap: StageBitmap?
    @State private var displayedKey = ""
    private var key: String { "\(environment.assetName(theme: theme))-\(StageRaster.pixelBudget(maxPixels))" }

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
            if let cached = StageRaster.cache.object(forKey: requested as NSString) {
                bitmap = cached; displayedKey = requested; return
            }
            bitmap = nil; displayedKey = ""
            guard !cachedOnly else { return }
            let selectedEnvironment = environment, selectedTheme = theme, pixelLimit = StageRaster.pixelBudget(maxPixels)
            let worker = Task.detached(priority: .utility) {
                StageRaster.load(environment: selectedEnvironment, theme: selectedTheme, maxPixels: pixelLimit)
            }
            let result = await withTaskCancellationHandler(operation: { await worker.value }, onCancel: { worker.cancel() })
            guard !Task.isCancelled, let result else { return }
            StageRaster.cache.setObject(result, forKey: requested as NSString, cost: result.image.bytesPerRow * result.image.height)
            bitmap = result; displayedKey = requested
        }
        .onDisappear { bitmap = nil; displayedKey = "" }
    }
}

struct ProceduralStage: View {
    let kind: IPTVMediaKind
    var cachedOnly = false
    /// Several rooms mounted together share the memory of one full-size room.
    var pixelLimit: Int?
    @AppStorage("fluxiptv.appearance.stage") private var style: ProceduralCinema.Style = .orbit
    @AppStorage(MediaThemePreferences.cinemaKey) private var cinemaTheme: VideoClubTheme = .neo90
    @AppStorage(MediaThemePreferences.seriesKey) private var seriesTheme: VideoClubTheme = .neo90
    @AppStorage(MediaThemePreferences.tvKey) private var tvTheme: VideoClubTheme = .neo90
    @Environment(\.accessibilityReduceTransparency) private var reduced
    @Environment(\.displayScale) private var displayScale
    private var theme: VideoClubTheme {
        switch kind { case .movie: cinemaTheme; case .series: seriesTheme; case .live: tvTheme }
    }
    var body: some View {
        GeometryReader { geometry in
            if !reduced, style != .off {
                let requested=max(geometry.size.width,geometry.size.height)*displayScale
                let wanted=requested <= 960 ? 960 : requested <= 1920 ? 1920 : requested <= 2560 ? 2560 : 3840
                let pixels=min(wanted, pixelLimit ?? wanted)
                RoomStageImage(environment: MediaEnvironment(kind: kind), theme: theme, maxPixels: pixels, cachedOnly: cachedOnly)
            }
        }.ignoresSafeArea().allowsHitTesting(false).accessibilityHidden(true)
    }
}

/// Reuses the identical place and theme recipe at thumbnail resolution.
struct RoomEnvironmentPreview: View {
    let environment: MediaEnvironment
    let theme: VideoClubTheme
    var body: some View {
        RoomStageImage(environment: environment, theme: theme, maxPixels: 640)
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
