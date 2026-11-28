import SwiftUI

// MARK: - The theme on the windows
//
// "theme dock super mais ça serai bien aussi que l'egfet neon soit sur
// toutes les fenetres aussi, en gros fait theme general pas que dock"
// (David, 28/11). Each theme of the dock lends the windows a plate in its
// manner: the column, the panels of the television, the fiches, the
// settings, the sheets and the messages. Inside, a plate stays dark, for
// the white of what is written on it; the theme is in its edge. Nothing is
// sampled or blurred but the glass that the app already draws, and a glow
// is a few strokes laid over each other, never a shadow, which a
// television would draw again with each picture. A plate is laid behind
// its window: the window keeps its size, and the remote its places.

/// The theme of the windows of the screen in front, and the colours of
/// that screen for the themes that take them.
struct FluxWindowLook: Equatable {
    let theme: FluxDockTheme
    let accent: Color
    let second: Color
}

private struct FluxWindowLookKey: EnvironmentKey {
    static let defaultValue: FluxWindowLook? = nil
}

extension EnvironmentValues {
    /// Set once by the screen (`FluxThemeScope`); nil keeps the glass of the app.
    var fluxWindowLook: FluxWindowLook? {
        get { self[FluxWindowLookKey.self] }
        set { self[FluxWindowLookKey.self] = newValue }
    }
}

extension View {
    /// A window of the app: the glass, or the plate of the theme.
    func fluxWindow(radius: CGFloat = 20) -> some View {
        modifier(FluxWindowChrome(radius: radius))
    }
}

private struct FluxWindowChrome: ViewModifier {
    @Environment(\.fluxWindowLook) private var look
    let radius: CGFloat

    @ViewBuilder func body(content: Content) -> some View {
        if let look {
            if look.theme.windowOnGlass {
                // The glass takes the window itself, as without a theme:
                // laid behind it on its own, the glass was drawn over what
                // the window holds, and blurred it. The tint and the edge
                // belong to the window too: an edge laid over the glass
                // afterwards went under it (bench of the 0.9.11).
                content
                    .background { FluxWindowTint(look: look, radius: radius) }
                    .overlay { FluxWindowRim(look: look, radius: radius) }
                    .fluxGlass(radius: look.theme.windowCorner(radius))
            } else {
                content.background { FluxWindowPlate(look: look, radius: radius) }
            }
        } else {
            content.fluxGlass(radius: radius)
        }
    }
}

extension FluxDockTheme {
    /// The themes that dress the glass of the app rather than replace it.
    var windowOnGlass: Bool { self == .vivid || self == .tactile || self == .frost || self == .nightGlass }
    /// The corner of a window in the theme, from the one the window asks for.
    func windowCorner(_ radius: CGFloat) -> CGFloat {
        switch self {
        case .tactile: radius * 1.25
        case .frost: radius * 0.45
        default: radius
        }
    }
}

/// What a theme on the glass lays between the glass and what the window holds.
private struct FluxWindowTint: View {
    let look: FluxWindowLook
    let radius: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: look.theme.windowCorner(radius), style: .continuous)
        switch look.theme {
        case .vivid:
            shape.fill(look.accent.opacity(0.07))
        case .tactile:
            shape.fill(.white.opacity(0.09))
        case .frost:
            shape.fill(Color(red: 0.13, green: 0.14, blue: 0.17).opacity(0.55))
        case .nightGlass:
            shape.fill(Color(red: 0.04, green: 0.07, blue: 0.20).opacity(0.55))
                .overlay(shape.fill(LinearGradient(colors: [.white.opacity(0.12), .white.opacity(0)], startPoint: .top,
                                                   endPoint: UnitPoint(x: 0.5, y: 0.3))))
        default:
            EmptyView()
        }
    }
}

/// The edge a theme on the glass draws around the window, above it.
private struct FluxWindowRim: View {
    let look: FluxWindowLook
    let radius: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: look.theme.windowCorner(radius), style: .continuous)
        Group {
            switch look.theme {
            case .vivid:
                // Ringed in the two colours of the screen, as its tiles are filled with them.
                shape.strokeBorder(LinearGradient(colors: [look.accent, look.second], startPoint: .topLeading,
                                                  endPoint: .bottomTrailing), lineWidth: Desk.pt(2))
            case .tactile:
                shape.strokeBorder(.white.opacity(0.32), lineWidth: 1)
            case .frost:
                shape.strokeBorder(.white.opacity(0.14), lineWidth: 1)
            case .nightGlass:
                shape.strokeBorder(Color(red: 0.78, green: 0.83, blue: 1.0).opacity(0.45), lineWidth: 1)
            default:
                EmptyView()
            }
        }
        .allowsHitTesting(false)
    }
}

/// The plate of a window in the manner of a theme that replaces the glass.
private struct FluxWindowPlate: View {
    let look: FluxWindowLook
    let radius: CGFloat

    var body: some View {
        let round = RoundedRectangle(cornerRadius: radius, style: .continuous)
        switch look.theme {
        case .glass, .floating, .vivid, .tactile, .frost, .nightGlass:
            // Drawn on the glass by the window itself.
            EmptyView()
        case .smoked:
            round.fill(Color(red: 0.035, green: 0.04, blue: 0.055).opacity(0.86))
                .overlay(round.strokeBorder(.white.opacity(0.14), lineWidth: 1))
        case .neon:
            FluxNeonPlate(shape: round, fill: Color(red: 0.02, green: 0.025, blue: 0.06).opacity(0.9),
                          colours: [look.accent, look.second])
        case .pebbles:
            let soft = RoundedRectangle(cornerRadius: radius * 1.6, style: .continuous)
            soft.fill(Color(red: 0.11, green: 0.12, blue: 0.15).opacity(0.94))
                .overlay(soft.strokeBorder(.white.opacity(0.08), lineWidth: 1))
        case .gel:
            // Fine dark stripes under a gloss, in a bright rim: 2001, at night.
            let shape = RoundedRectangle(cornerRadius: radius * 0.5, style: .continuous)
            DockSkinPattern(image: DockPixelArt.stripes([(SkinRGB(0.15, 0.16, 0.18), 0.96), (SkinRGB(0.15, 0.16, 0.18), 0.96),
                                                         (SkinRGB(0.11, 0.12, 0.14), 0.96), (SkinRGB(0.11, 0.12, 0.14), 0.96)],
                                                        key: "window-pinstripes"))
                .clipShape(shape)
                .overlay(shape.fill(LinearGradient(colors: [.white.opacity(0.14), .white.opacity(0)], startPoint: .top,
                                                   endPoint: UnitPoint(x: 0.5, y: 0.22))))
                .overlay(shape.strokeBorder(.white.opacity(0.8), lineWidth: 1))
                .overlay(shape.inset(by: 1).strokeBorder(.black.opacity(0.45), lineWidth: 1))
        case .hills:
            // The blue of the bar, deep enough for what is written in white.
            let shape = RoundedRectangle(cornerRadius: radius * 0.4, style: .continuous)
            shape.fill(LinearGradient(colors: [Color(red: 0.13, green: 0.30, blue: 0.72), Color(red: 0.07, green: 0.18, blue: 0.50),
                                               Color(red: 0.05, green: 0.13, blue: 0.40)], startPoint: .top, endPoint: .bottom))
                .overlay(shape.strokeBorder(LinearGradient(colors: [Color(red: 0.64, green: 0.80, blue: 1.0), .clear],
                                                           startPoint: .top, endPoint: .center), lineWidth: 1.5))
                .overlay(shape.strokeBorder(Color(red: 0.04, green: 0.12, blue: 0.40), lineWidth: 1))
        case .bevel:
            FluxReliefFrame(band: Desk.pt(5), face: DockSkin.silver.color,
                            pane: Color(red: 0.10, green: 0.105, blue: 0.12).opacity(0.97),
                            line: Desk.pt(1.5), shade: Color(white: 0.5))
        case .eightColor:
            FluxReliefFrame(band: Desk.pt(5), face: DockSkin.workbenchGrey.color,
                            pane: Color(red: 0.0, green: 0.17, blue: 0.40).opacity(0.97),
                            line: Desk.pt(2), shade: .black)
        case .fourColor:
            // Its blue holds white writing as well as its time did.
            DockSkin.fourBlue.color.opacity(0.97)
                .overlay(Rectangle().strokeBorder(.white, lineWidth: Desk.pt(3)))
                .overlay(Rectangle().inset(by: Desk.pt(3)).strokeBorder(Color(red: 0, green: 0, blue: 0.13), lineWidth: Desk.pt(1.5)))
        case .greenDesk:
            Color.black.opacity(0.93)
                .overlay(Rectangle().strokeBorder(DockSkin.deskGreen.color, lineWidth: Desk.pt(5)))
                .overlay(Rectangle().strokeBorder(.black, lineWidth: Desk.pt(1.5)))
                .overlay(Rectangle().inset(by: Desk.pt(5)).strokeBorder(.white, lineWidth: Desk.pt(1)))
        case .phosphor:
            FluxNeonPlate(shape: Rectangle(), fill: Color(red: 0, green: 0.035, blue: 0.01).opacity(0.96),
                          colours: [DockSkin.phosphorInk.color, DockSkin.phosphorInk.color], core: false)
                .overlay(DockSkinPattern(image: DockPixelArt.stripes([(.black, 0), (.black, 0), (.black, 0.35), (.black, 0.35)],
                                                                     key: "scanlines")))
        case .neon90:
            FluxNeonPlate(shape: round, fill: Color(red: 0.09, green: 0.03, blue: 0.16).opacity(0.94),
                          colours: [Color(red: 0.98, green: 0.22, blue: 0.78), Color(red: 0.10, green: 0.85, blue: 0.98)])
        case .artDeco:
            // Copper, twice, around corners cut as a frame of the time is.
            let cut = max(Desk.pt(8), min(radius * 0.6, Desk.pt(16)))
            let copper = Color(red: 0.80, green: 0.55, blue: 0.33)
            FluxChamferedRectangle(cut: cut).fill(Color(red: 0.035, green: 0.07, blue: 0.06).opacity(0.95))
                .overlay(FluxChamferedRectangle(cut: cut).strokeBorder(copper, lineWidth: Desk.pt(1.5)))
                .overlay(FluxChamferedRectangle(cut: cut * 0.7).strokeBorder(copper.opacity(0.6), lineWidth: Desk.pt(0.75))
                    .padding(Desk.pt(4)))
        }
    }
}

/// A dark pane in a tube of light: the same line three times, wide and
/// faint to narrow and bright, in place of a shadow; a thin white core
/// gives a tube its heat.
private struct FluxNeonPlate<S: InsettableShape>: View {
    let shape: S
    let fill: Color
    let colours: [Color]
    var core = true

    var body: some View {
        func edge(_ opacity: Double) -> LinearGradient {
            LinearGradient(colors: colours.map { $0.opacity(opacity) }, startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        return shape.fill(fill)
            .overlay(shape.stroke(edge(0.10), lineWidth: Desk.pt(9)))
            .overlay(shape.stroke(edge(0.22), lineWidth: Desk.pt(4.5)))
            .overlay(shape.stroke(edge(1), lineWidth: Desk.pt(1.8)))
            .overlay(shape.stroke(Color.white.opacity(core ? 0.55 : 0), lineWidth: Desk.pt(0.6)))
    }
}

/// A grey frame in relief around a dark pane, as the windows of their
/// years drew their edges: lit above and on the left, shaded below and on
/// the right, and the pane sunk into it.
private struct FluxReliefFrame: View {
    let band: CGFloat
    let face: Color
    let pane: Color
    let line: CGFloat
    let shade: Color

    var body: some View {
        face
            .overlay(pane.padding(band))
            .overlay(FluxReliefEdges(line: line, lit: .white, shaded: shade))
            .overlay(FluxReliefEdges(line: line, lit: shade, shaded: .white).padding(band - line))
    }
}

/// Four bands: two lit, two shaded. Drawn as plain fills, not on a canvas
/// as large as the window.
private struct FluxReliefEdges: View {
    let line: CGFloat
    let lit: Color
    let shaded: Color

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                lit.frame(height: line)
                Spacer(minLength: 0)
                shaded.frame(height: line)
            }
            HStack(spacing: 0) {
                lit.frame(width: line)
                Spacer(minLength: 0)
                shaded.frame(width: line)
            }
        }
        .allowsHitTesting(false)
    }
}

/// A rectangle whose corners are cut on the diagonal.
struct FluxChamferedRectangle: InsettableShape {
    var cut: CGFloat
    var inset: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: inset, dy: inset)
        let c = max(0, min(cut - inset * 0.4, min(r.width, r.height) / 2))
        var path = Path()
        path.move(to: CGPoint(x: r.minX + c, y: r.minY))
        path.addLine(to: CGPoint(x: r.maxX - c, y: r.minY))
        path.addLine(to: CGPoint(x: r.maxX, y: r.minY + c))
        path.addLine(to: CGPoint(x: r.maxX, y: r.maxY - c))
        path.addLine(to: CGPoint(x: r.maxX - c, y: r.maxY))
        path.addLine(to: CGPoint(x: r.minX + c, y: r.maxY))
        path.addLine(to: CGPoint(x: r.minX, y: r.maxY - c))
        path.addLine(to: CGPoint(x: r.minX, y: r.minY + c))
        path.closeSubpath()
        return path
    }

    func inset(by amount: CGFloat) -> FluxChamferedRectangle {
        var shape = self
        shape.inset += amount
        return shape
    }
}
