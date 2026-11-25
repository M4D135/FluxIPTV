import SwiftUI

extension FluxDockItem {
    var symbol: String {
        switch self {
        case .live: "tv.fill"
        case .movie: "film.fill"
        case .series: "square.stack.3d.up.fill"
        case .search: "magnifyingglass"
        case .favorites: "star.fill"
        case .settings: "gearshape.fill"
        }
    }
    var tint: Color {
        switch self {
        case .live: .cyan
        case .movie: .orange
        case .series: .purple
        case .search: Color(red: 0.30, green: 0.86, blue: 0.72)
        case .favorites: .yellow
        case .settings: Color(red: 0.62, green: 0.68, blue: 0.80)
        }
    }
}

#if !os(tvOS)
/// Sizes shared by the bar and by the screen that leaves room for it. The
/// compact form holds the same destinations in the width of the navigation
/// column, without labels. The hero form is the bar of the home screen, in
/// the middle of the window and scaled to its width.
struct FluxDockMetrics: Equatable {
    enum Form: Equatable { case compact, regular, hero(CGFloat) }
    let form: Form
    init(_ position: FluxDockPosition) { form = position.isCompact ? .compact : .regular }
    init(hero scale: CGFloat) { form = .hero(max(0.6, min(1.2, scale))) }

    var compact: Bool { form == .compact }
    var hero: Bool { unit != nil }
    private var unit: CGFloat? {
        if case .hero(let scale) = form { return scale }
        return nil
    }

    var cell: CGSize {
        if let unit { return CGSize(width: 138 * unit, height: 150 * unit) }
        return compact ? CGSize(width: 38, height: 38) : CGSize(width: 74, height: 72)
    }
    var spacing: CGFloat { unit.map { 10 * $0 } ?? (compact ? 2 : 4) }
    var platePadding: CGFloat { unit.map { 20 * $0 } ?? (compact ? 8 : 9) }
    var tile: CGFloat { unit.map { 96 * $0 } ?? (compact ? 34 : 50) }
    var glyph: CGFloat { unit.map { 44 * $0 } ?? (compact ? 18 : 25) }
    var tileRadius: CGFloat { unit.map { 27 * $0 } ?? (compact ? 11 : 15) }
    var label: CGFloat { unit.map { 15.5 * $0 } ?? 11 }
    var labelSpacing: CGFloat { unit.map { 11 * $0 } ?? 5 }
    var radius: CGFloat { unit.map { 46 * $0 } ?? (compact ? 20 : 28) }
    var maximumScale: Double { hero ? 1.2 : compact ? 1.34 : 1.42 }
    /// Transparent room around the plate for magnified icons. It tracks the
    /// pointer but never receives a click.
    var growth: CGFloat { unit.map { 44 * $0 } ?? (compact ? 18 : 40) }
    static let edgeMargin: CGFloat = 10

    /// Width or height that the screen must leave free on the bar's edge.
    static func thickness(_ position: FluxDockPosition) -> CGFloat {
        let metrics = FluxDockMetrics(position)
        return (position.isVertical ? metrics.cell.width : metrics.cell.height) + metrics.platePadding * 2 + edgeMargin + 6
    }
    /// Length of the plate along its axis, for a given number of destinations.
    func length(count: Int, vertical: Bool) -> CGFloat {
        let extent = vertical ? cell.height : cell.width
        return CGFloat(count) * extent + CGFloat(max(0, count - 1)) * spacing + platePadding * 2
    }
}

/// Destination bar in the manner of the system Dock: a plate on one edge of
/// the window, icons that grow under the pointer, an order chosen by dragging.
struct FluxDock: View {
    let selection: Set<FluxDockItem>
    let focusedID: String?
    let showsFocus: Bool
    let accent: Color
    let second: Color
    /// Scale of the home screen's bar; nil for the bar on its edge.
    var hero: CGFloat?
    /// Destination under the pointer, for a screen that describes it.
    var hover: ((FluxDockItem?) -> Void)?
    /// Frame of the bar while the zones of the screen are shown: nil outside
    /// that overview, true when the bar is the zone being chosen.
    var zoneRing: Bool?
    let systemFocus: FocusState<String?>.Binding
    let activate: (FluxDockItem) -> Void
    let openSettings: () -> Void

    @AppStorage(FluxDockPosition.storageKey) private var position: FluxDockPosition = .defaultValue
    @AppStorage(FluxDockTheme.storageKey) private var theme: FluxDockTheme = .defaultValue
    @AppStorage(FluxDockItem.orderKey) private var storedOrder = ""
    @AppStorage(FluxDockItem.magnifyKey) private var magnifies = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var pointer = 0.0
    @State private var hovering = false
    @State private var hovered: FluxDockItem?
    @State private var dragged: FluxDockItem?
    @State private var dragStartIndex = 0
    @State private var dragTranslation = 0.0
    @State private var suppressActivation = false

    private var order: [FluxDockItem] { FluxDockItem.order(from: storedOrder) }
    /// The home screen lays its bar out as a bar at the bottom, whatever edge
    /// the user chose for the other screens.
    private var placement: FluxDockPosition { hero == nil ? position : .bottom }
    private var vertical: Bool { placement.isVertical }
    private var metrics: FluxDockMetrics { hero.map { FluxDockMetrics(hero: $0) } ?? FluxDockMetrics(position) }
    private var magnifier: FluxDockMagnifier {
        let extent = Double(vertical ? metrics.cell.height : metrics.cell.width)
        return FluxDockMagnifier(count: order.count, cell: extent, spacing: Double(metrics.spacing),
                                 maximumScale: metrics.maximumScale, radius: (extent + Double(metrics.spacing)) * 2.2)
    }
    /// Icons grow away from the edge that holds the bar.
    private var anchor: UnitPoint {
        switch placement {
        case .bottom, .corner: .bottom
        case .top: .top
        case .leading: .leading
        case .trailing: .trailing
        }
    }
    private var growthInsets: EdgeInsets {
        let room = metrics.growth
        switch placement {
        // Under the navigation column the plate keeps the column's own edges.
        case .corner: return EdgeInsets(top: room, leading: 0, bottom: 0, trailing: room)
        case .bottom: return EdgeInsets(top: room, leading: room, bottom: 0, trailing: room)
        case .top: return EdgeInsets(top: 0, leading: room, bottom: room, trailing: room)
        case .leading: return EdgeInsets(top: room, leading: 0, bottom: room, trailing: room)
        case .trailing: return EdgeInsets(top: room, leading: room, bottom: room, trailing: 0)
        }
    }
    private var magnification: Double {
        hovering && magnifies && dragged == nil && !reduceMotion ? 1 : 0
    }

    var body: some View {
        let items = order
        FluxDockStrip(intensity: magnification, pointer: pointer, magnifier: magnifier, metrics: metrics, vertical: vertical,
                      anchor: anchor, items: items, dragged: dragged, dragTranslation: dragTranslation,
                      reduceMotion: reduceMotion,
                      plate: {
                          FluxDockPlate(theme: theme, accent: accent, second: second, radius: metrics.radius)
                              .overlay {
                                  if let zoneRing {
                                      RoundedRectangle(cornerRadius: metrics.radius, style: .continuous)
                                          .strokeBorder(zoneRing ? accent : Color.white.opacity(0.28), lineWidth: zoneRing ? 3 : 1)
                                          .shadow(color: zoneRing ? accent.opacity(0.7) : .clear, radius: 10)
                                          .allowsHitTesting(false)
                                  }
                              }
                      },
                      cell: { item in cell(item, items: items) })
            .animation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.8), value: magnification)
            .coordinateSpace(name: "flux-dock")
            // The menu belongs to the plate; the transparent room around it
            // must leave a secondary click to the screen underneath.
            .contextMenu { menu }
            .padding(growthInsets)
            .onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case .active(let location): track(location)
                case .ended: hovering = false; report(nil)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Barre des destinations")
            #if FLUX_CATALOG_UI_TESTING
            .onAppear {
                // A capture has no pointer: place one on the requested icon.
                if let index = UserDefaults.standard.object(forKey: "fluxiptv.fixture.dockPointer") as? Int,
                   items.indices.contains(index) {
                    pointer = magnifier.center(index); hovering = true; report(items[index])
                }
            }
            #endif
    }

    /// The pointer starts the effect on the plate and keeps it while it stays
    /// over the enlarged icons, which reach past the plate.
    private func track(_ location: CGPoint) {
        let insets = growthInsets
        let pad = Double(metrics.platePadding)
        let along = Double(vertical ? location.y - insets.top : location.x - insets.leading) - pad
        let cross = Double(vertical ? location.x - insets.leading : location.y - insets.top)
        let thickness = Double(vertical ? metrics.cell.width : metrics.cell.height) + pad * 2
        let onPlate = cross >= 0 && cross <= thickness && along >= -pad && along <= magnifier.length + pad
        guard hovering || onPlate else { return }
        pointer = along
        if !hovering { hovering = true }
        let items = order
        report(magnifier.index(at: along).flatMap { items.indices.contains($0) ? items[$0] : nil })
    }

    private func report(_ item: FluxDockItem?) {
        guard item != hovered else { return }
        hovered = item
        hover?(item)
    }

    private func cell(_ item: FluxDockItem, items: [FluxDockItem]) -> some View {
        let id = item.focusID
        let focused = showsFocus && focusedID == id
        return Button {
            guard !suppressActivation else { return }
            activate(item)
        } label: {
            FluxDockCell(item: item, selected: selection.contains(item), focused: focused,
                         theme: theme, position: placement, metrics: metrics)
        }
        .buttonStyle(FluxBareButtonStyle())
        .focusable().focused(systemFocus, equals: id).focusEffectDisabled()
        .id(id)
        .scaleEffect(focused && !reduceMotion ? (metrics.hero ? 1.06 : 1.12) : 1, anchor: anchor)
        .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.85), value: focused)
        .help(item.title)
        .accessibilityLabel(item.title)
        .accessibilityValue(selection.contains(item) ? "Sélectionné" : "")
        .accessibilityIdentifier("navigation-\(id)")
        .simultaneousGesture(reorderGesture(item, items: items))
    }

    private func reorderGesture(_ item: FluxDockItem, items: [FluxDockItem]) -> some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .named("flux-dock"))
            .onChanged { value in
                let pitch = magnifier.pitch
                guard let current = items.firstIndex(of: item) else { return }
                if dragged != item {
                    dragged = item; dragStartIndex = current; suppressActivation = true; hovering = false
                }
                let translation = Double(vertical ? value.translation.height : value.translation.width)
                let wanted = (Double(dragStartIndex) * pitch + translation) / pitch
                let target = Int(max(0, min(Double(items.count - 1), wanted.rounded())))
                if target != current { storedOrder = FluxDockItem.stored(FluxDockItem.moving(item, to: target, in: items)) }
                // The icon stays under the pointer while its slot changes.
                dragTranslation = translation - Double(target - dragStartIndex) * pitch
            }
            .onEnded { _ in
                withAnimation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.82)) {
                    dragged = nil; dragTranslation = 0
                }
                // The button under the pointer must not fire for this release.
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    suppressActivation = false
                }
            }
    }

    @ViewBuilder private var menu: some View {
        Picker("Position", selection: $position) {
            ForEach(FluxDockPosition.allCases) { choice in Text(choice.title).tag(choice) }
        }
        Picker("Thème", selection: $theme) {
            ForEach(FluxDockTheme.allCases) { choice in Text(choice.title).tag(choice) }
        }
        Toggle("Agrandir au survol", isOn: $magnifies)
        Divider()
        Button("Réglages du dock…", action: openSettings)
    }
}

/// Lays the icons out by hand so that the pointer drives their size on every
/// frame, while slot changes and the entry of the effect keep their animation.
private struct FluxDockStrip<Plate: View, Cell: View>: View, Animatable {
    var intensity: Double
    let pointer: Double
    let magnifier: FluxDockMagnifier
    let metrics: FluxDockMetrics
    let vertical: Bool
    let anchor: UnitPoint
    let items: [FluxDockItem]
    let dragged: FluxDockItem?
    let dragTranslation: Double
    let reduceMotion: Bool
    @ViewBuilder let plate: () -> Plate
    @ViewBuilder let cell: (FluxDockItem) -> Cell

    var animatableData: Double {
        get { intensity }
        set { intensity = newValue }
    }

    var body: some View {
        let layout = magnifier.layout(pointer: pointer, intensity: intensity)
        let size = metrics.cell, pad = metrics.platePadding
        let length = CGFloat(magnifier.length)
        let base = CGSize(width: (vertical ? size.width : length) + pad * 2,
                          height: (vertical ? length : size.height) + pad * 2)
        let stretch = CGFloat(layout.trailing - layout.leading)
        ZStack(alignment: .topLeading) {
            plate()
                .frame(width: base.width + (vertical ? 0 : stretch), height: base.height + (vertical ? stretch : 0))
                .offset(x: vertical ? 0 : CGFloat(layout.leading), y: vertical ? CGFloat(layout.leading) : 0)
            ForEach(Array(items.enumerated()), id: \.element) { index, item in
                let lifted = item == dragged
                let shift = CGFloat(Double(index) * magnifier.pitch + (lifted ? dragTranslation : layout.offsets[index]))
                cell(item)
                    .frame(width: size.width, height: size.height)
                    .scaleEffect(lifted ? 1.1 : layout.scales[index], anchor: anchor)
                    .shadow(color: .black.opacity(lifted ? 0.45 : 0), radius: 10, y: 6)
                    .offset(x: pad + (vertical ? 0 : shift), y: pad + (vertical ? shift : 0))
                    .zIndex(lifted ? 10 : layout.scales[index])
                    .animation(lifted || reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.82), value: index)
            }
        }
        .frame(width: base.width, height: base.height, alignment: .topLeading)
    }
}

private struct FluxDockPlate: View {
    let theme: FluxDockTheme
    let accent: Color
    let second: Color
    var radius: CGFloat = 28

    @ViewBuilder var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        switch theme {
        case .glass, .vivid:
            Color.clear.fluxGlass(radius: radius)
                .shadow(color: .black.opacity(0.30), radius: 18, x: 0, y: 10)
        case .smoked:
            Color.clear
                .background(Color(red: 0.035, green: 0.04, blue: 0.055).opacity(0.80), in: shape)
                .overlay(shape.strokeBorder(.white.opacity(0.14), lineWidth: 1).allowsHitTesting(false))
                .shadow(color: .black.opacity(0.40), radius: 18, x: 0, y: 10)
        case .neon:
            Color.clear
                .background(Color(red: 0.02, green: 0.025, blue: 0.06).opacity(0.88), in: shape)
                .overlay(shape.strokeBorder(LinearGradient(colors: [accent, second], startPoint: .topLeading, endPoint: .bottomTrailing),
                                            lineWidth: 1.6).allowsHitTesting(false))
                .shadow(color: accent.opacity(0.55), radius: 14)
        case .floating:
            Color.clear
        }
    }
}

struct FluxDockCell: View {
    let item: FluxDockItem
    let selected: Bool
    let focused: Bool
    let theme: FluxDockTheme
    let position: FluxDockPosition
    var metrics = FluxDockMetrics(.bottom)

    private var tint: Color { item.tint }
    private var tileShape: RoundedRectangle { RoundedRectangle(cornerRadius: metrics.tileRadius, style: .continuous) }

    var body: some View {
        VStack(spacing: metrics.labelSpacing) {
            tile
            if !metrics.compact {
                Text(item.title)
                    .font(.system(size: metrics.label, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                    .foregroundStyle(selected && theme != .vivid ? tint : .white.opacity(0.88))
                    .shadow(color: .black.opacity(theme == .floating ? 0.8 : 0.35), radius: 3, y: 1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: indicatorAlignment) {
            if selected {
                Capsule().fill(theme == .vivid ? Color.white : tint)
                    .frame(width: position.isVertical ? 3.5 : metrics.compact ? 12 : 16, height: position.isVertical ? 16 : metrics.compact ? 3 : 3.5)
                    .offset(indicatorOffset)
                    .shadow(color: tint.opacity(theme == .neon ? 0.9 : 0), radius: 5)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var indicatorAlignment: Alignment {
        switch position {
        case .bottom, .corner: .bottom
        case .top: .top
        case .leading: .leading
        case .trailing: .trailing
        }
    }
    private var indicatorOffset: CGSize {
        switch position {
        case .corner: CGSize(width: 0, height: 5.5)
        case .bottom: CGSize(width: 0, height: 6.5)
        case .top: CGSize(width: 0, height: -6.5)
        case .leading: CGSize(width: -6.5, height: 0)
        case .trailing: CGSize(width: 6.5, height: 0)
        }
    }

    @ViewBuilder private var tile: some View {
        let glyph = Image(systemName: item.symbol)
            .font(.system(size: metrics.glyph, weight: .medium)).symbolRenderingMode(.hierarchical)
            .frame(width: metrics.tile, height: metrics.tile)
        switch theme {
        case .vivid:
            glyph.foregroundStyle(.white)
                .background(LinearGradient(colors: [tint.opacity(0.98), tint.opacity(0.62)], startPoint: .top, endPoint: .bottom), in: tileShape)
                .background(Color.black.opacity(0.55), in: tileShape)
                .overlay(tileShape.strokeBorder(LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.05)],
                                                               startPoint: .top, endPoint: .bottom), lineWidth: 1).allowsHitTesting(false))
                .overlay(tileShape.strokeBorder(.white.opacity(focused ? 0.95 : 0), lineWidth: 2).allowsHitTesting(false))
                .saturation(selected ? 1 : 0.82).brightness(selected ? 0.04 : -0.05)
                .shadow(color: .black.opacity(0.35), radius: 5, y: 3)
        case .neon:
            glyph.foregroundStyle(tint)
                .shadow(color: tint.opacity(selected ? 0.95 : 0.55), radius: selected ? 9 : 5)
                .background(tint.opacity(selected ? 0.18 : 0), in: tileShape)
                .overlay(tileShape.strokeBorder(focused ? Color.white : tint.opacity(selected ? 0.9 : 0.28),
                                                lineWidth: focused ? 2 : 1.2).allowsHitTesting(false))
        case .floating:
            glyph.foregroundStyle(selected ? tint : .white.opacity(0.94))
                .fluxNavigationGlass(selected: selected, tint: tint, radius: metrics.tileRadius)
                .overlay(tileShape.strokeBorder(.white.opacity(focused ? 0.95 : 0), lineWidth: 2).allowsHitTesting(false))
        case .glass, .smoked:
            glyph.foregroundStyle(.white.opacity(selected || metrics.hero ? 1 : 0.94))
                .background { tintedTile }
                .overlay(tileShape.strokeBorder(.white.opacity(focused ? 0.95 : 0), lineWidth: 2).allowsHitTesting(false))
                .shadow(color: tint.opacity(metrics.hero ? 0.30 : selected ? 0.38 : 0.16),
                        radius: metrics.hero ? 16 : 6, y: metrics.hero ? 8 : 3)
        }
    }

    /// Every destination shows its colour at every size of the bar: the home
    /// screen and the compact bar under the column draw the same icons.
    private var tintedTile: some View {
        tileShape.fill(LinearGradient(colors: [tint.opacity(selected ? 0.74 : 0.52), tint.opacity(selected ? 0.36 : 0.18)],
                                      startPoint: .top, endPoint: .bottom))
            .overlay(tileShape.strokeBorder(LinearGradient(colors: [.white.opacity(selected ? 0.66 : 0.46), tint.opacity(0.28)],
                                                           startPoint: .top, endPoint: .bottom), lineWidth: 1))
    }
}
#endif

#if os(macOS)
/// Round control at the top of a navigation column: back, home.
struct DeskHeaderButton: View {
    let symbol: String
    let title: String
    let identifier: String
    /// Selected with the keyboard or a remote.
    var focused = false
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white.opacity(hovered || focused ? 1 : 0.82))
                .frame(width: 28, height: 28)
                .background(.white.opacity(hovered || focused ? 0.22 : 0.09), in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(focused ? 0.9 : 0), lineWidth: 2).allowsHitTesting(false))
                .contentShape(Circle())
        }
        .buttonStyle(FluxBareButtonStyle())
        .onHover { hovered = $0 }
        .help(title).accessibilityLabel(title).accessibilityIdentifier(identifier)
    }
}

/// Top of a navigation column: Back to the previous screen, the name of the
/// column, and the home screen.
struct DeskColumnHeader: View {
    let title: String
    var backTitle = "Retour"
    var back: (() -> Void)?
    var home: (() -> Void)?
    /// A panel above another screen closes; it has no screen to go back to.
    var close: (() -> Void)?
    /// Identifier selected with the keyboard or a remote, and the native
    /// focus that follows it.
    var focusedID: String?
    var systemFocus: FocusState<String?>.Binding?


    var body: some View {
        HStack(spacing: 8) {
            if let back {
                bound(DeskHeaderButton(symbol: "chevron.backward", title: backTitle, identifier: DeskZone.backID,
                                       focused: focusedID == DeskZone.backID, action: back), id: DeskZone.backID)
            }
            Text(title)
                .font(.caption.weight(.semibold)).tracking(1.5).foregroundStyle(.secondary)
                .lineLimit(1).minimumScaleFactor(0.75)
                .padding(.leading, back == nil ? 8 : 0)
            Spacer(minLength: 0)
            if let home {
                bound(DeskHeaderButton(symbol: "house.fill", title: "Accueil", identifier: DeskZone.homeID,
                                       focused: focusedID == DeskZone.homeID, action: home), id: DeskZone.homeID)
            }
            if let close { DeskHeaderButton(symbol: "xmark", title: "Fermer", identifier: "desk-close", action: close) }
        }
        .padding(.top, 1)
    }

    @ViewBuilder private func bound<V: View>(_ view: V, id: String) -> some View {
        if let systemFocus { view.focusable().focused(systemFocus, equals: id).focusEffectDisabled().id(id) }
        else { view }
    }
}
#endif
