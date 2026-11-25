import SwiftUI

/// tvOS PlainButtonStyle can add a focus platter. Controls that draw their own
/// focus treatment use this explicit label-only style, including the invisible
/// Select target above a playing video.
struct FluxBareButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.82 : 1)
    }
}

/// System glass is reserved for navigation and transient playback controls.
enum FluxAppearance {
    static let glassKey = "fluxiptv.appearance.glass.v2"
    static let artworkKey = "fluxiptv.appearance.artwork"
    static let wallpaperKey = "fluxiptv.appearance.wallpaper"
    static let intensityKey = "fluxiptv.appearance.wallpaperIntensity"
    static let densityKey = "fluxiptv.appearance.density"
    static var nativeAvailable: Bool {
        #if os(tvOS)
        // Television prioritises a predictable, inexpensive dark surface.
        return false
        #else
        #if compiler(>=6.2)
        if #available(macOS 26.0, iOS 26.0, tvOS 26.0, *) { return true }
        #endif
        return false
        #endif
    }
}

private struct FluxGlassChrome: ViewModifier {
    @AppStorage(FluxAppearance.glassKey) private var richGlass = true
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let radius: CGFloat

    @ViewBuilder func body(content: Content) -> some View {
        #if os(tvOS)
        content.fluxTelevisionGlass(radius: radius, translucent: richGlass && !reduceTransparency)
        #else
        if richGlass && !reduceTransparency {
            #if compiler(>=6.2)
            if #available(macOS 26.0, iOS 26.0, tvOS 26.0, *) {
                content.glassEffect(.regular, in: .rect(cornerRadius: radius))
            } else { content.fluxMaterial(radius: radius) }
            #else
            content.fluxMaterial(radius: radius)
            #endif
        } else { content.fluxFrosted(radius: radius) }
        #endif
    }
}

/// Clear Liquid Glass is designed for controls above rich media. A small,
/// local dimming layer keeps the white controls legible even over a bright shot.
/// The system remains responsible for the refraction and live material.
private struct FluxMediaGlass: ViewModifier {
    @AppStorage(FluxAppearance.glassKey) private var richGlass = true
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let radius: CGFloat

    @ViewBuilder func body(content: Content) -> some View {
        #if os(tvOS)
        content.fluxTelevisionGlass(radius: radius, translucent: richGlass && !reduceTransparency)
        #else
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        if richGlass && !reduceTransparency {
            #if compiler(>=6.2)
            if #available(macOS 26.0, iOS 26.0, tvOS 26.0, *) {
                content
                    .glassEffect(.clear, in: shape)
                    .background(.black.opacity(0.30), in: shape)
            } else {
                content.background(.ultraThinMaterial, in: shape)
                    .background(.black.opacity(0.22), in: shape)
                    .overlay(shape.strokeBorder(.white.opacity(0.18), lineWidth: 0.7).allowsHitTesting(false))
            }
            #else
            content.background(.ultraThinMaterial, in: shape)
                .background(.black.opacity(0.22), in: shape)
                .overlay(shape.strokeBorder(.white.opacity(0.18), lineWidth: 0.7).allowsHitTesting(false))
            #endif
        } else { content.fluxFrosted(radius: radius) }
        #endif
    }
}

/// Independent navigation capsules reveal the room between controls. Selected
/// destinations use a tinted native glass; other destinations stay clear.
private struct FluxNavigationGlass: ViewModifier {
    @AppStorage(FluxAppearance.glassKey) private var richGlass = true
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let selected: Bool
    let tint: Color
    let radius: CGFloat

    @ViewBuilder func body(content: Content) -> some View {
        #if os(tvOS)
        content.fluxTelevisionGlass(radius: radius, tint: selected ? tint : .clear,
                                   translucent: richGlass && !reduceTransparency)
        #else
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        if richGlass && !reduceTransparency {
            #if compiler(>=6.2)
            if #available(macOS 26.0, iOS 26.0, tvOS 26.0, *) {
                if selected {
                    content.glassEffect(.regular.tint(tint.opacity(0.38)).interactive(), in: shape)
                } else {
                    content.glassEffect(.clear.interactive(), in: shape)
                        .background(.black.opacity(0.16), in: shape)
                }
            } else { content.fluxMaterial(radius: radius) }
            #else
            content.fluxMaterial(radius: radius)
            #endif
        } else { content.fluxFrosted(radius: radius) }
        #endif
    }
}

/// Render nearby glass shapes in one system container. Older systems preserve
/// the same layout and use real system material through the modifiers above.
struct FluxGlassGroup<Content: View>: View {
    private let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    @ViewBuilder var body: some View {
        #if os(tvOS)
        content
        #else
        #if compiler(>=6.2)
        if #available(macOS 26.0, iOS 26.0, tvOS 26.0, *) {
            GlassEffectContainer(spacing: 12) { content }
        } else { content }
        #else
        content
        #endif
        #endif
    }
}

extension View {
    /// No backdrop sampling or blur passes on Apple TV. A static dark tint and
    /// a thin highlight retain depth while focus/press/transition animations
    /// remain independent of the surface treatment.
    func fluxTelevisionGlass(radius: CGFloat, tint: Color = .clear, translucent: Bool = true) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return background(Color(red: 0.07, green: 0.085, blue: 0.12).opacity(translucent ? 0.9 : 1), in: shape)
            .background(tint.opacity(0.18), in: shape)
            .overlay(shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.32), .white.opacity(0.08)],
                                                        startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                .allowsHitTesting(false))
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
    @ViewBuilder func fluxSheetSize(width: CGFloat, height: CGFloat? = nil) -> some View {
        #if os(macOS)
        self.frame(width: width, height: height)
        #else
        self.frame(maxWidth: width)
        #endif
    }
}
