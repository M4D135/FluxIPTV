import SwiftUI
import ImageIO

// MARK: - Drawn packs of the dock
//
// Icons and plates drawn by David with ChatGPT for the shop to come
// ("voici les nouveaux icone et dock, servira pour le prochain store",
// 26/11): three families of seven icons, each on its own tile, and a plate
// for each. They are pictures, decoded once at the size they are shown and
// kept; the plate stretches between its ends, which keep their corners and
// their ornaments, and turns with a bar on a side of the screen.

extension FluxDockTheme {
    /// The folder of its pictures in `DockPacks`, for a drawn theme.
    var packName: String? {
        switch self {
        case .neon90: "neon-90"
        case .nightGlass: "verre-nocturne"
        case .artDeco: "art-deco"
        default: nil
        }
    }
    /// Corner of the tiles drawn in the pictures, for the ring of the focus.
    var packTileRadius: CGFloat {
        switch self {
        case .artDeco: 0.2
        default: 0.22
        }
    }
}

extension FluxDockItem {
    /// The name of its picture in a pack.
    var packPicture: String {
        switch self {
        case .live: "live"
        case .movie: "movie"
        case .series: "series"
        case .search: "search"
        case .favorites: "favorites"
        case .settings: "settings"
        }
    }
}

/// The pictures of the packs, decoded once at each size they are shown.
@MainActor enum DockPackArt {
    private static var cache: [String: CGImage] = [:]

    private static func url(_ name: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: "heic", subdirectory: "DockPacks")
    }

    /// An icon of `pack`, at least `pixels` a side (in steps, so that the
    /// loupe does not decode a picture at every size it passes).
    static func icon(_ pack: String, _ picture: String, pixels: CGFloat) -> CGImage? {
        let step = min(640, max(128, (pixels / 128).rounded(.up) * 128))
        let key = "\(pack)/\(picture)@\(Int(step))"
        if let image = cache[key] { return image }
        guard let url = url("\(pack)-\(picture)"), let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                        kCGImageSourceThumbnailMaxPixelSize: step,
                                        kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceShouldCacheImmediately: true]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        cache[key] = image
        return image
    }

    /// The plate of `pack`, lying or standing.
    static func plate(_ pack: String, standing: Bool) -> CGImage? {
        let key = "plate/\(pack)/\(standing)"
        if let image = cache[key] { return image }
        guard let url = url("plate-\(pack)"), let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let lying = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
        else { return nil }
        let image = standing ? turned(lying) ?? lying : lying
        cache[key] = image
        return image
    }

    /// A quarter turn: the left end of the plate goes to the top.
    private static func turned(_ image: CGImage) -> CGImage? {
        let width = image.height, height = image.width
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.translateBy(x: CGFloat(width), y: 0)
        context.rotate(by: .pi / 2)
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage()
    }
}

/// The plate of a drawn pack. Its ends, half as long as the plate is thick,
/// keep their curve and their ornaments; what lies between them stretches.
struct DockPackPlate: View {
    let pack: String
    let radius: CGFloat

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let standing = size.height > size.width
            if let art = DockPackArt.plate(pack, standing: standing) {
                // The picture is a capsule: its ends are half its thickness.
                let thickness = CGFloat(standing ? art.width : art.height)
                let scale = max(0.1, thickness / 2 / max(1, radius))
                let cap = max(1, (thickness / 2 - 2) / scale)
                Image(decorative: art, scale: scale)
                    .resizable(capInsets: EdgeInsets(top: cap, leading: cap, bottom: cap, trailing: cap), resizingMode: .stretch)
                    .frame(width: size.width, height: size.height)
                    .shadow(color: .black.opacity(0.35), radius: 14, y: 8)
            }
        }
        .allowsHitTesting(false)
    }
}

/// A destination drawn by a pack: its tile is the picture; the ring of the
/// focus follows its corners. The halo and the lift are drawn around it by
/// the cell, as for every theme.
struct DockPackDestination: View {
    let theme: FluxDockTheme
    let pack: String
    let item: FluxDockItem
    let selected: Bool
    /// Draws the ring of the selection.
    let focused: Bool
    let side: CGFloat
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: side * theme.packTileRadius, style: .continuous)
        Group {
            if let art = DockPackArt.icon(pack, item.packPicture, pixels: side * displayScale * 2) {
                Image(decorative: art, scale: 1).resizable().interpolation(.high)
            } else {
                Image(systemName: item.symbol).font(.system(size: side * 0.46, weight: .medium))
                    .foregroundStyle(.white).frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.6), in: shape)
            }
        }
        .frame(width: side, height: side)
        .brightness(selected ? 0.05 : 0)
        .overlay(shape.strokeBorder(.white.opacity(focused ? 0.95 : 0), lineWidth: 2).allowsHitTesting(false))
        .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
    }
}
