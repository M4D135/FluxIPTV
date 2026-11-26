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

        var body: some View {
            configuration.label
                .opacity(configuration.isPressed ? 0.82 : 1)
                #if os(tvOS)
                .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(.white.opacity(isFocused ? 0.92 : 0), lineWidth: 3).allowsHitTesting(false))
                .scaleEffect(isFocused && !reduceMotion ? 1.02 : 1)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isFocused)
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

    static func == (left: Self, right: Self) -> Bool { left.key == right.key }
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
    @AppStorage(FluxAppearance.glassKey) private var rich = FluxAppearance.richDefault
    #if os(tvOS)
    @State private var lean: CGSize = .zero
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
            .onReceive(focused && !reduceMotion ? RemoteTouch.shared.leans : RemoteTouch.shared.still) { value in
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
    static let glassKey = "fluxiptv.appearance.glass.v2"
    /// Whether the full effects are on until the user says otherwise: the
    /// glass of the system, what is put out of focus behind a panel, the
    /// animations of the focus. An Apple TV HD and the first Apple TV 4K
    /// draw them too slowly for a remote that is held down: they start
    /// with the dark surfaces and the immediate focus, which cost them
    /// next to nothing. The setting stays theirs to turn on.
    static let richDefault: Bool = {
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
            if #available(macOS 26.0, iOS 26.0, tvOS 26.0, *) {
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
            if #available(macOS 26.0, iOS 26.0, tvOS 26.0, *) {
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
            if #available(macOS 26.0, iOS 26.0, tvOS 26.0, *) {
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
            } else { content.fluxMaterial(radius: radius) }
            #else
            content.fluxMaterial(radius: radius)
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

    /// Older OS: real system translucency with a restrained rim, not faux blur.
    func fluxMaterial(radius: CGFloat = 20) -> some View {
        #if os(tvOS)
        return fluxTelevisionGlass(radius: radius)
        #else
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return background(.regularMaterial, in: shape)
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
enum Desk {
    /// Factor of the lengths: paddings, frames, radii.
    static var unit: CGFloat {
        #if os(tvOS)
        1.35
        #else
        1
        #endif
    }
    static func pt(_ value: CGFloat) -> CGFloat { value * unit }

    static func font(_ style: Font.TextStyle, _ weight: Font.Weight? = nil) -> Font {
        #if os(tvOS)
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
        return .system(size: size, weight: weight ?? (style == .headline ? .semibold : .regular))
        #else
        let font = Font.system(style)
        return weight.map { font.weight($0) } ?? font
        #endif
    }

    /// A text size stated for the Mac layout, as a television needs it.
    static func size(_ value: CGFloat) -> CGFloat {
        #if os(tvOS)
        max(17, value * 1.6)
        #else
        value
        #endif
    }

    /// A size stated for the Mac layout.
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
