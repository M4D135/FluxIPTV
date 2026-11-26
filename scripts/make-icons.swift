// Draws the icons of FLUX IPTV from code: the Mac and iPhone icon, the
// layered icon of the Apple TV and its Top Shelf images. Nothing is taken
// from a font or a symbol set: the television, the play mark and the
// letters of the name are drawn here.
//
//   swift scripts/make-icons.swift [repository]
//
// writes FluxIPTVMac/Assets.xcassets (Mac, iPhone, iPad) and
// FluxIPTVMac/AssetsTV.xcassets (Apple TV) with their Contents.json files.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let repository = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath)
let space = CGColorSpace(name: CGColorSpace.sRGB)!

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [CGFloat((hex >> 16) & 0xFF) / 255, CGFloat((hex >> 8) & 0xFF) / 255,
                                            CGFloat(hex & 0xFF) / 255, alpha])!
}

// The neon of the name and of the television, from the cyan of the
// application to the magenta of the video club.
let cyan: UInt32 = 0x2BE4FF, violet: UInt32 = 0x7B61FF, magenta: UInt32 = 0xFF3FA8
let neon = CGGradient(colorsSpace: space, colors: [rgb(cyan), rgb(violet), rgb(magenta)] as CFArray, locations: [0, 0.52, 1])!

/// A canvas whose origin is the top left corner, as the design is written.
func canvas(_ width: Int, _ height: Int, opaque: Bool) -> CGContext {
    let info = opaque ? CGImageAlphaInfo.noneSkipLast.rawValue : CGImageAlphaInfo.premultipliedLast.rawValue
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: space, bitmapInfo: info)!
    context.translateBy(x: 0, y: CGFloat(height))
    context.scaleBy(x: 1, y: -1)
    context.setShouldAntialias(true)
    context.interpolationQuality = .high
    return context
}

/// PNG, or JPEG for the wide opaque pictures of the Top Shelf, whose
/// gradients would weigh several megabytes as PNG.
func save(_ context: CGContext, _ url: URL) {
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let jpeg = url.pathExtension == "jpg"
    let destination = CGImageDestinationCreateWithURL(url as CFURL, (jpeg ? UTType.jpeg : UTType.png).identifier as CFString, 1, nil)!
    let options = jpeg ? [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary : nil
    CGImageDestinationAddImage(destination, context.makeImage()!, options)
    guard CGImageDestinationFinalize(destination) else { fatalError("Could not write \(url.path)") }
}

func json(_ object: Any, _ url: URL) {
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let data = try! JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    try! data.write(to: url)
}

let xcode: [String: Any] = ["author": "xcode", "version": 1]

// MARK: - Drawing

/// Night of a cinema: deep indigo above, almost black below, a cyan light
/// from the top left and a magenta one from the bottom right.
func sky(_ c: CGContext, _ rect: CGRect) {
    let night = CGGradient(colorsSpace: space, colors: [rgb(0x1C1550), rgb(0x0C0B26), rgb(0x05060F)] as CFArray,
                           locations: [0, 0.58, 1])!
    c.drawLinearGradient(night, start: CGPoint(x: rect.midX, y: rect.minY), end: CGPoint(x: rect.midX, y: rect.maxY), options: [])
    let size = max(rect.width, rect.height)
    let cyanLight = CGGradient(colorsSpace: space, colors: [rgb(0x19C8EE, 0.42), rgb(0x19C8EE, 0)] as CFArray, locations: [0, 1])!
    c.drawRadialGradient(cyanLight, startCenter: CGPoint(x: rect.minX + rect.width * 0.18, y: rect.minY + rect.height * 0.1),
                         startRadius: 0, endCenter: CGPoint(x: rect.minX + rect.width * 0.18, y: rect.minY + rect.height * 0.1),
                         endRadius: size * 0.72, options: [])
    let magentaLight = CGGradient(colorsSpace: space, colors: [rgb(0xFF2E93, 0.34), rgb(0xFF2E93, 0)] as CFArray, locations: [0, 1])!
    c.drawRadialGradient(magentaLight, startCenter: CGPoint(x: rect.maxX - rect.width * 0.12, y: rect.maxY - rect.height * 0.08),
                         startRadius: 0, endCenter: CGPoint(x: rect.maxX - rect.width * 0.12, y: rect.maxY - rect.height * 0.08),
                         endRadius: size * 0.7, options: [])
}

/// A floor of neon lines that runs to the horizon, as in the decors of
/// the video club.
func floor(_ c: CGContext, _ rect: CGRect, horizon: CGFloat, strength: CGFloat = 1) {
    c.saveGState()
    c.clip(to: CGRect(x: rect.minX, y: horizon, width: rect.width, height: rect.maxY - horizon))
    c.beginTransparencyLayer(auxiliaryInfo: nil)
    let depth = rect.maxY - horizon
    let line = max(1, rect.height / 340)
    c.setLineWidth(line)
    c.setLineCap(.round)
    // Lines across, closer together toward the horizon.
    for step in 1...9 {
        let t = pow(CGFloat(step) / 9, 2.1)
        let y = horizon + depth * t
        c.setStrokeColor(rgb(magenta, 0.10 + 0.32 * t * strength))
        c.move(to: CGPoint(x: rect.minX, y: y)); c.addLine(to: CGPoint(x: rect.maxX, y: y)); c.strokePath()
    }
    // Lines toward the vanishing point.
    let vanish = CGPoint(x: rect.midX, y: horizon - depth * 0.35)
    for step in -12...12 {
        let x = rect.midX + CGFloat(step) * rect.width * 0.11
        c.setStrokeColor(rgb(violet, 0.30 * strength))
        let bottom = CGPoint(x: x, y: rect.maxY)
        let ratio = (horizon - vanish.y) / (bottom.y - vanish.y)
        let top = CGPoint(x: vanish.x + (bottom.x - vanish.x) * ratio, y: horizon)
        c.move(to: top); c.addLine(to: bottom); c.strokePath()
    }
    // The lines fade into the night toward the horizon: only their own
    // light is taken away, nothing is painted over the sky.
    c.setBlendMode(.destinationIn)
    let fade = CGGradient(colorsSpace: space, colors: [rgb(0xFFFFFF, 0), rgb(0xFFFFFF, 1)] as CFArray, locations: [0, 1])!
    c.drawLinearGradient(fade, start: CGPoint(x: rect.midX, y: horizon), end: CGPoint(x: rect.midX, y: horizon + depth * 0.55),
                         options: [.drawsAfterEndLocation])
    c.endTransparencyLayer()
    c.restoreGState()
    // A glow along the horizon, soft above and below.
    let band = depth * 0.24
    let glow = CGGradient(colorsSpace: space, colors: [rgb(magenta, 0), rgb(magenta, 0.24 * strength), rgb(magenta, 0)] as CFArray,
                          locations: [0, 0.5, 1])!
    c.drawLinearGradient(glow, start: CGPoint(x: rect.midX, y: horizon - band), end: CGPoint(x: rect.midX, y: horizon + band), options: [])
}

/// A neon tube along a path: its glow, its colour from cyan to magenta
/// across `span`, and a white core.
func tube(_ c: CGContext, _ path: CGPath, width: CGFloat, span: CGRect, glow: CGFloat, core: Bool = true) {
    c.saveGState()
    c.setLineCap(.round); c.setLineJoin(.round)
    c.setLineWidth(width)
    c.setShadow(offset: .zero, blur: glow, color: rgb(violet, 0.95))
    c.setStrokeColor(rgb(violet, 0.9))
    c.addPath(path); c.strokePath()
    c.setShadow(offset: .zero, blur: glow * 0.45, color: rgb(cyan, 0.6))
    c.addPath(path); c.strokePath()
    c.restoreGState()
    c.saveGState()
    c.setLineCap(.round); c.setLineJoin(.round)
    c.setLineWidth(width)
    c.addPath(path); c.replacePathWithStrokedPath(); c.clip()
    c.drawLinearGradient(neon, start: CGPoint(x: span.minX, y: span.minY), end: CGPoint(x: span.maxX, y: span.maxY), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    c.restoreGState()
    if core {
        c.saveGState()
        c.setLineCap(.round); c.setLineJoin(.round)
        c.setLineWidth(width * 0.32)
        c.setStrokeColor(rgb(0xFFFFFF, 0.78))
        c.addPath(path); c.strokePath()
        c.restoreGState()
    }
}

/// The television: a screen of neon on a foot. `unit` is the height of the
/// whole mark, which `center` places.
func television(_ c: CGContext, center: CGPoint, unit: CGFloat, bold: Bool = false) {
    let s = unit / 700
    let width: CGFloat = (bold ? 84 : 58) * s
    let screen = CGRect(x: center.x - 320 * s, y: center.y - 300 * s, width: 640 * s, height: 440 * s)
    let frame = CGPath(roundedRect: screen, cornerWidth: 96 * s, cornerHeight: 96 * s, transform: nil)
    tube(c, frame, width: width, span: screen, glow: (bold ? 18 : 46) * s, core: !bold)
    let foot = CGMutablePath()
    foot.move(to: CGPoint(x: center.x - 120 * s, y: center.y + 250 * s))
    foot.addLine(to: CGPoint(x: center.x + 120 * s, y: center.y + 250 * s))
    tube(c, foot, width: width * 0.86, span: screen, glow: (bold ? 14 : 36) * s, core: !bold)
}

/// What plays: a triangle with round corners, and the lines of the flux
/// that it leaves behind it.
func play(_ c: CGContext, center: CGPoint, unit: CGFloat, bold: Bool = false) {
    let s = unit / 700
    let cx = center.x, cy = center.y - 80 * s
    let a = CGPoint(x: cx - 62 * s, y: cy - 118 * s), b = CGPoint(x: cx - 62 * s, y: cy + 118 * s), d = CGPoint(x: cx + 142 * s, y: cy)
    let triangle = CGMutablePath()
    let radius = 30 * s
    triangle.move(to: CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2))
    triangle.addArc(tangent1End: b, tangent2End: d, radius: radius)
    triangle.addArc(tangent1End: d, tangent2End: a, radius: radius)
    triangle.addArc(tangent1End: a, tangent2End: b, radius: radius)
    triangle.closeSubpath()
    c.saveGState()
    c.setShadow(offset: .zero, blur: (bold ? 10 : 40) * s, color: rgb(0xBFF7FF, 0.9))
    c.setFillColor(rgb(0xFFFFFF))
    c.addPath(triangle); c.fillPath()
    c.restoreGState()
    c.saveGState()
    c.addPath(triangle); c.clip()
    let shine = CGGradient(colorsSpace: space, colors: [rgb(0xFFFFFF), rgb(0xC9F6FF)] as CFArray, locations: [0, 1])!
    c.drawLinearGradient(shine, start: CGPoint(x: cx, y: a.y), end: CGPoint(x: cx, y: b.y), options: [])
    c.restoreGState()
    guard !bold else { return }
    // Three lines of flux, longer in the middle, that fade behind it.
    for (index, offset) in [-62, 0, 62].enumerated() {
        let y = cy + CGFloat(offset) * s
        let length: CGFloat = index == 1 ? 150 : 104
        let end = a.x - 30 * s
        let line = CGMutablePath()
        line.move(to: CGPoint(x: end - length * s, y: y)); line.addLine(to: CGPoint(x: end, y: y))
        c.saveGState()
        c.setLineCap(.round); c.setLineWidth(24 * s)
        c.addPath(line); c.replacePathWithStrokedPath(); c.clip()
        let trail = CGGradient(colorsSpace: space, colors: [rgb(cyan, 0), rgb(0xFFFFFF, 0.92)] as CFArray, locations: [0, 1])!
        c.drawLinearGradient(trail, start: CGPoint(x: end - length * s, y: y), end: CGPoint(x: end, y: y), options: [])
        c.restoreGState()
    }
}

/// The letters of the name, drawn as strokes of a height of 100.
func letter(_ character: Character) -> (path: CGMutablePath, width: CGFloat) {
    let p = CGMutablePath()
    switch character {
    case "F":
        p.move(to: CGPoint(x: 58, y: 0)); p.addLine(to: CGPoint(x: 0, y: 0)); p.addLine(to: CGPoint(x: 0, y: 100))
        p.move(to: CGPoint(x: 0, y: 48)); p.addLine(to: CGPoint(x: 44, y: 48))
        return (p, 58)
    case "L":
        p.move(to: CGPoint(x: 0, y: 0)); p.addLine(to: CGPoint(x: 0, y: 100)); p.addLine(to: CGPoint(x: 56, y: 100))
        return (p, 56)
    case "U":
        p.move(to: CGPoint(x: 0, y: 0)); p.addLine(to: CGPoint(x: 0, y: 64))
        p.addQuadCurve(to: CGPoint(x: 32, y: 100), control: CGPoint(x: 0, y: 100))
        p.addQuadCurve(to: CGPoint(x: 64, y: 64), control: CGPoint(x: 64, y: 100))
        p.addLine(to: CGPoint(x: 64, y: 0))
        return (p, 64)
    case "X":
        p.move(to: CGPoint(x: 0, y: 0)); p.addLine(to: CGPoint(x: 66, y: 100))
        p.move(to: CGPoint(x: 66, y: 0)); p.addLine(to: CGPoint(x: 0, y: 100))
        return (p, 66)
    case "I":
        p.move(to: CGPoint(x: 0, y: 0)); p.addLine(to: CGPoint(x: 0, y: 100))
        return (p, 0)
    case "P":
        p.move(to: CGPoint(x: 0, y: 100)); p.addLine(to: CGPoint(x: 0, y: 0)); p.addLine(to: CGPoint(x: 30, y: 0))
        p.addCurve(to: CGPoint(x: 30, y: 56), control1: CGPoint(x: 66, y: 0), control2: CGPoint(x: 66, y: 56))
        p.addLine(to: CGPoint(x: 0, y: 56))
        return (p, 52)
    case "T":
        p.move(to: CGPoint(x: 0, y: 0)); p.addLine(to: CGPoint(x: 60, y: 0))
        p.move(to: CGPoint(x: 30, y: 0)); p.addLine(to: CGPoint(x: 30, y: 100))
        return (p, 60)
    case "V":
        p.move(to: CGPoint(x: 0, y: 0)); p.addLine(to: CGPoint(x: 33, y: 100)); p.addLine(to: CGPoint(x: 66, y: 0))
        return (p, 66)
    default:
        return (p, 40)
    }
}

/// A word of those letters: its strokes placed for a height `height`,
/// with `tracking` between letters, and its width.
func word(_ text: String, height: CGFloat, tracking: CGFloat) -> (path: CGMutablePath, width: CGFloat) {
    let path = CGMutablePath()
    var x: CGFloat = 0
    let scale = height / 100
    for (index, character) in text.enumerated() {
        let (glyph, width) = letter(character)
        path.addPath(glyph, transform: CGAffineTransform(a: scale, b: 0, c: 0, d: scale, tx: x, ty: 0))
        x += width * scale + (index == text.count - 1 ? 0 : tracking)
    }
    return (path, x)
}

func place(_ path: CGPath, at origin: CGPoint) -> CGPath {
    var move = CGAffineTransform(translationX: origin.x, y: origin.y)
    return path.copy(using: &move)!
}

/// The Top Shelf: the television on the left, the name on the right.
func shelf(_ width: Int, _ height: Int) -> CGContext {
    let c = canvas(width, height, opaque: true)
    let rect = CGRect(x: 0, y: 0, width: width, height: height)
    sky(c, rect)
    floor(c, rect, horizon: rect.height * 0.77, strength: 0.9)
    let h = rect.height
    let name = word("FLUX", height: h * 0.27, tracking: h * 0.085)
    let tag = word("IPTV", height: h * 0.085, tracking: h * 0.06)
    let mark = h * 0.62
    let gap = h * 0.16
    let markWidth = mark * 640 / 700 + h * 0.05
    let total = markWidth + gap + name.width
    let left = (rect.width - total) / 2
    let center = CGPoint(x: left + markWidth / 2, y: h * 0.52)
    television(c, center: CGPoint(x: center.x, y: center.y + mark * 0.06), unit: mark)
    play(c, center: CGPoint(x: center.x, y: center.y + mark * 0.06), unit: mark)
    let textLeft = left + markWidth + gap
    let top = h * 0.28
    let stroke = h * 0.27 * 0.17
    tube(c, place(name.path, at: CGPoint(x: textLeft, y: top)), width: stroke,
         span: CGRect(x: textLeft, y: top, width: name.width, height: h * 0.27), glow: h * 0.05)
    c.saveGState()
    c.setLineCap(.round); c.setLineJoin(.round); c.setLineWidth(h * 0.085 * 0.16)
    c.setStrokeColor(rgb(0xBFF4FF, 0.86))
    c.setShadow(offset: .zero, blur: h * 0.02, color: rgb(cyan, 0.8))
    c.addPath(place(tag.path, at: CGPoint(x: textLeft + h * 0.01, y: top + h * 0.27 + h * 0.075))); c.strokePath()
    c.restoreGState()
    return c
}

/// The plate of a Mac icon: a rounded square on the grid of macOS, with
/// its shadow, holding the night and the television.
func plate(_ size: Int) -> CGContext {
    let c = canvas(size, size, opaque: false)
    let s = CGFloat(size) / 1024
    let body = CGRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let shape = squircle(body)
    let small = size <= 64
    c.saveGState()
    c.setShadow(offset: CGSize(width: 0, height: 10 * s), blur: 22 * s, color: rgb(0x000000, 0.35))
    c.setFillColor(rgb(0x0C0B26))
    c.addPath(shape); c.fillPath()
    c.restoreGState()
    c.saveGState()
    c.addPath(shape); c.clip()
    sky(c, body)
    if !small { floor(c, body, horizon: body.minY + body.height * 0.78, strength: 0.8) }
    let center = CGPoint(x: body.midX, y: body.midY + body.height * 0.06)
    television(c, center: center, unit: body.height * (small ? 0.74 : 0.68), bold: small)
    play(c, center: center, unit: body.height * (small ? 0.74 : 0.68), bold: small)
    c.restoreGState()
    // A light edge on the glass of the plate.
    c.saveGState()
    c.setLineWidth(max(1, 3 * s)); c.setStrokeColor(rgb(0xFFFFFF, 0.12))
    c.addPath(shape); c.strokePath()
    c.restoreGState()
    return c
}

/// A continuous corner, as on the icons of macOS: a superellipse.
func squircle(_ rect: CGRect) -> CGPath {
    let path = CGMutablePath()
    let n: CGFloat = 5
    let steps = 720
    for step in 0...steps {
        let t = CGFloat(step) / CGFloat(steps) * 2 * .pi
        let cosT = cos(t), sinT = sin(t)
        let x = pow(abs(cosT), 2 / n) * (cosT < 0 ? -1 : 1)
        let y = pow(abs(sinT), 2 / n) * (sinT < 0 ? -1 : 1)
        let point = CGPoint(x: rect.midX + x * rect.width / 2, y: rect.midY + y * rect.height / 2)
        if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
    }
    path.closeSubpath()
    return path
}

/// The icon of an iPhone and an iPad: the night to the edges, without
/// transparency; the system rounds its corners.
func phone(_ size: Int) -> CGContext {
    let c = canvas(size, size, opaque: true)
    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    sky(c, rect)
    floor(c, rect, horizon: rect.height * 0.78, strength: 0.8)
    let center = CGPoint(x: rect.midX, y: rect.midY + rect.height * 0.06)
    television(c, center: center, unit: rect.height * 0.6)
    play(c, center: center, unit: rect.height * 0.6)
    return c
}

/// The three layers of the icon of an Apple TV, which tvOS moves apart
/// under the thumb: the night and its floor, the television, what plays.
func tvLayer(_ layer: String, _ width: Int, _ height: Int) -> CGContext {
    let c = canvas(width, height, opaque: layer == "Back")
    let rect = CGRect(x: 0, y: 0, width: width, height: height)
    let center = CGPoint(x: rect.midX, y: rect.midY + rect.height * 0.07)
    let unit = rect.height * 0.7
    switch layer {
    case "Back":
        sky(c, rect)
        floor(c, rect, horizon: rect.height * 0.74)
    case "Middle":
        television(c, center: center, unit: unit)
    default:
        play(c, center: center, unit: unit)
    }
    return c
}

// MARK: - Catalogs

let shared = repository.appendingPathComponent("FluxIPTVMac/Assets.xcassets")
let television = repository.appendingPathComponent("FluxIPTVMac/AssetsTV.xcassets")
for catalog in [shared, television] {
    try? FileManager.default.removeItem(at: catalog)
    json(["info": xcode], catalog.appendingPathComponent("Contents.json"))
}

// Mac and iPhone.
let appIcon = shared.appendingPathComponent("AppIcon.appiconset")
var images: [[String: Any]] = []
save(phone(1024), appIcon.appendingPathComponent("ios-1024.png"))
images.append(["filename": "ios-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"])
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "mac-\(points)@\(scale)x.png"
        save(plate(points * scale), appIcon.appendingPathComponent(name))
        images.append(["filename": name, "idiom": "mac", "scale": "\(scale)x", "size": "\(points)x\(points)"])
    }
}
json(["images": images, "info": xcode], appIcon.appendingPathComponent("Contents.json"))

// Apple TV.
let brand = television.appendingPathComponent("App Icon & Top Shelf Image.brandassets")
for (stack, sizes) in [("App Icon", [(400, 240, 1), (800, 480, 2)]), ("App Icon - App Store", [(1280, 768, 1)])] {
    let folder = brand.appendingPathComponent("\(stack).imagestack")
    for layer in ["Front", "Middle", "Back"] {
        let set = folder.appendingPathComponent("\(layer).imagestacklayer/Content.imageset")
        var entries: [[String: Any]] = []
        for (width, height, scale) in sizes {
            let name = "\(layer.lowercased())-\(width).png"
            save(tvLayer(layer, width, height), set.appendingPathComponent(name))
            entries.append(["filename": name, "idiom": "tv", "scale": "\(scale)x"])
        }
        json(["images": entries, "info": xcode], set.appendingPathComponent("Contents.json"))
        json(["info": xcode], folder.appendingPathComponent("\(layer).imagestacklayer/Contents.json"))
    }
    json(["info": xcode, "layers": ["Front", "Middle", "Back"].map { ["filename": "\($0).imagestacklayer"] }],
         folder.appendingPathComponent("Contents.json"))
}
for (set, sizes) in [("Top Shelf Image", [(1920, 720, 1), (3840, 1440, 2)]), ("Top Shelf Image Wide", [(2320, 720, 1), (4640, 1440, 2)])] {
    let folder = brand.appendingPathComponent("\(set).imageset")
    var entries: [[String: Any]] = []
    for (width, height, scale) in sizes {
        let name = "shelf-\(width).jpg"
        save(shelf(width, height), folder.appendingPathComponent(name))
        entries.append(["filename": name, "idiom": "tv", "scale": "\(scale)x"])
    }
    json(["images": entries, "info": xcode], folder.appendingPathComponent("Contents.json"))
}
json(["assets": [
    ["filename": "App Icon - App Store.imagestack", "idiom": "tv", "role": "primary-app-icon", "size": "1280x768"],
    ["filename": "App Icon.imagestack", "idiom": "tv", "role": "primary-app-icon", "size": "400x240"],
    ["filename": "Top Shelf Image Wide.imageset", "idiom": "tv", "role": "top-shelf-image-wide", "size": "2320x720"],
    ["filename": "Top Shelf Image.imageset", "idiom": "tv", "role": "top-shelf-image", "size": "1920x720"],
], "info": xcode], brand.appendingPathComponent("Contents.json"))
print("Icons drawn in \(shared.path) and \(television.path)")
