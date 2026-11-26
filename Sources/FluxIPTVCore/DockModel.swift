import Foundation

/// Edge of the window that carries the destination bar. The leading and
/// trailing edges present the same destinations as a column.
public enum FluxDockPosition: String, CaseIterable, Identifiable, Sendable {
    /// `corner` is a compact bar under the navigation column: the rest of the
    /// window, to its bottom edge, belongs to the content.
    case bottom, corner, top, leading, trailing
    public static let storageKey = "fluxiptv.dock.position.v1"
    public static let defaultValue: Self = .bottom
    public var id: String { rawValue }
    public var isVertical: Bool { self == .leading || self == .trailing }
    /// Icons without labels, sized to the navigation column.
    public var isCompact: Bool { self == .corner }
    public var title: String {
        switch self {
        case .bottom: "En bas"
        case .corner: "Sous la colonne"
        case .top: "En haut"
        case .leading: "À gauche"
        case .trailing: "À droite"
        }
    }
    /// Direction that leaves the bar toward the screen it serves.
    public var inward: RemoteAction {
        switch self {
        case .bottom, .corner: .up
        case .top: .down
        case .leading: .right
        case .trailing: .left
        }
    }
    /// Direction that reaches the bar from the matching edge of the screen.
    public var outward: RemoteAction {
        switch self {
        case .bottom, .corner: .down
        case .top: .up
        case .leading: .left
        case .trailing: .right
        }
    }
}

/// The look of the plate and of its icons. Those of other systems and other
/// years are drawn for the app, after the manner of their time: no icon, no
/// name and no mark of a system is borrowed.
public enum FluxDockTheme: String, CaseIterable, Identifiable, Sendable {
    case glass, vivid, smoked, neon, floating
    case tactile, pebbles, frost
    case gel, hills
    case bevel, eightColor, fourColor, greenDesk, phosphor
    public static let storageKey = "fluxiptv.dock.theme.v1"
    public static let defaultValue: Self = .glass
    public var id: String { rawValue }

    public enum Family: String, CaseIterable, Identifiable, Sendable {
        case flux, today, millennium, retro
        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .flux: "Flux"
            case .today: "Téléphones et bureaux d’aujourd’hui"
            case .millennium: "Années 2000"
            case .retro: "Rétro"
            }
        }
        public var themes: [FluxDockTheme] { FluxDockTheme.allCases.filter { $0.family == self } }
    }
    public var family: Family {
        switch self {
        case .glass, .vivid, .smoked, .neon, .floating: .flux
        case .tactile, .pebbles, .frost: .today
        case .gel, .hills: .millennium
        case .bevel, .eightColor, .fourColor, .greenDesk, .phosphor: .retro
        }
    }
    /// Drawn in square pixels, as the screens of their years were.
    public var pixelated: Bool { family == .retro }

    public var title: String {
        switch self {
        case .glass: "Verre"
        case .vivid: "Couleurs"
        case .smoked: "Fumé"
        case .neon: "Néon"
        case .floating: "Sans fond"
        case .tactile: "Tactile"
        case .pebbles: "Galets"
        case .frost: "Givre"
        case .gel: "Gélule"
        case .hills: "Collines"
        case .bevel: "Biseaux"
        case .eightColor: "Huit couleurs"
        case .fourColor: "Quatre couleurs"
        case .greenDesk: "Bureau vert"
        case .phosphor: "Phosphore"
        }
    }
    public var subtitle: String {
        switch self {
        case .glass: "Plaque translucide, icônes teintées."
        case .vivid: "Pastilles pleines, couleurs franches."
        case .smoked: "Plaque sombre et sobre."
        case .neon: "Contour lumineux aux couleurs de l’écran."
        case .floating: "Icônes séparées, sans plaque."
        case .tactile: "Carrés arrondis en dégradé sur verre clair, comme un téléphone."
        case .pebbles: "Ronds aux tons doux, plaque en pilule, sélection en gélule."
        case .frost: "Verre dépoli, coins doux, trait sous l’écran ouvert."
        case .gel: "Gel brillant sur fines rayures, triangle sous l’écran ouvert. 2001."
        case .hills: "Bleu franc, boutons ronds et brillants. 2001."
        case .bevel: "Gris en relief, bouton enfoncé, pixels de 1995."
        case .eightColor: "Gris biseauté et bleu, pixels fins de 1992."
        case .fourColor: "Bleu, blanc, noir et orange, pixels de 1987."
        case .greenDesk: "Noir et blanc sur fond vert, sélection inversée. 1985."
        case .phosphor: "Vert sur noir, gros pixels, vidéo inverse. 1977."
        }
    }
}

/// Destinations of the bar. Their order is a user preference; a destination
/// added by a later version joins the end of a saved order.
public enum FluxDockItem: String, CaseIterable, Identifiable, Sendable {
    case live, movie, series, search, favorites, settings
    public static let orderKey = "fluxiptv.dock.order.v1"
    public static let magnifyKey = "fluxiptv.dock.magnify.v1"
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .live: "TV"
        case .movie: "Films"
        case .series: "Séries"
        case .search: "Recherche"
        case .favorites: "Favoris"
        case .settings: "Réglages"
        }
    }
    /// Identifier shared with the keyboard and remote focus model.
    public var focusID: String {
        switch self {
        case .live: "tab-live"
        case .movie: "tab-movie"
        case .series: "tab-series"
        case .search: "search"
        case .favorites: "tab-favorites"
        case .settings: "settings"
        }
    }
    public var mediaKind: IPTVMediaKind? {
        switch self {
        case .live: .live
        case .movie: .movie
        case .series: .series
        default: nil
        }
    }
    public init?(focusID: String) {
        guard let match = Self.allCases.first(where: { $0.focusID == focusID }) else { return nil }
        self = match
    }
    public init(kind: IPTVMediaKind) {
        switch kind {
        case .live: self = .live
        case .movie: self = .movie
        case .series: self = .series
        }
    }

    /// Unknown and repeated entries are dropped; missing destinations follow.
    public static func order(from stored: String) -> [FluxDockItem] {
        var result: [FluxDockItem] = []
        for token in stored.split(separator: ",") {
            guard let item = FluxDockItem(rawValue: token.trimmingCharacters(in: .whitespaces)),
                  !result.contains(item) else { continue }
            result.append(item)
        }
        for item in allCases where !result.contains(item) { result.append(item) }
        return result
    }
    public static func stored(_ order: [FluxDockItem]) -> String {
        order.map(\.rawValue).joined(separator: ",")
    }
    /// Places `item` at `index` of the complete order; an index outside the
    /// bar is clamped to its ends.
    public static func moving(_ item: FluxDockItem, to index: Int, in order: [FluxDockItem]) -> [FluxDockItem] {
        var result = order.filter { $0 != item }
        guard result.count == order.count - 1 else { return order }
        result.insert(item, at: max(0, min(result.count, index)))
        return result
    }
}

/// macOS-style magnification of equally sized cells along one axis. Positions
/// are measured from the start of the first cell, before any magnification.
/// A divider may stand before some cells, as between the parts of the Dock
/// of a Mac: it takes a fixed room that never grows.
public struct FluxDockMagnifier: Equatable, Sendable {
    public struct Layout: Equatable, Sendable {
        /// Scale of each cell.
        public let scales: [Double]
        /// Displacement of each cell centre along the axis.
        public let offsets: [Double]
        /// Displacement of the bar's first edge (zero or negative).
        public let leading: Double
        /// Displacement of the bar's last edge (zero or positive).
        public let trailing: Double
    }

    public var count: Int
    public var cell: Double
    public var spacing: Double
    public var maximumScale: Double
    public var radius: Double
    /// Cells that a divider precedes, in increasing order, and its room.
    public var breaks: [Int]
    public var gap: Double

    public init(count: Int, cell: Double, spacing: Double, maximumScale: Double, radius: Double,
                breaks: [Int] = [], gap: Double = 0) {
        self.count = max(0, count)
        self.cell = max(1, cell)
        self.spacing = max(0, spacing)
        self.maximumScale = max(1, maximumScale)
        self.radius = max(1, radius)
        // A divider stands between two cells: never before the first.
        let limit = self.count
        self.breaks = Array(Set(breaks.filter { $0 > 0 && $0 < limit })).sorted()
        self.gap = max(0, gap)
    }

    public var pitch: Double { cell + spacing }
    public var length: Double {
        count == 0 ? 0 : Double(count) * cell + Double(count - 1) * spacing + Double(breaks.count) * gap
    }
    /// Where a cell starts, the dividers before it included.
    public func start(_ index: Int) -> Double {
        Double(index) * pitch + Double(breaks.prefix { $0 <= index }.count) * gap
    }
    public func center(_ index: Int) -> Double { start(index) + cell / 2 }
    /// Middle of the divider that stands before a cell.
    public func divider(before index: Int) -> Double { start(index) - (spacing + gap) / 2 }

    /// Index of the cell at an unmagnified position; a position between
    /// two cells belongs to the one before it.
    public func index(at position: Double) -> Int? {
        guard count > 0, position.isFinite else { return nil }
        var index = Int(max(0, min(Double(count - 1), (position / pitch).rounded(.down))))
        while index > 0, start(index) > position { index -= 1 }
        return index
    }

    /// The point under the pointer keeps its place: cells before it move
    /// toward the start, cells after it toward the end, as the system Dock does.
    public func layout(pointer: Double?, intensity: Double = 1) -> Layout {
        let rest = Layout(scales: Array(repeating: 1, count: count), offsets: Array(repeating: 0, count: count),
                          leading: 0, trailing: 0)
        guard count > 0, let pointer, pointer.isFinite, intensity.isFinite, intensity > 0 else { return rest }
        let strength = min(1, intensity) * (maximumScale - 1)
        var scales: [Double] = []
        scales.reserveCapacity(count)
        for index in 0..<count {
            let distance = abs(center(index) - pointer) / radius
            // Raised cosine: full size under the pointer, at rest at the radius,
            // with no visible step at either end.
            let falloff = distance >= 1 ? 0 : (cos(distance * .pi) + 1) / 2
            scales.append(1 + strength * falloff)
        }
        let growth = scales.map { cell * ($0 - 1) }
        var before: [Double] = []
        before.reserveCapacity(count)
        var total = 0.0
        for value in growth { before.append(total); total += value }
        // Growth accumulated up to the pointer itself, linear inside a cell.
        let anchor: Double
        if pointer <= 0 { anchor = 0 }
        else if pointer >= length { anchor = total }
        else {
            let index = index(at: pointer) ?? 0
            let inside = min(1, max(0, (pointer - start(index)) / cell))
            anchor = before[index] + growth[index] * inside
        }
        let offsets = (0..<count).map { before[$0] + growth[$0] / 2 - anchor }
        return Layout(scales: scales, offsets: offsets, leading: -anchor, trailing: total - anchor)
    }
}

public enum FluxDockNavigation {
    /// Routes one direction between the bar and the screen it serves.
    /// `content` performs the screen's own move and returns the identifier it
    /// received when the selection already sits on that edge.
    ///
    /// A fresh press — not a key held down — leaves no key without effect
    /// (`beyond`): `backID` is the Back key of the bar, `topID` the control
    /// at the top of the screen.
    public static func move(from current: String?, action: RemoteAction, position: FluxDockPosition,
                            dockIDs: [String], preferredDockID: String?, entryID: String?,
                            backID: String? = nil, topID: String? = nil, fresh: Bool = false,
                            content: (String?, RemoteAction) -> String?) -> String? {
        guard !dockIDs.isEmpty else { return content(current, action) }
        if let current, let index = dockIDs.firstIndex(of: current) {
            if fresh, let around = beyond(current, action: action, position: position, dockIDs: dockIDs,
                                          preferredDockID: preferredDockID, backID: backID, topID: topID) { return around }
            let previous: RemoteAction = position.isVertical ? .up : .left
            let next: RemoteAction = position.isVertical ? .down : .right
            if action == previous { return dockIDs[max(0, index - 1)] }
            if action == next { return dockIDs[min(dockIDs.count - 1, index + 1)] }
            if action == position.inward { return entryID ?? content(nil, action) ?? current }
            return current
        }
        let target = content(current, action)
        guard target == nil || target == current else { return target }
        if action == position.outward { return preferred(preferredDockID, in: dockIDs) }
        guard fresh else { return target }
        return beyond(current, action: action, position: position, dockIDs: dockIDs,
                      preferredDockID: preferredDockID, backID: backID, topID: topID) ?? target
    }

    /// Where a press leads from a control that has nothing beyond it in
    /// that direction, so that a remote finds no dead key. From the screen:
    /// Left goes to the Back key of the bar, and every other way to the
    /// icon of the screen. Along the bar, past one end comes the other end;
    /// away from the screen comes the top of the screen. Nil when the press
    /// has somewhere to go already.
    public static func beyond(_ current: String?, action: RemoteAction, position: FluxDockPosition,
                              dockIDs: [String], preferredDockID: String?, backID: String?, topID: String?) -> String? {
        guard !dockIDs.isEmpty, [.up, .down, .left, .right].contains(action) else { return nil }
        if let current, let index = dockIDs.firstIndex(of: current) {
            let previous: RemoteAction = position.isVertical ? .up : .left
            let next: RemoteAction = position.isVertical ? .down : .right
            if action == previous { return index == 0 && dockIDs.count > 1 ? dockIDs.last : nil }
            if action == next { return index == dockIDs.count - 1 && dockIDs.count > 1 ? dockIDs.first : nil }
            if action == position.outward { return topID }
            return nil
        }
        if action == .left, action != position.outward, let backID, dockIDs.contains(backID) { return backID }
        return preferred(preferredDockID, in: dockIDs)
    }

    private static func preferred(_ id: String?, in dockIDs: [String]) -> String? {
        id.flatMap { dockIDs.contains($0) ? $0 : nil } ?? dockIDs.first
    }
}

/// Tells a fresh press of an arrow from a key held down and from a press
/// that closely follows another: only a fresh press crosses an edge of the
/// screen or goes round the bar, so that a run of presses stops at the
/// edge, and the next one, after a pause, goes beyond it.
public final class FluxPressCadence {
    /// Seconds without an arrow after which a press is a fresh one.
    public static let pause: Double = 0.4
    private var last = -Double.infinity

    public init() {}

    /// Records a press of an arrow at `time`, in seconds, and tells whether it is fresh.
    public func press(at time: Double, held: Bool = false) -> Bool {
        defer { last = time }
        return !held && time - last >= Self.pause
    }
}
