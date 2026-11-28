import SwiftUI
import ImageIO
import Foundation

/// RAM-only, bounded thumbnail cache shared by the three Apple targets.
/// Artwork is optional; loading/decoding is never a prerequisite for playback.
final class FluxBitmap: NSObject, @unchecked Sendable {
    let image: CGImage
    init(_ image: CGImage) { self.image = image }
}

enum ArtworkLoader {
    private static let gate = ArtworkGate(limit:4)
    static let cache: NSCache<NSString, FluxBitmap> = {
        let cache = NSCache<NSString, FluxBitmap>()
        cache.countLimit = 120
        cache.totalCostLimit = 32 * 1024 * 1024
        return cache
    }()
    static let wallpaperCache: NSCache<NSString, FluxBitmap> = {
        let cache = NSCache<NSString, FluxBitmap>()
        cache.countLimit = 8
        cache.totalCostLimit = 16 * 1024 * 1024
        return cache
    }()
    static let caseCache: NSCache<NSString, FluxBitmap> = {
        let cache = NSCache<NSString, FluxBitmap>()
        cache.countLimit = 3
        cache.totalCostLimit = 16 * 1024 * 1024
        return cache
    }()
    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpMaximumConnectionsPerHost = 4
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 20
        return URLSession(configuration: configuration)
    }()

    static func cached(_ url: URL, wallpaper: Bool = false, caseHD: Bool = false) -> FluxBitmap? { (caseHD ? caseCache : wallpaper ? wallpaperCache : cache).object(forKey: url.absoluteString as NSString) }

    static func load(_ url: URL, wallpaper: Bool = false, caseHD: Bool = false) async -> FluxBitmap? {
        if let image = cached(url, wallpaper: wallpaper, caseHD: caseHD) { return image }
        guard await gate.acquire() else { return nil }
        let result = await loadWithinBudget(url,wallpaper:wallpaper,caseHD:caseHD)
        await gate.release()
        return result
    }

    private static func loadWithinBudget(_ url:URL,wallpaper:Bool,caseHD:Bool) async -> FluxBitmap? {
        guard !Task.isCancelled else {return nil}
        // Re-check after waiting; another view may have filled the cache.
        if let image = cached(url,wallpaper:wallpaper,caseHD:caseHD) {return image}
        do {
            let (data, response) = try await session.data(from: url)
            guard !Task.isCancelled, data.count <= 8 * 1024 * 1024,
                  let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
            let worker = Task.detached(priority: .utility) { () -> FluxBitmap? in
                guard !Task.isCancelled else { return nil }
                let sourceOptions = [kCGImageSourceShouldCache as String: false] as CFDictionary
                guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
                let options: [String: Any] = [kCGImageSourceCreateThumbnailFromImageAlways as String: true,
                               kCGImageSourceCreateThumbnailWithTransform as String: true,
                               kCGImageSourceShouldCacheImmediately as String: true,
                               kCGImageSourceThumbnailMaxPixelSize as String: caseHD ? 1536 : wallpaper ? 1024 : 512]
                guard let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
                guard !Task.isCancelled else { return nil }
                return FluxBitmap(thumb)
            }
            let result = await withTaskCancellationHandler(operation: { await worker.value }, onCancel: { worker.cancel() })
            guard !Task.isCancelled, let result else { return nil }
            (caseHD ? caseCache : wallpaper ? wallpaperCache : cache).setObject(result, forKey: url.absoluteString as NSString, cost: result.image.bytesPerRow * result.image.height)
            return result
        } catch { return nil }
    }
}

struct ArtworkView<Placeholder: View>: View {
    let url: URL?
    let fit: Bool
    let placeholder: Placeholder
    @Environment(\.fluxArtwork) private var artworkEnabled
    @State private var bitmap: FluxBitmap?
    init(url: URL?, fit: Bool, @ViewBuilder placeholder: () -> Placeholder) {
        self.url = url
        self.fit = fit
        self.placeholder = placeholder()
    }
    var body: some View {
        Group {
            if artworkEnabled, let bitmap {
                Image(decorative: bitmap.image, scale: 1, orientation: .up)
                    .resizable().aspectRatio(contentMode: fit ? .fit : .fill)
            } else { placeholder }
        }
        .task(id: artworkEnabled ? url : nil) {
            guard artworkEnabled, let url else { bitmap = nil; return }
            bitmap = ArtworkLoader.cached(url)
            if bitmap == nil {
                let loaded = await ArtworkLoader.load(url)
                guard !Task.isCancelled else { return }
                bitmap = loaded
            }
        }
    }
}
