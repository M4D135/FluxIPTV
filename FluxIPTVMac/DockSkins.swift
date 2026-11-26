import SwiftUI
import CoreGraphics

// MARK: - Skins of the dock
//
// The themes after other systems and other years. Each draws its plate, its
// icons, their names and the mark of the screen in front in the manner of
// its time, with pictures drawn for this app: no icon, no name and no mark
// of a system is borrowed. Everything is drawn once and cached: a pixel icon
// is a bitmap of sixteen pixels a side, enlarged without smoothing.

extension FluxDockTheme {
    /// Drawn by the skins below; the Flux themes keep their own drawing.
    var skinned: Bool { family != .flux }
}

/// A colour that the skins lighten, darken and mix.
struct SkinRGB: Hashable {
    var r: Double, g: Double, b: Double
    init(_ r: Double, _ g: Double, _ b: Double) { self.r = r; self.g = g; self.b = b }
    func mix(_ other: SkinRGB, _ t: Double) -> SkinRGB {
        SkinRGB(r + (other.r - r) * t, g + (other.g - g) * t, b + (other.b - b) * t)
    }
    func lighter(_ t: Double) -> SkinRGB { mix(.white, t) }
    func darker(_ t: Double) -> SkinRGB { mix(.black, t) }
    var color: Color { Color(red: r, green: g, blue: b) }
    var packed: UInt32 {
        func byte(_ v: Double) -> UInt32 { UInt32(max(0, min(255, (v * 255).rounded()))) }
        return byte(r) << 24 | byte(g) << 16 | byte(b) << 8 | 0xFF
    }
    static let white = SkinRGB(1, 1, 1), black = SkinRGB(0, 0, 0)
}

extension FluxDockItem {
    /// Its colour in the skins, close to its tint.
    var skinRGB: SkinRGB {
        switch self {
        case .live: SkinRGB(0.20, 0.64, 1.0)
        case .movie: SkinRGB(1.0, 0.50, 0.18)
        case .series: SkinRGB(0.62, 0.36, 0.96)
        case .search: SkinRGB(0.18, 0.80, 0.66)
        case .favorites: SkinRGB(1.0, 0.78, 0.16)
        case .settings: SkinRGB(0.58, 0.62, 0.70)
        }
    }
    /// The symbol drawn as an outline, for the skins that draw outlines.
    var outlineSymbol: String {
        switch self {
        case .live: "tv"
        case .movie: "film"
        case .series: "square.stack.3d.up"
        case .search: "magnifyingglass"
        case .favorites: "star"
        case .settings: "gearshape"
        }
    }
    var pixelPicture: DockPixelPicture {
        switch self {
        case .live: .television
        case .movie: .clapper
        case .series: .cards
        case .search: .lens
        case .favorites: .star
        case .settings: .gear
        }
    }
}

enum DockSkin {
    /// Corner of a tile, and of the picture of a title.
    static func radius(_ theme: FluxDockTheme, side: CGFloat) -> CGFloat {
        switch theme {
        case .tactile: side * 0.225
        case .pebbles: side / 2
        case .frost: side * 0.18
        case .gel: side * 0.30
        case .hills: side * 0.22
        default: 0
        }
    }
    /// A pixel icon is enlarged by whole points: a sixteenth of its side.
    static func pixelSide(_ side: CGFloat) -> CGFloat { max(16, (side / 16).rounded(.down) * 16) }

    static let phosphorInk = SkinRGB(0.25, 1.0, 0.42)
    static let deskGreen = SkinRGB(0.0, 0.58, 0.0)
    static let fourBlue = SkinRGB(0.0, 0.33, 0.67)
    static let fourOrange = SkinRGB(1.0, 0.53, 0.0)
    static let silver = SkinRGB(0.75, 0.75, 0.75)
    static let workbenchGrey = SkinRGB(0.67, 0.67, 0.67)
}

// MARK: Pixel pictures

/// The pictures of the pixel skins, drawn for this app on sixteen pixels.
enum DockPixelPicture: String, CaseIterable {
    case television, clapper, cards, lens, star, gear, folder

    /// Ink 1, paper 2, colour 3, light 4, shade 5; 0 is transparent.
    var cells: [UInt8] { DockPixelPicture.drawn[self] ?? [] }

    private static let drawn: [DockPixelPicture: [UInt8]] = {
        var result: [DockPixelPicture: [UInt8]] = [:]
        for picture in DockPixelPicture.allCases { result[picture] = picture.draw() }
        return result
    }()

    private func draw() -> [UInt8] {
        var c = PixelGrid()
        let ink: UInt8 = 1, paper: UInt8 = 2, colour: UInt8 = 3, light: UInt8 = 4, shade: UInt8 = 5
        switch self {
        case .television:
            c.line(4, 0, 7, 3, ink); c.line(11, 0, 8, 3, ink)
            c.frame(1, 4, 14, 11, ink); c.fill(2, 5, 12, 9, paper)
            c.frame(3, 6, 8, 7, ink); c.fill(4, 7, 6, 5, colour)
            c.set(4, 7, light); c.set(5, 7, light); c.set(4, 8, light)
            c.set(12, 7, ink); c.set(12, 9, ink); c.set(12, 11, shade); c.set(12, 12, shade)
            c.fill(3, 15, 2, 1, ink); c.fill(11, 15, 2, 1, ink)
        case .clapper:
            c.frame(1, 1, 14, 4, ink)
            for y in 2...3 { for x in 2...13 { c.set(x, y, (x - y + 12) % 6 < 3 ? paper : ink) } }
            c.fill(1, 5, 2, 1, ink)
            c.frame(1, 6, 14, 9, ink); c.fill(2, 7, 12, 7, colour)
            c.fill(3, 8, 10, 1, paper)
            c.fill(3, 10, 4, 1, paper); c.fill(9, 10, 4, 1, paper)
            c.fill(3, 12, 4, 1, paper); c.fill(9, 12, 4, 1, paper)
        case .cards:
            c.frame(5, 1, 10, 10, ink); c.fill(6, 2, 8, 8, shade)
            c.frame(3, 3, 10, 10, ink); c.fill(4, 4, 8, 8, paper)
            c.frame(1, 5, 10, 10, ink); c.fill(2, 6, 8, 8, colour)
            c.set(2, 6, light); c.set(3, 6, light); c.set(2, 7, light)
            c.set(5, 8, paper); c.fill(5, 9, 2, 1, paper); c.fill(5, 10, 3, 1, paper); c.fill(5, 11, 2, 1, paper); c.set(5, 12, paper)
        case .lens:
            for y in 0..<16 {
                for x in 0..<16 {
                    let dx = Double(x) - 6, dy = Double(y) - 6
                    let d = (dx * dx + dy * dy).squareRoot()
                    if d <= 5.3 { c.set(x, y, d > 3.9 ? ink : colour) }
                }
            }
            c.set(4, 3, light); c.set(3, 4, light); c.set(4, 4, light); c.set(5, 3, light)
            for i in 0...4 { c.set(10 + i, 10 + i, ink); c.set(11 + i, 10 + i, ink); c.set(10 + i, 11 + i, shade) }
        case .star:
            let points: [(Double, Double)] = (0..<10).map { i in
                let angle = -Double.pi / 2 + Double(i) * Double.pi / 5
                let radius = i % 2 == 0 ? 7.6 : 3.1
                return (7.5 + radius * cos(angle), 8.3 + radius * sin(angle))
            }
            var inside = [Bool](repeating: false, count: 256)
            for y in 0..<16 { for x in 0..<16 { inside[y * 16 + x] = PixelGrid.contains(points, Double(x) + 0.5, Double(y) + 0.5) } }
            for y in 0..<16 {
                for x in 0..<16 where inside[y * 16 + x] {
                    let edge = PixelGrid.neighbours(x, y).contains { (index: Int?) -> Bool in
                        guard let index else { return true }
                        return !inside[index]
                    }
                    c.set(x, y, edge ? ink : colour)
                }
            }
            c.set(6, 6, light); c.set(7, 5, light); c.set(6, 7, light)
        case .gear:
            for y in 0..<16 {
                for x in 0..<16 {
                    let dx = Double(x) + 0.5 - 8, dy = Double(y) + 0.5 - 8
                    let d = (dx * dx + dy * dy).squareRoot()
                    let tooth = cos(8 * atan2(dy, dx)) > 0.25
                    guard d <= (tooth ? 7.6 : 5.8), d >= 2.3 else { continue }
                    c.set(x, y, paper)
                }
            }
            c.outline(ink)
            for i in 0..<256 where c.cells[i] == paper {
                let x = i % 16, y = i / 16
                if Double(x + y) > 17 { c.cells[i] = shade } else if Double(x + y) < 11 { c.cells[i] = light }
            }
        case .folder:
            c.frame(1, 3, 6, 3, ink); c.fill(2, 4, 4, 1, colour)
            c.frame(1, 5, 14, 10, ink); c.fill(2, 6, 12, 8, colour)
            c.fill(2, 6, 12, 1, light); c.fill(2, 13, 12, 1, shade)
        }
        return c.cells
    }
}

struct PixelGrid {
    var cells = [UInt8](repeating: 0, count: 256)
    mutating func set(_ x: Int, _ y: Int, _ value: UInt8) {
        guard (0..<16).contains(x), (0..<16).contains(y) else { return }
        cells[y * 16 + x] = value
    }
    mutating func fill(_ x: Int, _ y: Int, _ width: Int, _ height: Int, _ value: UInt8) {
        for row in y..<(y + height) { for column in x..<(x + width) { set(column, row, value) } }
    }
    mutating func frame(_ x: Int, _ y: Int, _ width: Int, _ height: Int, _ value: UInt8) {
        fill(x, y, width, 1, value); fill(x, y + height - 1, width, 1, value)
        fill(x, y, 1, height, value); fill(x + width - 1, y, 1, height, value)
    }
    mutating func line(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int, _ value: UInt8) {
        let steps = max(abs(x1 - x0), abs(y1 - y0))
        for i in 0...max(0, steps) {
            let t = steps == 0 ? 0 : Double(i) / Double(steps)
            set(Int((Double(x0) + Double(x1 - x0) * t).rounded()), Int((Double(y0) + Double(y1 - y0) * t).rounded()), value)
        }
    }
    /// Every drawn pixel beside an empty one, or beside the edge, becomes ink.
    mutating func outline(_ ink: UInt8) {
        let drawn = cells
        for y in 0..<16 {
            for x in 0..<16 where drawn[y * 16 + x] != 0 {
                let edge = Self.neighbours(x, y).contains { (index: Int?) -> Bool in
                    guard let index else { return true }
                    return drawn[index] == 0
                }
                if edge { cells[y * 16 + x] = ink }
            }
        }
    }
    /// The cells of the four neighbours of a pixel; nil beyond the grid.
    static func neighbours(_ x: Int, _ y: Int) -> [Int?] {
        let around: [(Int, Int)] = [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)]
        return around.map { (cell: (Int, Int)) -> Int? in
            let (nx, ny) = cell
            guard (0..<16).contains(nx), (0..<16).contains(ny) else { return nil }
            return ny * 16 + nx
        }
    }
    static func contains(_ polygon: [(Double, Double)], _ x: Double, _ y: Double) -> Bool {
        var inside = false
        var j = polygon.count - 1
        for i in polygon.indices {
            let (xi, yi) = polygon[i], (xj, yj) = polygon[j]
            if (yi > y) != (yj > y), x < (xj - xi) * (y - yi) / (yj - yi) + xi { inside.toggle() }
            j = i
        }
        return inside
    }
}

/// The five colours of a pixel picture in a skin: ink, paper, colour,
/// light and shade.
struct DockPixelPalette: Hashable {
    let colours: [SkinRGB]

    static func of(_ theme: FluxDockTheme, picture: DockPixelPicture, selected: Bool) -> DockPixelPalette {
        let white = SkinRGB.white, black = SkinRGB.black
        switch theme {
        case .phosphor:
            let ink = DockSkin.phosphorInk
            return selected
                ? DockPixelPalette(colours: [black, ink.darker(0.42), ink.darker(0.72), ink.lighter(0.5), ink.darker(0.6)])
                : DockPixelPalette(colours: [ink, ink.darker(0.86), ink.darker(0.32), ink.lighter(0.62), ink.darker(0.58)])
        case .greenDesk:
            // One bit: black on white, the other way round once selected.
            return selected
                ? DockPixelPalette(colours: [white, black, white, black, white])
                : DockPixelPalette(colours: [black, white, black, white, black])
        case .fourColor:
            // Selected, each of the four colours takes its complement.
            let blue = DockSkin.fourBlue, orange = DockSkin.fourOrange, ink = SkinRGB(0, 0, 0.13)
            return selected
                ? DockPixelPalette(colours: [white, ink, blue, ink, orange])
                : DockPixelPalette(colours: [ink, white, orange, white, blue])
        case .eightColor:
            let accent: SkinRGB = switch picture {
            case .clapper: SkinRGB(0.85, 0.55, 0.45)
            case .cards, .star, .folder: SkinRGB(0.80, 0.70, 0.58)
            case .gear: SkinRGB(0.75, 0.75, 0.75)
            case .television, .lens: SkinRGB(0.40, 0.53, 0.73)
            }
            return DockPixelPalette(colours: [black, SkinRGB(0.86, 0.86, 0.86), accent, white, SkinRGB(0.48, 0.48, 0.48)])
        default:
            // Sixteen colours: each picture keeps one of them.
            let accent: SkinRGB = switch picture {
            case .television: SkinRGB(0, 0.5, 0.5)
            case .clapper: SkinRGB(0.5, 0, 0)
            case .cards: SkinRGB(0.5, 0, 0.5)
            case .lens: SkinRGB(0, 1, 1)
            case .star, .folder: SkinRGB(1, 1, 0)
            case .gear: DockSkin.silver
            }
            return DockPixelPalette(colours: [black, white, accent, white, SkinRGB(0.5, 0.5, 0.5)])
        }
    }
}

@MainActor
enum DockPixelArt {
    private static var images: [String: CGImage] = [:]

    static func image(_ picture: DockPixelPicture, _ palette: DockPixelPalette) -> CGImage? {
        let key = picture.rawValue + palette.colours.map { String($0.packed, radix: 16) }.joined(separator: ".")
        if let image = images[key] { return image }
        let cells = picture.cells
        guard cells.count == 256 else { return nil }
        var bytes = [UInt8](repeating: 0, count: 256 * 4)
        for index in 0..<256 where cells[index] != 0 {
            let colour = palette.colours[Int(cells[index]) - 1].packed
            bytes[index * 4] = UInt8(colour >> 24 & 0xFF)
            bytes[index * 4 + 1] = UInt8(colour >> 16 & 0xFF)
            bytes[index * 4 + 2] = UInt8(colour >> 8 & 0xFF)
            bytes[index * 4 + 3] = 0xFF
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let image = CGImage(width: 16, height: 16, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 64,
                                  space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else { return nil }
        images[key] = image
        return image
    }

    /// A pattern repeated over a plate: rows of a column one pixel wide.
    static func stripes(_ rows: [(SkinRGB, Double)], key: String) -> CGImage? {
        if let image = images[key] { return image }
        var bytes = [UInt8](repeating: 0, count: rows.count * 4)
        for (index, row) in rows.enumerated() {
            let alpha = max(0, min(1, row.1))
            bytes[index * 4] = UInt8((row.0.r * alpha * 255).rounded())
            bytes[index * 4 + 1] = UInt8((row.0.g * alpha * 255).rounded())
            bytes[index * 4 + 2] = UInt8((row.0.b * alpha * 255).rounded())
            bytes[index * 4 + 3] = UInt8((alpha * 255).rounded())
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let image = CGImage(width: 1, height: rows.count, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 4,
                                  space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else { return nil }
        images[key] = image
        return image
    }

    /// The grey and white checks of a pressed button.
    static var checks: CGImage? {
        if let image = images["checks"] { return image }
        let a: [UInt8] = [255, 255, 255, 255], b: [UInt8] = [191, 191, 191, 255]
        let bytes = a + b + b + a
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let image = CGImage(width: 2, height: 2, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 8,
                                  space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else { return nil }
        images["checks"] = image
        return image
    }
}

/// A pixel picture, enlarged without smoothing.
struct DockPixelIcon: View {
    let picture: DockPixelPicture
    let palette: DockPixelPalette
    let side: CGFloat
    var body: some View {
        if let image = DockPixelArt.image(picture, palette) {
            Image(decorative: image, scale: 1).interpolation(.none).resizable()
                .frame(width: side, height: side)
        } else {
            Color.clear.frame(width: side, height: side)
        }
    }
}

/// A pattern of rows, repeated over what it covers.
struct DockSkinPattern: View {
    let image: CGImage?
    var scale: CGFloat = 2
    var body: some View {
        if let image {
            Image(decorative: image, scale: scale).resizable(resizingMode: .tile).interpolation(.none)
        }
    }
}

/// The raised or sunken edges of a control drawn in relief.
struct SkinBevel: View {
    var raised = true
    let line: CGFloat
    var light = Color.white
    var dark = Color.black
    var innerLight: Color?
    var innerDark: Color?

    var body: some View {
        Canvas { context, size in
            func edges(_ inset: CGFloat, _ lit: Color, _ shaded: Color) {
                let rect = CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset)
                var upper = Path()
                upper.move(to: CGPoint(x: rect.minX, y: rect.maxY)); upper.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
                upper.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
                var lower = Path()
                lower.move(to: CGPoint(x: rect.maxX, y: rect.minY)); lower.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
                lower.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
                context.stroke(upper, with: .color(raised ? lit : shaded), lineWidth: line)
                context.stroke(lower, with: .color(raised ? shaded : lit), lineWidth: line)
            }
            edges(line / 2, light, dark)
            if let innerLight, let innerDark { edges(line * 1.5, innerLight, innerDark) }
        }
        .allowsHitTesting(false)
    }
}

private struct SkinTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: Plates

struct DockSkinPlate: View {
    let theme: FluxDockTheme
    let radius: CGFloat

    var body: some View {
        switch theme {
        case .tactile:
            let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
            Color.clear.fluxGlass(radius: radius)
                .overlay(shape.fill(.white.opacity(0.17)).allowsHitTesting(false))
                .overlay(shape.strokeBorder(.white.opacity(0.34), lineWidth: 1).allowsHitTesting(false))
                .shadow(color: .black.opacity(0.28), radius: 18, y: 10)
        case .pebbles:
            Capsule().fill(Color(red: 0.11, green: 0.12, blue: 0.15).opacity(0.93))
                .overlay(Capsule().strokeBorder(.white.opacity(0.07), lineWidth: 1))
                .shadow(color: .black.opacity(0.35), radius: 16, y: 8)
        case .frost:
            let corner = radius * 0.45
            let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
            Color.clear.fluxGlass(radius: corner)
                .overlay(shape.fill(Color(red: 0.13, green: 0.14, blue: 0.17).opacity(0.62)).allowsHitTesting(false))
                .overlay(shape.strokeBorder(.white.opacity(0.13), lineWidth: 1).allowsHitTesting(false))
                .shadow(color: .black.opacity(0.32), radius: 16, y: 8)
        case .gel:
            let shape = RoundedRectangle(cornerRadius: radius * 0.5, style: .continuous)
            DockSkinPattern(image: DockPixelArt.stripes([(.white, 0.92), (.white, 0.92), (SkinRGB(0.86, 0.87, 0.90), 0.86), (SkinRGB(0.86, 0.87, 0.90), 0.86)], key: "pinstripes"))
                .clipShape(shape)
                .overlay(shape.strokeBorder(.white.opacity(0.95), lineWidth: 1))
                .overlay(shape.inset(by: 1).strokeBorder(.black.opacity(0.12), lineWidth: 1))
                .shadow(color: .black.opacity(0.32), radius: 14, y: 8)
        case .hills:
            let shape = RoundedRectangle(cornerRadius: radius * 0.4, style: .continuous)
            shape.fill(LinearGradient(colors: [Color(red: 0.29, green: 0.54, blue: 0.98), Color(red: 0.15, green: 0.37, blue: 0.88),
                                               Color(red: 0.11, green: 0.29, blue: 0.78)], startPoint: .top, endPoint: .bottom))
                .overlay(alignment: .top) {
                    shape.strokeBorder(LinearGradient(colors: [Color(red: 0.64, green: 0.80, blue: 1.0), .clear], startPoint: .top, endPoint: .center), lineWidth: 1.5)
                }
                .overlay(shape.strokeBorder(Color(red: 0.05, green: 0.17, blue: 0.52), lineWidth: 1))
                .shadow(color: .black.opacity(0.34), radius: 14, y: 8)
        case .bevel:
            DockSkin.silver.color
                .overlay(SkinBevel(line: 1.5, light: .white, dark: .black, innerLight: Color(white: 0.87), innerDark: Color(white: 0.5)))
                .shadow(color: .black.opacity(0.35), radius: 10, y: 6)
        case .eightColor:
            DockSkin.workbenchGrey.color
                .overlay(SkinBevel(line: 2, light: .white, dark: .black))
                .shadow(color: .black.opacity(0.35), radius: 10, y: 6)
        case .fourColor:
            DockSkin.fourBlue.color
                .overlay(Rectangle().strokeBorder(.white, lineWidth: 3))
                .overlay(Rectangle().inset(by: 3).strokeBorder(Color(red: 0, green: 0, blue: 0.13), lineWidth: 1.5))
                .shadow(color: .black.opacity(0.35), radius: 10, y: 6)
        case .greenDesk:
            DockSkin.deskGreen.color
                .overlay(Rectangle().strokeBorder(.black, lineWidth: 2))
                .shadow(color: .black.opacity(0.35), radius: 10, y: 6)
        case .phosphor:
            Color(red: 0, green: 0.035, blue: 0.01).opacity(0.95)
                .overlay(DockSkinPattern(image: DockPixelArt.stripes([(.black, 0), (.black, 0), (.black, 0.35), (.black, 0.35)], key: "scanlines")))
                .overlay(Rectangle().strokeBorder(DockSkin.phosphorInk.darker(0.45).color, lineWidth: 2))
                .shadow(color: DockSkin.phosphorInk.color.opacity(0.25), radius: 12)
        default:
            EmptyView()
        }
    }
}

// MARK: Icons

/// A destination of the bar drawn by a skin.
struct DockSkinDestination: View {
    let item: FluxDockItem
    let theme: FluxDockTheme
    let selected: Bool
    let focused: Bool
    /// Side of the tile, and size of the symbol in it.
    let side: CGFloat
    let glyph: CGFloat

    var body: some View {
        if theme.pixelated {
            DockSkinPixelTile(picture: item.pixelPicture, theme: theme, selected: selected, focused: focused, side: side)
        } else {
            vector
        }
    }

    @ViewBuilder private var vector: some View {
        let rgb = item.skinRGB
        switch theme {
        case .pebbles:
            let width = selected ? side * 1.34 : side
            Image(systemName: selected ? item.symbol : item.outlineSymbol)
                .font(.system(size: glyph * 0.92, weight: .medium))
                .foregroundStyle(rgb.darker(selected ? 0.66 : 0.55).color)
                .frame(width: width, height: side)
                .background(Capsule().fill(rgb.lighter(selected ? 0.42 : 0.64).color))
                .overlay(Capsule().strokeBorder(.white.opacity(focused ? 0.95 : 0), lineWidth: 2).allowsHitTesting(false))
                .frame(width: side, height: side)
        case .frost:
            let shape = RoundedRectangle(cornerRadius: side * 0.2, style: .continuous)
            Image(systemName: item.symbol)
                .font(.system(size: glyph * 1.06, weight: .regular))
                .foregroundStyle(LinearGradient(colors: [rgb.lighter(0.5).color, rgb.color], startPoint: .top, endPoint: .bottom))
                .frame(width: side, height: side)
                .background(shape.fill(.white.opacity(focused ? 0.17 : selected ? 0.10 : 0)))
                .overlay(shape.strokeBorder(.white.opacity(focused ? 0.55 : selected ? 0.09 : 0), lineWidth: 1).allowsHitTesting(false))
        case .gel:
            let shape = RoundedRectangle(cornerRadius: side * 0.30, style: .continuous)
            ZStack {
                shape.fill(LinearGradient(colors: [rgb.lighter(0.32).color, rgb.darker(0.2).color], startPoint: .top, endPoint: .bottom))
                Ellipse().fill(RadialGradient(colors: [.white.opacity(0.55), .clear], center: .center, startRadius: 0, endRadius: side * 0.42))
                    .frame(width: side * 0.9, height: side * 0.5).offset(y: side * 0.27)
                RoundedRectangle(cornerRadius: side * 0.24, style: .continuous)
                    .fill(LinearGradient(colors: [.white.opacity(0.9), .white.opacity(0.1)], startPoint: .top, endPoint: .bottom))
                    .frame(width: side * 0.84, height: side * 0.46).offset(y: -side * 0.2)
                Image(systemName: item.symbol).font(.system(size: glyph, weight: .bold)).foregroundStyle(.white)
                    .shadow(color: rgb.darker(0.6).color.opacity(0.8), radius: 1.2, y: 1)
            }
            .frame(width: side, height: side)
            .clipShape(shape)
            .overlay(shape.strokeBorder(rgb.darker(0.45).color.opacity(0.85), lineWidth: 1).allowsHitTesting(false))
            .overlay(shape.strokeBorder(.white.opacity(focused ? 0.95 : 0), lineWidth: 2).allowsHitTesting(false))
            .shadow(color: .black.opacity(0.3), radius: 3, y: 2)
        case .hills:
            let shape = RoundedRectangle(cornerRadius: side * 0.22, style: .continuous)
            Image(systemName: item.symbol).font(.system(size: glyph, weight: .heavy)).foregroundStyle(.white)
                .shadow(color: rgb.darker(0.65).color, radius: 0.6, x: 1, y: 1)
                .frame(width: side, height: side)
                .background(LinearGradient(colors: [rgb.lighter(0.45).color, rgb.color, rgb.darker(0.25).color],
                                           startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(alignment: .topLeading) {
                    Ellipse().fill(.white.opacity(0.42)).frame(width: side * 0.46, height: side * 0.2)
                        .offset(x: side * 0.1, y: side * 0.07).allowsHitTesting(false)
                }
                .clipShape(shape)
                .overlay(shape.strokeBorder(rgb.darker(0.5).color, lineWidth: 1).allowsHitTesting(false))
                .overlay(shape.strokeBorder(.white.opacity(focused ? 0.95 : 0), lineWidth: 2).allowsHitTesting(false))
                .background {
                    if selected {
                        RoundedRectangle(cornerRadius: side * 0.28, style: .continuous).fill(.white.opacity(0.22))
                            .overlay(RoundedRectangle(cornerRadius: side * 0.28, style: .continuous).strokeBorder(.white.opacity(0.4), lineWidth: 1))
                            .padding(-side * 0.1)
                    }
                }
                .shadow(color: .black.opacity(0.3), radius: 3, y: 2)
        default:
            // Tactile: a rounded square in its colours, the symbol in white.
            let shape = RoundedRectangle(cornerRadius: side * 0.225, style: .continuous)
            Image(systemName: item.symbol).font(.system(size: glyph, weight: .semibold)).foregroundStyle(.white)
                .shadow(color: .black.opacity(0.22), radius: 1, y: 1)
                .frame(width: side, height: side)
                .background(LinearGradient(colors: [rgb.lighter(0.3).color, rgb.darker(0.14).color], startPoint: .top, endPoint: .bottom), in: shape)
                .overlay(shape.strokeBorder(.white.opacity(0.24), lineWidth: 0.8).allowsHitTesting(false))
                .overlay(shape.strokeBorder(.white.opacity(focused ? 0.95 : 0), lineWidth: 2).allowsHitTesting(false))
                .shadow(color: .black.opacity(selected ? 0.36 : 0.26), radius: 4, y: 2)
        }
    }
}

/// A pixel picture on its tile, with the mark of a selection of its years:
/// a pressed button, a recess, colours turned round.
struct DockSkinPixelTile: View {
    let picture: DockPixelPicture
    let theme: FluxDockTheme
    let selected: Bool
    let focused: Bool
    let side: CGFloat
    /// The shortcuts of a folder chose a symbol; nil draws the picture.
    var symbol: String?

    var body: some View {
        let art = DockSkin.pixelSide(side)
        let dot = art / 16
        let pressed = selected && theme == .bevel
        ZStack {
            tile(dot: dot)
            Group {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: art * 0.56, weight: .bold))
                        .foregroundStyle(ink)
                        .frame(width: art, height: art)
                } else {
                    DockPixelIcon(picture: picture, palette: .of(theme, picture: picture, selected: selected), side: art)
                }
            }
            // A pressed button shows its picture a pixel lower and further right.
            .offset(x: pressed ? dot : 0, y: pressed ? dot : 0)
        }
        .frame(width: side, height: side)
        .overlay {
            if focused {
                Rectangle().strokeBorder(ring, style: StrokeStyle(lineWidth: max(1.5, dot * 0.7), dash: [max(2, dot), max(2, dot)]))
                    .padding(-dot * 0.6).allowsHitTesting(false)
            }
        }
    }

    private var ink: Color {
        switch theme {
        case .phosphor: selected ? .black : DockSkin.phosphorInk.color
        case .greenDesk: selected ? .white : .black
        case .fourColor: selected ? DockSkin.fourOrange.color : .white
        default: .black
        }
    }
    private var ring: Color {
        switch theme {
        case .phosphor: DockSkin.phosphorInk.color
        case .fourColor: .white
        default: .black
        }
    }

    @ViewBuilder private func tile(dot: CGFloat) -> some View {
        switch theme {
        case .bevel where selected:
            DockSkinPattern(image: DockPixelArt.checks, scale: 1)
                .overlay(SkinBevel(raised: false, line: max(1.5, dot * 0.5), light: .white, dark: .black,
                                   innerLight: Color(white: 0.87), innerDark: Color(white: 0.5)))
        case .eightColor where selected:
            Color(white: 0.56)
                .overlay(SkinBevel(raised: false, line: max(1.5, dot * 0.6), light: .white, dark: .black))
        case .phosphor where selected:
            DockSkin.phosphorInk.color
        case .greenDesk where selected:
            Color.black
        default:
            Color.clear
        }
    }
}

/// The folder of a skin: its titles, one behind the other, or its picture.
struct DockSkinFolder<Covers: View>: View {
    let theme: FluxDockTheme
    let selected: Bool
    let focused: Bool
    let side: CGFloat
    let glyph: CGFloat
    let symbol: String
    let empty: Bool
    @ViewBuilder let covers: () -> Covers

    var body: some View {
        if theme.pixelated {
            ZStack {
                if empty {
                    DockSkinPixelTile(picture: .folder, theme: theme, selected: selected, focused: focused, side: side,
                                      symbol: symbol == "folder.fill" ? nil : symbol)
                } else {
                    DockSkinPixelTile(picture: .folder, theme: theme, selected: selected, focused: focused, side: side)
                        .opacity(0.55)
                    covers()
                }
            }
            .frame(width: side, height: side)
        } else {
            let rgb = FluxDockItem.favorites.skinRGB
            let shape = RoundedRectangle(cornerRadius: DockSkin.radius(theme, side: side), style: .continuous)
            ZStack {
                switch theme {
                case .tactile, .gel, .hills:
                    shape.fill(LinearGradient(colors: [rgb.lighter(0.3).color, rgb.darker(0.16).color], startPoint: .top, endPoint: .bottom))
                case .pebbles:
                    Capsule().fill(rgb.lighter(0.64).color)
                default:
                    shape.fill(.white.opacity(selected ? 0.14 : 0.07))
                }
                if empty {
                    Image(systemName: symbol).font(.system(size: glyph, weight: .semibold))
                        .foregroundStyle(theme == .pebbles ? rgb.darker(0.55).color : theme == .frost ? rgb.color : .white)
                } else {
                    covers()
                }
            }
            .frame(width: side, height: side)
            .overlay(shape.strokeBorder(.white.opacity(focused ? 0.95 : 0), lineWidth: 2).allowsHitTesting(false))
        }
    }
}

/// The picture of a title in a skin: the colours of its screen.
struct DockSkinArtLook: ViewModifier {
    let theme: FluxDockTheme
    let side: CGFloat
    func body(content: Content) -> some View {
        switch theme {
        case .phosphor:
            content.grayscale(1).colorMultiply(DockSkin.phosphorInk.color)
                .overlay(Rectangle().strokeBorder(DockSkin.phosphorInk.color, lineWidth: max(1.5, side / 32)).allowsHitTesting(false))
        case .greenDesk:
            content.grayscale(1).contrast(1.5)
                .overlay(Rectangle().strokeBorder(.black, lineWidth: max(1.5, side / 32)).allowsHitTesting(false))
        case .fourColor:
            content.saturation(0.7)
                .overlay(Rectangle().strokeBorder(.white, lineWidth: max(1.5, side / 28)).allowsHitTesting(false))
        case .bevel, .eightColor:
            content.overlay(SkinBevel(raised: false, line: max(1.5, side / 32), light: .white, dark: Color(white: 0.3)))
        default:
            content
        }
    }
}

// MARK: Names and marks

/// The name under an icon, in the type and the colours of its skin.
struct DockSkinLabel: View {
    let text: String
    let theme: FluxDockTheme
    let selected: Bool
    let size: CGFloat
    var shrinks = true

    var body: some View {
        styled
            .lineLimit(1).minimumScaleFactor(shrinks ? 0.8 : 1).truncationMode(.tail)
    }

    @ViewBuilder private var styled: some View {
        switch theme {
        case .pebbles:
            Text(text).font(.system(size: size, weight: selected ? .bold : .medium))
                .foregroundStyle(Color(white: selected ? 1 : 0.86))
        case .frost:
            Text(text).font(.system(size: size, weight: .regular)).foregroundStyle(.white.opacity(selected ? 1 : 0.84))
                .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
        case .gel:
            Text(text).font(.system(size: size, weight: .semibold)).foregroundStyle(Color(white: 0.1))
                .shadow(color: .white.opacity(0.8), radius: 0, y: 1)
        case .hills:
            Text(text).font(.system(size: size, weight: .bold)).foregroundStyle(.white)
                .shadow(color: Color(red: 0, green: 0.1, blue: 0.4), radius: 0, x: 1, y: 1)
        case .bevel, .eightColor:
            Text(text).font(.system(size: size * 0.94, weight: .regular)).foregroundStyle(.black)
        case .fourColor:
            Text(text).font(.system(size: size * 0.94, weight: .bold, design: .monospaced))
                .foregroundStyle(selected ? DockSkin.fourOrange.color : .white)
        case .greenDesk:
            Text(text).font(.system(size: size * 0.9, weight: .regular, design: .monospaced))
                .foregroundStyle(selected ? .white : .black)
                .padding(.horizontal, size * 0.22)
                .background(selected ? Color.black : Color.white)
        case .phosphor:
            Text(text.uppercased()).font(.system(size: size * 0.9, weight: .bold, design: .monospaced))
                .foregroundStyle(selected ? Color.black : DockSkin.phosphorInk.color)
                .padding(.horizontal, size * 0.22)
                .background(selected ? DockSkin.phosphorInk.color : Color.clear)
        default:
            Text(text).font(.system(size: size, weight: .semibold)).foregroundStyle(.white)
                .shadow(color: .black.opacity(0.45), radius: 2, y: 1)
        }
    }
}

/// What marks the screen in front under its icon, where the skin has one.
struct DockSkinIndicator: View {
    let theme: FluxDockTheme
    let tint: Color
    let side: CGFloat
    let position: FluxDockPosition

    var body: some View {
        switch theme {
        case .tactile:
            Circle().fill(.white.opacity(0.92)).frame(width: max(4, side * 0.09), height: max(4, side * 0.09))
        case .frost:
            Capsule().fill(tint)
                .frame(width: position.isVertical ? max(3, side * 0.06) : side * 0.34,
                       height: position.isVertical ? side * 0.34 : max(3, side * 0.06))
        case .gel:
            SkinTriangle().fill(Color.black.opacity(0.78))
                .frame(width: side * 0.2, height: side * 0.11)
                .rotationEffect(.degrees(rotation))
        default:
            EmptyView()
        }
    }
    /// The triangle points to its icon, whatever edge holds the bar.
    private var rotation: Double {
        switch position {
        case .bottom, .corner: 0
        case .top: 180
        case .leading: 90
        case .trailing: -90
        }
    }
}
