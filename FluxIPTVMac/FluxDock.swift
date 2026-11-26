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

/// Sizes shared by the bar and by the screen that leaves room for it. The
/// compact form holds the same destinations in the width of the navigation
/// column, without labels. The hero form is the bar of the home screen, in
/// the middle of the window and scaled to its width.
struct FluxDockMetrics: Equatable {
    enum Form: Equatable { case compact, regular, hero(CGFloat) }
    let form: Form
    /// The icons of a long bar shrink a little to hold in the window, never
    /// below `floor`: a television is read from the sofa.
    let shrink: CGFloat
    static let floor: CGFloat = 0.82
    init(_ position: FluxDockPosition, shrink: CGFloat = 1) {
        form = position.isCompact ? .compact : .regular
        self.shrink = max(Self.floor, min(1, shrink))
    }
    init(hero scale: CGFloat) { form = .hero(max(Self.heroFloor, min(Self.heroLimit, scale))); shrink = 1 }

    /// The bar of a television, read from the sofa; a Mac draws the same
    /// at the size of its window.
    static var screenUnit: CGFloat { Desk.unit }
    static var heroLimit: CGFloat { 1.62 * Desk.scale }
    /// A bar of the home screen that holds many icons stays larger than
    /// the bar of the other screens.
    static var heroFloor: CGFloat { 0.6 * Desk.scale }

    var compact: Bool { form == .compact }
    var hero: Bool { unit != nil }
    private var unit: CGFloat? {
        if case .hero(let scale) = form { return scale }
        return nil
    }
    private var k: CGFloat { Self.screenUnit * shrink }

    var cell: CGSize {
        if let unit { return CGSize(width: 138 * unit, height: 150 * unit) }
        // The larger names of a television need their own height.
        return compact ? CGSize(width: 38 * k, height: 38 * k)
            : CGSize(width: 74 * k, height: 72 * k + Desk.tv(8))
    }
    var spacing: CGFloat { unit.map { 10 * $0 } ?? (compact ? 2 : 4) * k }
    var platePadding: CGFloat { unit.map { 20 * $0 } ?? (compact ? 8 : 9) * k }
    var tile: CGFloat { unit.map { 96 * $0 } ?? (compact ? 34 : 50) * k }
    var glyph: CGFloat { unit.map { 44 * $0 } ?? (compact ? 18 : 25) * k }
    var tileRadius: CGFloat { unit.map { 27 * $0 } ?? (compact ? 11 : 15) * k }
    /// Names stay readable from a sofa, whatever the size of the icons.
    var label: CGFloat { max(unit.map { 15.5 * $0 } ?? 11 * k, Desk.tv(18)) }
    var labelSpacing: CGFloat { unit.map { 11 * $0 } ?? 5 * k }
    var radius: CGFloat { unit.map { 46 * $0 } ?? (compact ? 20 : 28) * k }
    var maximumScale: Double { hero ? 1.2 : compact ? 1.34 : 1.42 }
    /// Room of the divider between two parts of the bar, and its line.
    var gap: CGFloat { unit.map { 22 * $0 } ?? (compact ? 6 : 12) * k }
    var rule: CGFloat { max(1.5, (unit ?? k) * 1.5) }
    /// Middle of the icons across the bar, from the top of a cell: the
    /// name under them moves it off the middle of the cell.
    var tileCenter: CGFloat {
        let content = tile + (compact ? 0 : labelSpacing + label * 1.2)
        return (cell.height - content) / 2 + tile / 2
    }
    /// Transparent room around the plate for magnified icons. It tracks the
    /// pointer but never receives a click.
    var growth: CGFloat { unit.map { 44 * $0 } ?? (compact ? 18 : 40) * k }
    static var edgeMargin: CGFloat { Desk.tv(10) }

    /// Width or height that the screen must leave free on the bar's edge.
    static func thickness(_ position: FluxDockPosition) -> CGFloat {
        let metrics = FluxDockMetrics(position)
        // The screens end clearly above the plate: nothing touches it.
        return (position.isVertical ? metrics.cell.width : metrics.cell.height) + metrics.platePadding * 2 + edgeMargin + Desk.pt(16)
    }
    /// Length of the plate along its axis, for a given number of icons and
    /// of dividers between them.
    func length(count: Int, breaks: Int = 0, vertical: Bool) -> CGFloat {
        let extent = vertical ? cell.height : cell.width
        return CGFloat(count) * extent + CGFloat(max(0, count - 1)) * spacing + CGFloat(breaks) * gap + platePadding * 2
    }
    /// Icons that hold in `room` at the smallest size they may take.
    static func capacity(_ position: FluxDockPosition, room: CGFloat, breaks: Int) -> Int {
        let metrics = FluxDockMetrics(position, shrink: floor)
        let extent = position.isVertical ? metrics.cell.height : metrics.cell.width
        let free = room - metrics.platePadding * 2 - CGFloat(breaks) * metrics.gap + metrics.spacing
        // A room that is not measured yet holds everything.
        let count = free / (extent + metrics.spacing)
        return count.isFinite && count < 1_000 ? max(0, Int(count)) : 1_000
    }
    /// What the icons shrink by for the bar to hold in `room`.
    static func shrink(_ position: FluxDockPosition, count: Int, breaks: Int, room: CGFloat) -> CGFloat {
        let natural = FluxDockMetrics(position).length(count: count, breaks: breaks, vertical: position.isVertical)
        return max(floor, min(1, room / max(1, natural)))
    }
    /// Scale of the bar of the home screen for these icons in this room,
    /// worked out in the points of a television.
    static func heroScale(count: Int, breaks: Int, width: CGFloat, height: CGFloat) -> CGFloat {
        // The length of the bar at the scale of one, in those points.
        let natural = CGFloat(count) * 138 + CGFloat(max(0, count - 1)) * 10 + CGFloat(breaks) * 22 + 40
        let share = max(0.01, Desk.scale)
        // 92: the room where the icons grow, on both sides of the plate.
        let fitted = min((width / share - 96) / (natural + 92), (height / share - 120) / 620)
        return share * min(1.2, max(0.6, fitted))
    }
}

/// One icon of the bar, as it is drawn. The picture of a title comes from
/// the catalogue each time: the bar keeps identifiers and names only.
struct DockTile: Identifiable, Equatable {
    enum Face: Equatable {
        case destination(FluxDockItem)
        /// A channel, a film, a series, a season or an episode. `item` is
        /// nil when the catalogue no longer holds it.
        case title(IPTVItem?, kind: IPTVMediaKind, badge: String?, progress: Double?)
        /// A list of favourites, or the shortcuts that found no room.
        case folder(covers: [IPTVItem], count: Int, symbol: String)
    }
    let entry: DockEntry
    /// Under the icon.
    let name: String
    /// The whole name, for the bubble above the icon and for VoiceOver.
    let full: String
    let face: Face
    var id: String { entry.id }
    var destination: FluxDockItem? {
        if case .destination(let item) = entry { return item }
        return nil
    }
    var tint: Color {
        switch face {
        case .destination(let item): item.tint
        case .title(_, let kind, _, _): FluxDockItem(kind: kind).tint
        case .folder: FluxDockItem.favorites.tint
        }
    }
}

/// A title of an open folder.
struct DockFanRow: Identifiable, Equatable {
    let shortcut: DockShortcut
    let item: IPTVItem?
    let badge: String?
    var id: String { DockEntry.fanPrefix + shortcut.id }
}

/// A folder of the bar, open above it as the fan of a stack of the Dock.
struct DockFan: Equatable {
    /// Icon of the bar that it rises from.
    let anchorID: String
    let title: String
    /// The nearest to the bar first.
    let rows: [DockFanRow]
    /// Titles that the fan has no room for.
    let more: Int
    /// Name of the last row, which opens them all on a screen of their
    /// own; nil for a list of favourites, named from what it holds.
    let listTitle: String?
    var ids: [String] { rows.map(\.id) + [DockEntry.fanAllID] }
}

/// Destination bar in the manner of the system Dock: a plate on one edge of
/// the window, icons that grow under the pointer, an order chosen by
/// dragging; then what the user keeps there, between dividers: shortcuts to
/// titles in named sections, the video in progress and the recents, and
/// lists of favourites as folders that open as a fan.
struct FluxDock: View {
    let tiles: [DockTile]
    /// Icons that a divider precedes.
    var breaks: [Int] = []
    var shrink: CGFloat = 1
    let selection: Set<FluxDockItem>
    let focusedID: String?
    let showsFocus: Bool
    let accent: Color
    let second: Color
    /// Scale of the home screen's bar; nil for the bar on its edge.
    var hero: CGFloat?
    /// Icon under the pointer, for a screen that describes it.
    var hover: ((DockTile?) -> Void)?
    /// Frame of the bar while the zones of the screen are shown: nil outside
    /// that overview, true when the bar is the zone being chosen.
    var zoneRing: Bool?
    /// The folder that is open above the bar.
    var fan: DockFan?
    let systemFocus: FocusState<String?>.Binding
    let activate: (DockEntry) -> Void
    /// A long press on a title: its lists and its place in the bar.
    var manage: ((DockEntry) -> Void)?
    var remove: ((DockEntry) -> Void)?
    /// A shortcut dragged to another place of its section.
    var reorder: ((DockShortcut, String, Int) -> Void)?
    var openFanRow: ((DockFanRow) -> Void)?
    var openFanList: (() -> Void)?
    let openSettings: () -> Void

    @AppStorage(FluxDockPosition.storageKey) private var position: FluxDockPosition = .defaultValue
    @AppStorage(FluxDockTheme.storageKey) private var theme: FluxDockTheme = .defaultValue
    @AppStorage(FluxDockItem.orderKey) private var storedOrder = ""
    @AppStorage(FluxDockItem.magnifyKey) private var magnifies = true
    @AppStorage(FluxAppearance.glassKey) private var richEffects = FluxAppearance.richDefault
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The icons slide and grow over several pictures, each of which lays
    /// the bar out again: a slow Apple TV shows the selected one at once.
    private var still: Bool {
        #if os(tvOS)
        reduceMotion || !richEffects
        #else
        reduceMotion
        #endif
    }

    @State private var pointer = 0.0
    @State private var hovering = false
    @State private var hovered: String?
    @State private var dragged: String?
    @State private var dragStartIndex = 0
    @State private var dragTranslation = 0.0
    @State private var suppressActivation = false
    #if FLUX_CATALOG_UI_TESTING && !os(tvOS)
    /// A capture has no pointer: the icon that one is placed on.
    @State private var fixturePointer: Int?
    #endif

    /// The home screen lays its bar out as a bar at the bottom, whatever edge
    /// the user chose for the other screens.
    private var placement: FluxDockPosition { hero == nil ? position : .bottom }
    private var vertical: Bool { placement.isVertical }
    private var metrics: FluxDockMetrics { hero.map { FluxDockMetrics(hero: $0) } ?? FluxDockMetrics(position, shrink: shrink) }
    private var magnifier: FluxDockMagnifier {
        let extent = Double(vertical ? metrics.cell.height : metrics.cell.width)
        return FluxDockMagnifier(count: tiles.count, cell: extent, spacing: Double(metrics.spacing),
                                 maximumScale: metrics.maximumScale, radius: (extent + Double(metrics.spacing)) * 2.2,
                                 breaks: breaks, gap: Double(metrics.gap))
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
    /// Icon drawn as selected. The bar reads the focus of a television
    /// by itself: the screen behind it is not rebuilt when the remote moves.
    private var shownID: String? {
        #if os(tvOS)
        systemFocus.wrappedValue
        #else
        focusedID
        #endif
    }
    /// A remote has no pointer: the icon it selects is the one that grows.
    /// While it walks an open folder, that folder stays the one.
    private var focusIndex: Int? {
        guard let id = shownID else { return nil }
        if let fan, fan.ids.contains(id) { return tiles.firstIndex { $0.id == fan.anchorID } }
        return tiles.firstIndex { $0.id == id }
    }
    private var magnification: Double {
        #if os(tvOS)
        return focusIndex != nil && magnifies && !reduceMotion ? 1 : 0
        #else
        return hovering && magnifies && dragged == nil && !reduceMotion ? 1 : 0
        #endif
    }
    private var magnifiedPoint: Double {
        #if os(tvOS)
        return focusIndex.map { magnifier.center($0) } ?? pointer
        #else
        #if FLUX_CATALOG_UI_TESTING
        if let fixturePointer, tiles.indices.contains(fixturePointer) { return magnifier.center(fixturePointer) }
        #endif
        return pointer
        #endif
    }
    /// The icon whose whole name is shown above it, as the Dock of a Mac
    /// names what the pointer rests on. A destination has its name under it.
    private var namedID: String? {
        guard fan == nil, dragged == nil else { return nil }
        #if os(tvOS)
        let id = showsFocus ? shownID : nil
        #else
        let id = hovering ? hovered : (showsFocus ? shownID : nil)
        #endif
        return id.flatMap { id in tiles.first { $0.id == id && $0.destination == nil }?.id }
    }

    var body: some View {
        let tiles = tiles
        let named = namedID
        FluxDockStrip(intensity: magnification, pointer: magnifiedPoint, magnifier: magnifier, metrics: metrics, vertical: vertical,
                      anchor: anchor, tiles: tiles, dragged: dragged, dragTranslation: dragTranslation,
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
                      cell: { tile in cell(tile) },
                      above: { centers, scales in above(centers: centers, scales: scales, named: named) })
            .animation(still ? nil : .spring(response: 0.24, dampingFraction: 0.8), value: magnification)
            .animation(still ? nil : .spring(response: 0.3, dampingFraction: 0.82), value: fan?.anchorID)
            #if os(tvOS)
            // The icons slide as the selection moves along the bar.
            .animation(still ? nil : .spring(response: 0.28, dampingFraction: 0.82), value: focusIndex)
            .padding(growthInsets)
            #else
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
            #endif
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Barre des destinations")
            #if FLUX_CATALOG_UI_TESTING && !os(tvOS)
            .onAppear {
                // A capture has no pointer: place one on the requested icon.
                if let index = UserDefaults.standard.object(forKey: "fluxiptv.fixture.dockPointer") as? Int {
                    fixturePointer = index; hovering = true
                }
            }
            // The bar is laid out again once the window is measured.
            .onChange(of: tiles.map(\.id), initial: true) { _, _ in
                if let index = fixturePointer, tiles.indices.contains(index), hovering { report(tiles[index]) }
            }
            #endif
    }

    #if !os(tvOS)
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
        report(magnifier.index(at: along).flatMap { tiles.indices.contains($0) ? tiles[$0] : nil })
    }

    private func report(_ tile: DockTile?) {
        guard tile?.id != hovered else { return }
        hovered = tile?.id
        hover?(tile)
    }
    #endif

    private func cell(_ tile: DockTile) -> some View {
        let id = tile.id
        let focused = showsFocus && shownID == id
        let open = fan?.anchorID == id
        return Button {
            guard !suppressActivation else { return }
            activate(tile.entry)
        } label: {
            FluxDockCell(tile: tile, selected: tile.destination.map(selection.contains) ?? open, focused: focused,
                         theme: theme, position: placement, metrics: metrics)
                #if os(tvOS)
                // The magnifier already grows the icon: it only follows the thumb.
                .fluxFocusLean(focused, grow: 1, angle: 8, shift: 5)
                .background(DeskFocusReport { FluxFocusLedger.shared.report(id, focused: $0) })
                #endif
        }
        .buttonStyle(FluxBareButtonStyle())
        #if os(tvOS)
        // A button already takes the focus of the remote.
        .focused(systemFocus, equals: id).focusEffectDisabled()
        #else
        .focusable().focused(systemFocus, equals: id).focusEffectDisabled()
        #endif
        .id(id)
        #if !os(tvOS)
        // On a television the selected icon is the magnified one already.
        .scaleEffect(focused && !reduceMotion ? (metrics.hero ? 1.06 : 1.12) : 1, anchor: anchor)
        .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.85), value: focused)
        #endif
        .accessibilityLabel(tile.full)
        .accessibilityValue(tile.destination.map(selection.contains) == true ? "Sélectionné" : open ? "Ouvert" : "")
        .accessibilityIdentifier("navigation-\(id)")
        #if os(tvOS) && FLUX_CATALOG_UI_TESTING
        .background(TVCatalogControlFrameProbe(identifier: "navigation-\(id)").allowsHitTesting(false))
        #endif
        #if os(tvOS)
        // Held, OK opens the lists of a title, where it leaves the bar.
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.65).onEnded { _ in
            if tile.destination == nil { manage?(tile.entry) }
        })
        #else
        .help(tile.destination == nil ? "" : tile.full)
        .simultaneousGesture(reorderGesture(tile))
        .contextMenu { tileMenu(tile); menu }
        #endif
    }

    /// What stands above the icons: the name of the one being pointed at,
    /// or the titles of the open folder.
    @ViewBuilder private func above(centers: [CGFloat], scales: [Double], named: String?) -> some View {
        let size = metrics.cell
        if let named, let index = tiles.firstIndex(where: { $0.id == named }), centers.indices.contains(index) {
            let rise = (vertical ? size.width : size.height) * CGFloat(scales[index] - 1) + metrics.label * 1.1
            FluxDockBubble(text: tiles[index].full, metrics: metrics)
                .fixedSize()
                .modifier(FluxDockAnchored(placement: placement, along: centers[index], rise: rise, metrics: metrics, centred: true))
                .allowsHitTesting(false)
                .transition(.opacity)
                .id("bubble-\(named)")
        }
        if let fan, let index = tiles.firstIndex(where: { $0.id == fan.anchorID }), centers.indices.contains(index) {
            FluxDockFanView(fan: fan, metrics: metrics, placement: placement, accent: accent,
                            focusedID: showsFocus ? shownID : nil, systemFocus: systemFocus,
                            open: { openFanRow?($0) }, openList: { openFanList?() })
                .fixedSize()
                .modifier(FluxDockAnchored(placement: placement, along: centers[index], rise: metrics.label * 0.9, metrics: metrics, centred: false))
                .transition(still ? .opacity : .opacity.combined(with: .scale(scale: 0.5, anchor: anchor)))
                .id("fan-\(fan.anchorID)")
        }
    }

    #if !os(tvOS)
    /// The icons that this one may be dragged among: the destinations, or
    /// the shortcuts of its section.
    private func run(of index: Int) -> Range<Int>? {
        func section(_ i: Int) -> String? {
            if case .shortcut(_, let section) = tiles[i].entry { return section }
            return nil
        }
        guard tiles.indices.contains(index) else { return nil }
        if tiles[index].destination != nil { return 0..<tiles.prefix { $0.destination != nil }.count }
        guard let own = section(index) else { return nil }
        var lower = index, upper = index + 1
        while lower > 0, section(lower - 1) == own { lower -= 1 }
        while upper < tiles.count, section(upper) == own { upper += 1 }
        return lower..<upper
    }

    private func reorderGesture(_ tile: DockTile) -> some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .named("flux-dock"))
            .onChanged { value in
                guard let current = tiles.firstIndex(where: { $0.id == tile.id }), let range = run(of: current) else { return }
                if dragged != tile.id {
                    dragged = tile.id; dragStartIndex = current; suppressActivation = true; hovering = false
                }
                let translation = Double(vertical ? value.translation.height : value.translation.width)
                let wanted = Double(dragStartIndex) + translation / magnifier.pitch
                let target = max(range.lowerBound, min(range.upperBound - 1, Int(wanted.rounded())))
                if target != current {
                    switch tile.entry {
                    case .destination(let item):
                        storedOrder = FluxDockItem.stored(FluxDockItem.moving(item, to: target, in: tiles.compactMap(\.destination)))
                    case .shortcut(let shortcut, let section):
                        reorder?(shortcut, section, target - range.lowerBound)
                    case .resume, .recent, .stack, .more: break
                    }
                }
                // The icon stays under the pointer while its slot changes.
                dragTranslation = translation - (magnifier.start(target) - magnifier.start(dragStartIndex))
            }
            .onEnded { _ in
                guard dragged != nil else { return }
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

    /// What a secondary click offers on an icon, before the menu of the bar.
    @ViewBuilder private func tileMenu(_ tile: DockTile) -> some View {
        switch tile.entry {
        case .destination, .more: EmptyView()
        case .shortcut:
            Button("Ouvrir") { activate(tile.entry) }
            Button("Favoris, listes et dock…") { manage?(tile.entry) }
            Button("Retirer du dock") { remove?(tile.entry) }
            Divider()
        case .resume:
            Button("Reprendre") { activate(tile.entry) }
            Button("Garder dans le dock…") { manage?(tile.entry) }
            Divider()
        case .recent:
            Button("Ouvrir") { activate(tile.entry) }
            Button("Garder dans le dock…") { manage?(tile.entry) }
            Button("Retirer des récents") { remove?(tile.entry) }
            Divider()
        case .stack:
            Button("Ouvrir") { activate(tile.entry) }
            Button("Retirer du dock") { remove?(tile.entry) }
            Divider()
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
    #endif
}

/// Places a view beside the bar, away from the edge that holds it, at the
/// icon whose middle along the bar is `along`. Centred on that icon, or
/// with its last edge on the icon's: the titles of a folder then have the
/// whole window before them for their names.
private struct FluxDockAnchored: ViewModifier {
    let placement: FluxDockPosition
    let along: CGFloat
    let rise: CGFloat
    let metrics: FluxDockMetrics
    let centred: Bool

    func body(content: Content) -> some View {
        let pad = metrics.platePadding, size = metrics.cell
        let alignment: Alignment
        let point: CGPoint
        switch placement {
        case .bottom, .corner:
            alignment = centred ? .bottom : .bottomTrailing
            point = CGPoint(x: along + (centred ? 0 : size.width / 2), y: pad - rise)
        case .top:
            alignment = centred ? .top : .topTrailing
            point = CGPoint(x: along + (centred ? 0 : size.width / 2), y: pad + size.height + rise)
        case .leading:
            alignment = centred ? .leading : .bottomLeading
            point = CGPoint(x: pad + size.width + rise, y: along + (centred ? 0 : size.height / 2))
        case .trailing:
            alignment = centred ? .trailing : .bottomTrailing
            point = CGPoint(x: pad - rise, y: along + (centred ? 0 : size.height / 2))
        }
        // A point of no size: what it carries reaches past the bar without
        // changing the room that the bar takes.
        return Color.clear.frame(width: 0, height: 0)
            .overlay(alignment: alignment) { content }
            .offset(x: point.x, y: point.y)
    }
}

/// The whole name of an icon, above it.
private struct FluxDockBubble: View {
    let text: String
    let metrics: FluxDockMetrics

    var body: some View {
        Text(text).font(.system(size: metrics.label, weight: .semibold)).lineLimit(1)
            .foregroundStyle(.white)
            .padding(.horizontal, metrics.label * 0.8).padding(.vertical, metrics.label * 0.38)
            .background(Color(red: 0.06, green: 0.065, blue: 0.08).opacity(0.92), in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.22), lineWidth: 1))
            .shadow(color: .black.opacity(0.45), radius: 8, y: 4)
            .frame(maxWidth: metrics.label * 28)
    }
}

/// The titles of an open folder: one above the other from the bar, each
/// with its name beside it, on a slight curve, as the fan of a stack.
private struct FluxDockFanView: View {
    let fan: DockFan
    let metrics: FluxDockMetrics
    let placement: FluxDockPosition
    let accent: Color
    let focusedID: String?
    let systemFocus: FocusState<String?>.Binding
    let open: (DockFanRow) -> Void
    let openList: () -> Void

    private var side: CGFloat { metrics.tile * 0.9 }
    /// The names stand on the side where the window is: before the icons,
    /// except beside a bar on the leading edge.
    private var namesFirst: Bool { placement != .leading }
    /// Rows rise from a bar at the bottom or on a side, and hang from one at the top.
    private var rises: Bool { placement != .top }
    private var curved: Bool { !placement.isVertical }

    var body: some View {
        let count = fan.rows.count + 1
        VStack(alignment: namesFirst ? .trailing : .leading, spacing: metrics.label * 0.42) {
            ForEach(0..<count, id: \.self) { slot in
                // The nearest to the bar is the first of the list.
                let index = rises ? count - 1 - slot : slot
                Group {
                    if index < fan.rows.count { row(fan.rows[index]) } else { listRow }
                }
                .offset(x: curve(index))
                .rotationEffect(.degrees(curved ? Double(index) * (rises ? 1 : -1) * 1.1 : 0), anchor: namesFirst ? .trailing : .leading)
            }
        }
        #if os(tvOS)
        .focusSection()
        #endif
        .accessibilityElement(children: .contain)
        .accessibilityLabel(fan.title)
        .accessibilityIdentifier("dock-fan")
    }

    /// Each row leans a little further than the one under it.
    private func curve(_ index: Int) -> CGFloat {
        curved ? CGFloat(index * index) * metrics.label * 0.085 : 0
    }

    private func row(_ row: DockFanRow) -> some View {
        line(id: row.id, name: row.shortcut.title, action: { open(row) }) {
            FluxDockArt(item: row.item, kind: row.shortcut.kind, badge: row.badge, progress: nil,
                        side: side, radius: metrics.tileRadius * 0.9, focused: false)
        }
    }

    private var listRow: some View {
        line(id: DockEntry.fanAllID,
             name: fan.listTitle ?? (fan.more > 0 ? "Tout afficher · \(fan.more) de plus" : fan.rows.isEmpty ? "Liste vide · l’ouvrir" : "Ouvrir la liste"),
             action: openList) {
            Image(systemName: "arrow.up.forward.square.fill").font(.system(size: side * 0.5, weight: .medium))
                .symbolRenderingMode(.hierarchical).foregroundStyle(.white)
                .frame(width: side, height: side)
                .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: metrics.tileRadius * 0.9, style: .continuous))
        }
    }

    private func line<Art: View>(id: String, name: String, action: @escaping () -> Void,
                                 @ViewBuilder art: () -> Art) -> some View {
        let picture = art()
        let gap = metrics.label * 0.6
        return Button(action: action) {
            FluxFocused(id: id, logical: focusedID == id) { focused in
                // The control is the picture alone, as wide as an icon of
                // the bar and right above the folder: Down from the first
                // title then leads a remote to that folder and to no
                // other icon. Its name is drawn beside it.
                picture.frame(width: metrics.cell.width, height: side)
                    .overlay {
                        RoundedRectangle(cornerRadius: metrics.tileRadius, style: .continuous)
                            .strokeBorder(.white.opacity(focused ? 0.95 : 0), lineWidth: 2)
                            .padding(.horizontal, (metrics.cell.width - side) / 2 - 4).padding(.vertical, -4)
                            .allowsHitTesting(false)
                    }
                    .overlay(alignment: namesFirst ? .leading : .trailing) {
                        label(name, focused: focused).fixedSize()
                            .alignmentGuide(namesFirst ? .leading : .trailing) { size in
                                namesFirst ? size[.trailing] + gap : size[.leading] - gap
                            }
                    }
                    .scaleEffect(focused ? 1.05 : 1, anchor: namesFirst ? .trailing : .leading)
            }
        }
        .buttonStyle(FluxBareButtonStyle())
        #if os(tvOS)
        .focused(systemFocus, equals: id).focusEffectDisabled()
        #else
        .focusable().focused(systemFocus, equals: id).focusEffectDisabled()
        #endif
        .id(id)
        .accessibilityLabel(name)
        .accessibilityIdentifier(id)
        #if os(tvOS) && FLUX_CATALOG_UI_TESTING
        .background(TVCatalogControlFrameProbe(identifier: id).allowsHitTesting(false))
        #endif
    }

    private func label(_ name: String, focused: Bool) -> some View {
        Text(name).font(.system(size: metrics.label, weight: .semibold)).lineLimit(1)
            .foregroundStyle(focused ? .black : .white)
            .padding(.horizontal, metrics.label * 0.8).padding(.vertical, metrics.label * 0.42)
            .background(focused ? AnyShapeStyle(Color.white) : AnyShapeStyle(Color(red: 0.06, green: 0.065, blue: 0.08).opacity(0.90)), in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(focused ? 0 : 0.22), lineWidth: 1))
            .shadow(color: .black.opacity(0.45), radius: 8, y: 4)
            .frame(maxWidth: metrics.label * 26, alignment: namesFirst ? .trailing : .leading)
    }
}

/// Lays the icons out by hand so that the pointer drives their size on every
/// frame, while slot changes and the entry of the effect keep their animation.
private struct FluxDockStrip<Plate: View, Cell: View, Above: View>: View, Animatable {
    var intensity: Double
    let pointer: Double
    let magnifier: FluxDockMagnifier
    let metrics: FluxDockMetrics
    let vertical: Bool
    let anchor: UnitPoint
    let tiles: [DockTile]
    let dragged: String?
    let dragTranslation: Double
    let reduceMotion: Bool
    @ViewBuilder let plate: () -> Plate
    @ViewBuilder let cell: (DockTile) -> Cell
    /// Drawn above the icons from where each one stands: its middle along
    /// the bar, in the coordinates of the plate, and its scale.
    @ViewBuilder let above: ([CGFloat], [Double]) -> Above

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
        let centers = tiles.indices.map { pad + CGFloat(magnifier.center($0) + layout.offsets[$0]) }
        ZStack(alignment: .topLeading) {
            plate()
                .frame(width: base.width + (vertical ? 0 : stretch), height: base.height + (vertical ? stretch : 0))
                .offset(x: vertical ? 0 : CGFloat(layout.leading), y: vertical ? CGFloat(layout.leading) : 0)
            // A divider stands half way between the icons it parts, wherever
            // the magnification has moved them.
            ForEach(magnifier.breaks, id: \.self) { index in
                let before = magnifier.center(index - 1) + layout.offsets[index - 1] + magnifier.cell * layout.scales[index - 1] / 2
                let after = magnifier.center(index) + layout.offsets[index] - magnifier.cell * layout.scales[index] / 2
                let along = pad + CGFloat((before + after) / 2)
                let across = pad + (vertical ? size.width / 2 : metrics.tileCenter)
                Capsule().fill(.white.opacity(0.30))
                    .frame(width: vertical ? metrics.tile * 0.72 : metrics.rule, height: vertical ? metrics.rule : metrics.tile * 0.72)
                    .position(x: vertical ? across : along, y: vertical ? along : across)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            ForEach(Array(tiles.enumerated()), id: \.element.id) { index, tile in
                let lifted = tile.id == dragged
                let shift = CGFloat(magnifier.start(index) + (lifted ? dragTranslation : layout.offsets[index]))
                cell(tile)
                    .frame(width: size.width, height: size.height)
                    .scaleEffect(lifted ? 1.1 : layout.scales[index], anchor: anchor)
                    .shadow(color: .black.opacity(lifted ? 0.45 : 0), radius: 10, y: 6)
                    .offset(x: pad + (vertical ? 0 : shift), y: pad + (vertical ? shift : 0))
                    .zIndex(lifted ? 10 : layout.scales[index])
                    .animation(lifted || reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.82), value: index)
            }
            above(centers, layout.scales).zIndex(20)
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

/// The picture of a title in the bar: the logo of a channel on a plate of
/// its own, the sleeve of a film or of a series as the catalogue shows it.
struct FluxDockArt: View {
    let item: IPTVItem?
    let kind: IPTVMediaKind
    /// A season or an episode says which, in a corner.
    let badge: String?
    /// What was watched of a video left unfinished.
    let progress: Double?
    let side: CGFloat
    let radius: CGFloat
    let focused: Bool

    var body: some View {
        let tint = FluxDockItem(kind: kind).tint
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        Group {
            if kind == .live || item == nil {
                ArtworkView(url: item?.logoURL, fit: true) {
                    Image(systemName: FluxDockItem(kind: kind).symbol).font(.system(size: side * 0.44, weight: .medium))
                        .symbolRenderingMode(.hierarchical).foregroundStyle(.white.opacity(item == nil ? 0.5 : 0.94))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(side * 0.13)
                .frame(width: side, height: side)
                .background(LinearGradient(colors: [tint.opacity(0.46), tint.opacity(0.16)], startPoint: .top, endPoint: .bottom), in: shape)
                .background(Color(red: 0.05, green: 0.055, blue: 0.07).opacity(0.88), in: shape)
                .overlay(shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.42), tint.opacity(0.26)],
                                                           startPoint: .top, endPoint: .bottom), lineWidth: 1).allowsHitTesting(false))
                .overlay(shape.strokeBorder(.white.opacity(focused ? 0.95 : 0), lineWidth: 2).allowsHitTesting(false))
            } else if let item {
                // The middle of its sleeve, as large as the other icons: a
                // whole sleeve would be half their size from a sofa.
                Color.clear.frame(width: side, height: side)
                    .overlay {
                        ArtworkView(url: item.logoURL, fit: false) {
                            Image(systemName: FluxDockItem(kind: kind).symbol).font(.system(size: side * 0.44, weight: .medium))
                                .symbolRenderingMode(.hierarchical).foregroundStyle(.white.opacity(0.94))
                                .frame(width: side, height: side)
                        }
                        .frame(width: side)
                    }
                    .background(LinearGradient(colors: [tint.opacity(0.46), tint.opacity(0.16)], startPoint: .top, endPoint: .bottom))
                    .background(Color(red: 0.05, green: 0.055, blue: 0.07).opacity(0.88))
                    .clipShape(shape)
                    .overlay(shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.42), tint.opacity(0.26)],
                                                               startPoint: .top, endPoint: .bottom), lineWidth: 1).allowsHitTesting(false))
                    .overlay(shape.strokeBorder(.white.opacity(focused ? 0.95 : 0), lineWidth: 2).allowsHitTesting(false))
            }
        }
        .overlay(alignment: .bottom) {
            if let progress {
                GeometryReader { geometry in
                    Capsule().fill(.black.opacity(0.62))
                        .overlay(alignment: .leading) {
                            Capsule().fill(tint).frame(width: max(geometry.size.height, geometry.size.width * min(1, max(0, progress))))
                        }
                }
                .frame(width: side * 0.78, height: max(3, side * 0.075))
                .offset(y: side * 0.035)
            }
        }
        .overlay(alignment: .topTrailing) {
            if let badge {
                Text(badge).font(.system(size: max(9, side * 0.21), weight: .heavy)).lineLimit(1).fixedSize()
                    .foregroundStyle(.black)
                    .padding(.horizontal, side * 0.09).padding(.vertical, side * 0.03)
                    .background(tint, in: Capsule())
                    .overlay(Capsule().strokeBorder(.black.opacity(0.35), lineWidth: 0.8))
                    .offset(x: side * 0.10, y: -side * 0.08)
            }
        }
        .shadow(color: .black.opacity(0.35), radius: 5, y: 3)
        .accessibilityHidden(true)
    }
}

struct FluxDockCell: View {
    let tile: DockTile
    let selected: Bool
    let focused: Bool
    let theme: FluxDockTheme
    let position: FluxDockPosition
    var metrics = FluxDockMetrics(.bottom)

    private var tint: Color { tile.tint }
    private var tileShape: RoundedRectangle { RoundedRectangle(cornerRadius: metrics.tileRadius, style: .continuous) }

    var body: some View {
        VStack(spacing: metrics.labelSpacing) {
            face
            if !metrics.compact {
                Text(tile.name)
                    .font(.system(size: metrics.label, weight: .semibold)).lineLimit(1)
                    .minimumScaleFactor(tile.destination == nil ? 1 : 0.8)
                    .truncationMode(.tail)
                    .foregroundStyle(selected && theme != .vivid ? tint : .white.opacity(0.88))
                    .shadow(color: .black.opacity(theme == .floating ? 0.8 : 0.35), radius: 3, y: 1)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: indicatorAlignment) {
            if selected {
                Capsule().fill(theme == .vivid ? Color.white : tint)
                    .frame(width: Desk.tv(position.isVertical ? 3.5 : metrics.compact ? 12 : 16),
                           height: Desk.tv(position.isVertical ? 16 : metrics.compact ? 3 : 3.5))
                    .offset(x: Desk.tv(indicatorOffset.width), y: Desk.tv(indicatorOffset.height))
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

    @ViewBuilder private var face: some View {
        switch tile.face {
        case .destination(let item): destination(item)
        case .title(let item, let kind, let badge, let progress):
            FluxDockArt(item: item, kind: kind, badge: badge, progress: progress,
                        side: metrics.tile, radius: metrics.tileRadius, focused: focused)
        case .folder(let covers, let count, let symbol): folder(covers, count: count, symbol: symbol)
        }
    }

    /// A folder shows what it holds: its first titles, one behind the
    /// other, as a stack of the Dock does.
    private func folder(_ covers: [IPTVItem], count: Int, symbol: String) -> some View {
        let side = metrics.tile
        return ZStack {
            tintedTile
            if covers.isEmpty {
                Image(systemName: symbol).font(.system(size: metrics.glyph, weight: .medium))
                    .symbolRenderingMode(.hierarchical).foregroundStyle(.white.opacity(0.94))
            } else {
                let shown = Array(covers.prefix(3))
                ForEach(Array(shown.enumerated().reversed()), id: \.element.id) { index, item in
                    let depth = CGFloat(index)
                    FluxDockArt(item: item, kind: item.kind, badge: nil, progress: nil,
                                side: side * 0.66, radius: metrics.tileRadius * 0.55, focused: false)
                        .scaleEffect(1 - depth * 0.10)
                        .offset(x: (depth - CGFloat(shown.count - 1) / 2) * side * 0.17, y: -depth * side * 0.035)
                        .opacity(1 - Double(depth) * 0.16)
                }
            }
        }
        .frame(width: side, height: side)
        .overlay(tileShape.strokeBorder(.white.opacity(focused ? 0.95 : 0), lineWidth: 2).allowsHitTesting(false))
        .overlay(alignment: .topTrailing) {
            if count > 0 {
                Text("\(count)").font(.system(size: max(9, side * 0.20), weight: .heavy)).monospacedDigit().lineLimit(1).fixedSize()
                    .foregroundStyle(.black)
                    .padding(.horizontal, side * 0.09).padding(.vertical, side * 0.03)
                    .background(tint, in: Capsule())
                    .overlay(Capsule().strokeBorder(.black.opacity(0.35), lineWidth: 0.8))
                    .offset(x: side * 0.10, y: -side * 0.08)
            }
        }
        .shadow(color: tint.opacity(0.16), radius: 6, y: 3)
        .accessibilityHidden(true)
    }

    @ViewBuilder private func destination(_ item: FluxDockItem) -> some View {
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

#if os(macOS) || os(tvOS)
/// Round control at the top of a navigation column: back, home.
struct DeskHeaderButton: View {
    let symbol: String
    let title: String
    let identifier: String
    /// Selected with the keyboard or a remote.
    var focused = false
    let action: () -> Void
    @State private var hovered = false
    private var side: CGFloat { 28 * FluxDockMetrics.screenUnit }

    var body: some View {
        Button(action: action) { Glyph(symbol: symbol, side: side, lit: hovered || focused, ringed: focused) }
        .buttonStyle(FluxBareButtonStyle())
        #if os(macOS)
        .onHover { hovered = $0 }
        .help(title)
        #endif
        .accessibilityLabel(title).accessibilityIdentifier(identifier)
    }

    /// Where nothing tells this button that it is selected, the remote of a
    /// television still shows on it.
    private struct Glyph: View {
        let symbol: String
        let side: CGFloat
        let lit: Bool
        let ringed: Bool
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            let on = lit || isFocused, ring = ringed || isFocused
            Image(systemName: symbol).font(.system(size: side * 0.43, weight: .bold))
                .foregroundStyle(.white.opacity(on ? 1 : 0.82))
                .frame(width: side, height: side)
                .background(.white.opacity(on ? 0.22 : 0.09), in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(ring ? 0.9 : 0), lineWidth: 2).allowsHitTesting(false))
                .contentShape(Circle())
                .scaleEffect(ring ? 1.12 : 1)
        }
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
        HStack(spacing: Desk.tv(8)) {
            if let back {
                bound(DeskHeaderButton(symbol: "chevron.backward", title: backTitle, identifier: DeskZone.backID,
                                       focused: focusedID == DeskZone.backID, action: back), id: DeskZone.backID)
            }
            Text(title)
                #if os(tvOS)
                .font(.caption.weight(.semibold))
                #else
                // The caption of a television, at the size of the window.
                .font(.system(size: Desk.tv(25), weight: .semibold))
                #endif
                .tracking(1.5).foregroundStyle(.secondary)
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
        if let systemFocus {
            #if os(tvOS)
            view.focused(systemFocus, equals: id).focusEffectDisabled().id(id)
            #else
            view.focusable().focused(systemFocus, equals: id).focusEffectDisabled().id(id)
            #endif
        } else { view }
    }
}
#endif
