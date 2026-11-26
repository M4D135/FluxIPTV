import SwiftUI

/// tvOS PlainButtonStyle can add a focus platter. Controls that draw their own
/// focus treatment use this explicit label-only style, including the invisible
/// Select target above a playing video.
struct FluxBareButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.82 : 1)
    }
}

/// A control that draws nothing of its own for the focus. On a television a
/// white ring shows where the remote stands; elsewhere it is the bare style.
struct DeskFocusStyle: ButtonStyle {
    var radius: CGFloat = 12

    func makeBody(configuration: Configuration) -> some View {
        Ring(configuration: configuration, radius: radius)
    }

    private struct Ring: View {
        let configuration: ButtonStyleConfiguration
        let radius: CGFloat
        @Environment(\.isFocused) private var isFocused
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        #if os(macOS)
        @State private var hovered = false
        /// The keyboard of the settings is on this control.
        @Environment(\.deskTargeted) private var targeted
        #endif

        var body: some View {
            configuration.label
                .opacity(configuration.isPressed ? 0.82 : 1)
                #if os(tvOS)
                .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(.white.opacity(isFocused ? 0.92 : 0), lineWidth: 3).allowsHitTesting(false))
                .scaleEffect(isFocused && !reduceMotion ? 1.02 : 1)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isFocused)
                #elseif os(macOS)
                // A pointer shows what it is on, as the remote does; the
                // keyboard shows the ring of a television.
                .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(.white.opacity(targeted ? 0.92 : hovered ? 0.6 : 0), lineWidth: targeted ? 3 : 2).allowsHitTesting(false))
                .scaleEffect(targeted && !reduceMotion ? 1.02 : 1)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: targeted)
                .onHover { hovered = $0 }
                #endif
        }
    }
}

/// A part of a screen that is rebuilt only when what it shows changes.
/// The screen keeps its state in one place, and any change of that state
/// rebuilds all of it: a move of the remote used to rebuild every sleeve,
/// row and button five times. A part gives here the values it is drawn
/// from; it is left alone while they are the same. Its actions read the
/// state when they run, not when they were built.
struct FluxStable<Key: Equatable, Content: View>: View, Equatable {
    let key: Key
    let content: () -> Content

    init(_ key: Key, @ViewBuilder content: @escaping () -> Content) {
        self.key = key
        self.content = content
    }

    /// The size that the desk is drawn at: a window that changes size
    /// draws every part again, whatever its values.
    private let scale = Desk.scale

    static func == (left: Self, right: Self) -> Bool { left.key == right.key && left.scale == right.scale }
    var body: some View { content() }
}

/// What a control shows when it is selected. A keyboard moves a selection
/// that the screen keeps. The remote of a television moves the focus of the
/// system, which each control reads from itself: a move then redraws the
/// two controls it concerns, and shows where the remote really is.
struct FluxFocused<Content: View>: View {
    /// Name under which the control says that it really has the remote,
    /// for a request that waits for it.
    var id: String? = nil
    /// The selection of a keyboard; a television does not read it.
    let logical: Bool
    @ViewBuilder let content: (Bool) -> Content
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        #if os(tvOS)
        if let id {
            content(isFocused)
                .onChange(of: isFocused, initial: true) { _, now in FluxFocusLedger.shared.report(id, focused: now) }
                .onDisappear { FluxFocusLedger.shared.report(id, focused: false) }
        } else {
            content(isFocused)
        }
        #else
        content(logical)
        #endif
    }
}

/// What really has the focus of a remote, told by the controls themselves.
/// A focus that was asked for reads as granted even when the system has
/// declined it, which it does for a control that cannot take it yet: a
/// request is repeated until the control it names is found here.
@MainActor final class FluxFocusLedger {
    static let shared = FluxFocusLedger()
    private(set) var real: String?

    func report(_ id: String, focused: Bool) {
        if focused { real = id } else if real == id { real = nil }
    }
}

/// Draws above its neighbours the control that has the focus of a remote:
/// what it shows grows over them. The control tells it by itself, and the
/// list that holds it is not rebuilt.
struct FluxRaised<Content: View>: View {
    @ViewBuilder let content: (_ focused: @escaping (Bool) -> Void) -> Content
    @State private var raised = false

    var body: some View {
        content { focused in if raised != focused { raised = focused } }
            .zIndex(raised ? 1 : 0)
    }
}

/// What has the focus of a remote grows, and leans with the thumb that
/// rests on the remote, as the tiles of the system do. Only its layer
/// moves: nothing is drawn again, whatever the television. The effect of
/// the system itself draws the tile again for every picture it shows,
/// which cost more than all the rest of a move of the remote.
struct FluxFocusLean: ViewModifier {
    let focused: Bool
    var grow: CGFloat = 1.06
    /// Degrees and points when the thumb is at the edge of the remote.
    var angle: Double = 7
    var shift: CGFloat = 8
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(FluxAppearance.motionKey) private var rich = FluxAppearance.motionDefault
    #if os(tvOS)
    @State private var lean: CGSize = .zero
    /// Following the thumb is a new picture for each of its moves: an
    /// Apple TV HD and the first Apple TV 4K showed it in jerks.
    private var leans: Bool { rich && !reduceMotion && FluxAppearance.systemGlass }
    #endif

    func body(content: Content) -> some View {
        #if os(tvOS)
        content
            .rotation3DEffect(.degrees(Double(lean.width) * angle), axis: (x: 0, y: 1, z: 0), perspective: 0.45)
            .rotation3DEffect(.degrees(Double(-lean.height) * angle), axis: (x: 1, y: 0, z: 0), perspective: 0.45)
            .offset(x: lean.width * shift, y: lean.height * shift)
            .scaleEffect(focused && !reduceMotion ? grow : 1)
            // Each picture of an animation walks the whole screen: a
            // slow Apple TV shows the focus at once instead.
            .animation(reduceMotion || !rich ? nil : .easeOut(duration: 0.14), value: focused)
            .onReceive(focused && leans ? RemoteTouch.shared.leans : RemoteTouch.shared.still) { value in
                // The layer follows the thumb at once, and comes back
                // gently when the thumb lifts.
                if value == .zero { withAnimation(rich ? .easeOut(duration: 0.22) : nil) { lean = .zero } }
                else { lean = value }
            }
            .onChange(of: focused) { _, now in
                if !now, lean != .zero { withAnimation(rich ? .easeOut(duration: 0.14) : nil) { lean = .zero } }
            }
        #else
        content
        #endif
    }
}

extension View {
    func fluxFocusLean(_ focused: Bool, grow: CGFloat = 1.06, angle: Double = 7, shift: CGFloat = 8) -> some View {
        modifier(FluxFocusLean(focused: focused, grow: grow, angle: angle, shift: shift))
    }
}

/// The handles that scroll the lists of a screen, kept for requests made
/// when nothing is being rebuilt. A list observed a counter to learn that
/// it had to move: its observer sits in the part of the screen that is
/// built when the list is, and that part is not built again for a state
/// it alone reads. The request is made to the list itself.
@MainActor final class FluxScrollHandles {
    /// The catalogue of the screen.
    var pane: ScrollViewProxy?
    /// The navigation column.
    var column: ScrollViewProxy?
    /// The list of channels over the picture.
    var channels: ScrollViewProxy?
}

/// Hands the moves of the focus of the system to a screen that does not
/// own it. The view that owns a focus is rebuilt each time it moves, and
/// only that view is told: the window owns it, and tells the screen here.
@MainActor final class FluxFocusRelay {
    var moved: ((String?) -> Void)?
}

/// Tells whether the control it is drawn in really has the focus. A request
/// the system declined still reads as granted in a focus binding: the
/// control itself is the one to ask.
struct DeskFocusReport: View {
    let report: (Bool) -> Void
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        Color.clear
            .onAppear { if isFocused { report(true) } }
            .onChange(of: isFocused) { _, focused in report(focused) }
            .onDisappear { report(false) }
    }
}

#if FLUX_CATALOG_UI_TESTING
/// Counts what a screen rebuilds, for the bench: a move of the remote must
/// not rebuild the whole catalogue, and a flow checks that it does not.
/// It counts nothing in the application.
enum FluxProbe {
    nonisolated(unsafe) static var counts: [String: Int] = [:]
    @inline(__always) static func hit(_ name: String) { counts[name, default: 0] += 1 }
}
#else
enum FluxProbe {
    @inline(__always) static func hit(_ name: String) {}
}
#endif

/// System glass is reserved for navigation and transient playback controls.
enum FluxAppearance {
    /// The glass of the panels. A new key: an Apple TV HD and the first
    /// Apple TV 4K started without it, and now start with it.
    static let glassKey = "fluxiptv.appearance.glass.v3"
    /// An Apple TV shows what a Mac shows: the glass is on until the user
    /// says otherwise, on every model.
    static let richDefault = true
    /// What moves when the focus does: the title that grows, the icons of
    /// the bar that slide. Apart from the glass, so that a television that
    /// draws them badly can keep the one without the other.
    static let motionKey = "fluxiptv.appearance.motion.v1"
    static let motionDefault = true
    /// Whether this machine draws the glass of the system itself. tvOS
    /// keeps it for the second Apple TV 4K and the later ones; on an Apple
    /// TV HD and on the first Apple TV 4K the panels are drawn from the
    /// blur of the system, which those have had since their first days.
    /// What only the newer chips draw well goes with it: a whole screen
    /// put out of focus behind a panel, and what follows the thumb on the
    /// remote, picture after picture.
    static let systemGlass: Bool = {
        #if FLUX_CATALOG_UI_TESTING
        // A bench shows the panels of an older Apple TV on any simulator.
        if ProcessInfo.processInfo.environment["FLUX_UI_EFFECTS"] == "material" { return false }
        #endif
        #if os(tvOS)
        var system = utsname()
        uname(&system)
        let machine = withUnsafeBytes(of: &system.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        // A simulator names the model it stands for in its environment.
        let model = machine.hasPrefix("AppleTV") ? machine
            : ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? machine
        // "AppleTV5,3" is the Apple TV HD and "AppleTV6,2" the first
        // Apple TV 4K; the second one, "AppleTV11,1", has the chip the
        // system itself asks for its glass.
        guard model.hasPrefix("AppleTV"), let generation = Int(model.dropFirst(7).prefix { $0.isNumber }) else { return true }
        return generation >= 11
        #else
        return true
        #endif
    }()
    static let artworkKey = "fluxiptv.appearance.artwork"
    static let wallpaperKey = "fluxiptv.appearance.wallpaper"
    static let intensityKey = "fluxiptv.appearance.wallpaperIntensity"
    static let densityKey = "fluxiptv.appearance.density"
    /// Liquid Glass exists on the three platforms from version 26. On Apple
    /// TV the same setting returns to the inexpensive dark surfaces.
    static var nativeAvailable: Bool {
        #if compiler(>=6.2)
        if #available(macOS 26.0, iOS 26.0, tvOS 26.0, *) { return true }
        #endif
        return false
    }
}

private struct FluxGlassChrome: ViewModifier {
    @AppStorage(FluxAppearance.glassKey) private var richGlass = FluxAppearance.richDefault
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let radius: CGFloat

    @ViewBuilder func body(content: Content) -> some View {
        if richGlass && !reduceTransparency {
            #if compiler(>=6.2)
            if #available(macOS 26.0, iOS 26.0, tvOS 26.0, *), FluxAppearance.systemGlass {
                content.glassEffect(.regular, in: .rect(cornerRadius: radius))
            } else { content.fluxMaterial(radius: radius) }
            #else
            content.fluxMaterial(radius: radius)
            #endif
        } else { content.fluxOpaque(radius: radius) }
    }
}

/// Clear Liquid Glass is designed for controls above rich media. A small,
/// local dimming layer keeps the white controls legible even over a bright shot.
/// The system remains responsible for the refraction and live material.
private struct FluxMediaGlass: ViewModifier {
    @AppStorage(FluxAppearance.glassKey) private var richGlass = FluxAppearance.richDefault
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let radius: CGFloat

    @ViewBuilder func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        if richGlass && !reduceTransparency {
            #if compiler(>=6.2)
            if #available(macOS 26.0, iOS 26.0, tvOS 26.0, *), FluxAppearance.systemGlass {
                content
                    .glassEffect(.clear, in: shape)
                    .background(.black.opacity(0.30), in: shape)
            } else { content.fluxLegacyMediaMaterial(shape: shape, radius: radius) }
            #else
            content.fluxLegacyMediaMaterial(shape: shape, radius: radius)
            #endif
        } else { content.fluxOpaque(radius: radius) }
    }
}

/// Independent navigation capsules reveal the room between controls. Selected
/// destinations use a tinted native glass; other destinations stay clear.
private struct FluxNavigationGlass: ViewModifier {
    @AppStorage(FluxAppearance.glassKey) private var richGlass = FluxAppearance.richDefault
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let selected: Bool
    let tint: Color
    let radius: CGFloat

    @ViewBuilder func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        if richGlass && !reduceTransparency {
            #if compiler(>=6.2)
            if #available(macOS 26.0, iOS 26.0, tvOS 26.0, *), FluxAppearance.systemGlass {
                #if os(tvOS)
                // The focus engine, not a touch, animates a control on Apple TV.
                if selected {
                    content.glassEffect(.regular.tint(tint.opacity(0.38)), in: shape)
                } else {
                    content.glassEffect(.clear, in: shape)
                        .background(.black.opacity(0.16), in: shape)
                }
                #else
                if selected {
                    content.glassEffect(.regular.tint(tint.opacity(0.38)).interactive(), in: shape)
                } else {
                    content.glassEffect(.clear.interactive(), in: shape)
                        .background(.black.opacity(0.16), in: shape)
                }
                #endif
            } else { content.fluxMaterial(radius: radius, tint: selected ? tint : .clear) }
            #else
            content.fluxMaterial(radius: radius, tint: selected ? tint : .clear)
            #endif
        } else {
            #if os(tvOS)
            content.fluxTelevisionGlass(radius: radius, tint: selected ? tint : .clear, translucent: false)
            #else
            content.fluxFrosted(radius: radius)
            #endif
        }
    }
}

/// Render nearby glass shapes in one system container. Older systems preserve
/// the same layout and use real system material through the modifiers above.
struct FluxGlassGroup<Content: View>: View {
    private let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    @ViewBuilder var body: some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, iOS 26.0, tvOS 26.0, *) {
            GlassEffectContainer(spacing: 12) { content }
        } else { content }
        #else
        content
        #endif
    }
}

extension View {
    /// No backdrop sampling or blur passes on Apple TV. A static dark tint and
    /// a thin highlight retain depth while focus/press/transition animations
    /// remain independent of the surface treatment.
    func fluxTelevisionGlass(radius: CGFloat, tint: Color = .clear, translucent: Bool = true) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return background(tint.opacity(0.18), in: shape)
            .background(Color(red: 0.07, green: 0.085, blue: 0.12).opacity(translucent ? 0.9 : 1), in: shape)
            .overlay(shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.32), .white.opacity(0.08)],
                                                        startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                .allowsHitTesting(false))
    }
    /// Surface used when Liquid Glass is switched off or unavailable: the
    /// inexpensive dark plate on Apple TV, the opaque frost elsewhere.
    @ViewBuilder func fluxOpaque(radius: CGFloat) -> some View {
        #if os(tvOS)
        fluxTelevisionGlass(radius: radius, translucent: false)
        #else
        fluxFrosted(radius: radius)
        #endif
    }
    @ViewBuilder func fluxLegacyMediaMaterial(shape: RoundedRectangle, radius: CGFloat) -> some View {
        #if os(tvOS)
        fluxTelevisionGlass(radius: radius)
        #else
        background(.ultraThinMaterial, in: shape)
            .background(.black.opacity(0.22), in: shape)
            .overlay(shape.strokeBorder(.white.opacity(0.18), lineWidth: 0.7).allowsHitTesting(false))
        #endif
    }
    func fluxNavigationGlass(selected: Bool = false, tint: Color = .cyan, radius: CGFloat = 22) -> some View {
        modifier(FluxNavigationGlass(selected: selected, tint: tint, radius: radius))
    }

    func fluxGlass(radius: CGFloat = 20) -> some View {
        modifier(FluxGlassChrome(radius: radius))
    }

    func fluxMediaGlass(radius: CGFloat = 26) -> some View {
        modifier(FluxMediaGlass(radius: radius))
    }

    /// Large moving case panel: static translucent fill instead of sampling the
    /// full live catalogue every animation frame. Native glass stays on navigation.
    func fluxCasePanel(radius: CGFloat = 30) -> some View {
        let shape=RoundedRectangle(cornerRadius:radius,style:.continuous)
        return background(Color(red:0.09,green:0.10,blue:0.14).opacity(0.88),in:shape)
            .overlay(shape.strokeBorder(.white.opacity(0.22),lineWidth:1).allowsHitTesting(false))
    }

    /// Where the system gives no glass of its own — an older OS, or the
    /// chip of an Apple TV HD and of the first Apple TV 4K —: its real
    /// blur of what is behind, under a light tint and a bright rim. The
    /// panels of a television then look like those of a Mac, with the blur
    /// those televisions have always drawn.
    func fluxMaterial(radius: CGFloat = 20, tint: Color = .clear) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        #if os(tvOS)
        // The blur of the system is darker than its glass: it is let
        // through in part, so that the room behind keeps its colours as
        // it does behind the glass of a Mac.
        return background(tint.opacity(0.24), in: shape)
            .background(Color.white.opacity(0.035), in: shape)
            .background { shape.fill(.ultraThinMaterial).opacity(0.74) }
            .overlay(shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.46), .white.opacity(0.10)],
                                                        startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                .allowsHitTesting(false))
        #else
        return background(tint.opacity(0.18), in: shape)
            .background(.regularMaterial, in: shape)
            .overlay(shape.strokeBorder(.white.opacity(0.17), lineWidth: 1).allowsHitTesting(false))
        #endif
    }

    /// Opaque treatment when transparency is disabled or for diagnostic content.
    func fluxFrosted(radius: CGFloat = 20) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return background(Color(red: 0.095, green: 0.112, blue: 0.145).opacity(0.97), in: shape)
            .overlay(shape.strokeBorder(.white.opacity(0.14), lineWidth: 1).allowsHitTesting(false))
    }
}

/// Sizes of the desk. Text styles do not keep their proportions between a
/// Mac and a television: a title is 1.3 times the body on one and twice on
/// the other. The Mac and the phone keep the system styles; the television
/// uses sizes that are read from a sofa and keep the layout of the Mac.
#if os(macOS)
/// How much of the screen of a television the window of a Mac is. The
/// desk is drawn for the 1920 × 1080 points of a television; a window
/// shows the same desk, with the same proportions, at its own size.
/// Observed: what was drawn from it is drawn again when the window changes.
@Observable final class DeskScale {
    static let shared = DeskScale()
    /// A window of 1440 × 900 points, until the window says its size.
    var value: CGFloat = 0.75

    static func fitting(_ size: CGSize) -> CGFloat {
        guard size.width > 0, size.height > 0 else { return 0.75 }
        // To the hundredth: a window being resized does not draw the
        // whole desk again for every point of its way.
        return max(0.5, min(1.8, (min(size.width / 1920, size.height / 1080) * 100).rounded() / 100))
    }
}
#endif

enum Desk {
    /// Share of the screen of a television that the desk is drawn at: one
    /// on a television, the size of the window on a Mac.
    static var scale: CGFloat {
        #if os(macOS)
        DeskScale.shared.value
        #else
        1
        #endif
    }
    /// Factor of the lengths: paddings, frames, radii.
    static var unit: CGFloat {
        #if os(iOS)
        1
        #else
        1.35 * scale
        #endif
    }
    static func pt(_ value: CGFloat) -> CGFloat { value * unit }
    /// A length stated in the points of a television, where it is not
    /// one of the lengths of the desk.
    static func tv(_ value: CGFloat) -> CGFloat { value * scale }
    /// The margins that a television keeps around its picture. The system
    /// gives them on a television; a Mac keeps the same, so that both
    /// show the same desk.
    static var screenMargins: EdgeInsets {
        EdgeInsets(top: tv(60), leading: tv(80), bottom: tv(60), trailing: tv(80))
    }

    static func font(_ style: Font.TextStyle, _ weight: Font.Weight? = nil) -> Font {
        #if !os(iOS)
        let size: CGFloat
        switch style {
        case .largeTitle: size = 42
        case .title: size = 36
        case .title2: size = 30
        case .title3: size = 26
        case .headline, .body: size = 23
        case .callout: size = 22
        case .subheadline: size = 21
        case .footnote, .caption: size = 19
        case .caption2: size = 18
        @unknown default: size = 23
        }
        return .system(size: size * scale, weight: weight ?? (style == .headline ? .semibold : .regular))
        #else
        let font = Font.system(style)
        return weight.map { font.weight($0) } ?? font
        #endif
    }

    /// A text size stated for a phone, as a television needs it.
    static func size(_ value: CGFloat) -> CGFloat {
        #if os(iOS)
        value
        #else
        max(17, value * 1.6) * scale
        #endif
    }

    /// A size stated for a phone.
    static func system(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: Desk.size(size), weight: weight)
    }
}

extension View {
    /// On a television a column answers as a whole: the arrow that points to
    /// it enters it, whatever stands at the height the remote comes from.
    @ViewBuilder func deskFocusSection() -> some View {
        #if os(tvOS)
        focusSection()
        #else
        self
        #endif
    }
}

/// Places its views in rows and starts a new row when the width is used:
/// chips of a fiche, choices of a setting.
struct DeskFlow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let limit = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > limit { x = 0; y += row + spacing; row = 0 }
            x += size.width + spacing
            row = max(row, size.height); widest = max(widest, x - spacing)
        }
        return CGSize(width: limit.isFinite ? limit : widest, height: y + row)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX { x = bounds.minX; y += row + spacing; row = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            row = max(row, size.height)
        }
    }
}

/// Static scene with broad color fields so the system glass has visible depth.
struct FluxBackdrop: View {
    var theme: VideoClubTheme = .neo90
    var body: some View {
        ZStack {
            Color(red: theme.palette.wall.x*0.35, green: theme.palette.wall.y*0.35, blue: theme.palette.wall.z*0.35)
            RadialGradient(colors: [Color(red: theme.palette.accent.x, green: theme.palette.accent.y, blue: theme.palette.accent.z).opacity(0.30), .clear], center: .topLeading, startRadius: 0, endRadius: 720)
            RadialGradient(colors: [Color(red: theme.palette.second.x, green: theme.palette.second.y, blue: theme.palette.second.z).opacity(0.35), .clear], center: .topTrailing, startRadius: 0, endRadius: 620)
        }.ignoresSafeArea().allowsHitTesting(false)
    }
}

// Only desktop and mobile have keyboard shortcuts; Apple TV uses focus and remote commands.
extension View {
    @ViewBuilder func fluxShortcut(cancel: Bool = false) -> some View {
        #if os(tvOS)
        self
        #else
        self.keyboardShortcut(cancel ? .cancelAction : .defaultAction)
        #endif
    }
    @ViewBuilder func fluxFieldStyle() -> some View {
        #if os(tvOS)
        self
        #else
        self.textFieldStyle(.roundedBorder)
        #endif
    }
    /// A form takes the whole television screen, where a sheet would cut it
    /// and make it scroll; elsewhere it stays a sheet.
    @ViewBuilder func fluxFormCover<Content: View>(isPresented: Binding<Bool>,
                                                   @ViewBuilder content: @escaping () -> Content) -> some View {
        #if os(tvOS)
        fullScreenCover(isPresented: isPresented, content: content)
        #else
        sheet(isPresented: isPresented, content: content)
        #endif
    }
    @ViewBuilder func fluxFormCover<Item: Identifiable, Content: View>(item: Binding<Item?>,
                                                                       @ViewBuilder content: @escaping (Item) -> Content) -> some View {
        #if os(tvOS)
        fullScreenCover(item: item, content: content)
        #else
        sheet(item: item, content: content)
        #endif
    }
    @ViewBuilder func fluxSheetSize(width: CGFloat, height: CGFloat? = nil) -> some View {
        #if os(macOS)
        self.frame(width: width, height: height)
        #else
        self.frame(maxWidth: width)
        #endif
    }
}
