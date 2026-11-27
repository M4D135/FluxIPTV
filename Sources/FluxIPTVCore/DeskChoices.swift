import Foundation

/// What Back does inside a screen. "touche retour sors de la grille film
/// séries etc vers contrôles bouton précédent ce qui permet d'aller sur
/// dock ou autre éléments" (David, 26/11): out of a long grid first, onto
/// the bar, where Back, the home screen and the dock stand side by side;
/// Back again leaves the screen.
public enum DeskBackBehavior: String, CaseIterable, Identifiable, Sendable {
    /// Back first hands the remote to the bar, on its Back button.
    case bar
    /// Back leaves the screen at once, as up to the 0.9.3.
    case leave
    /// Back first shows the plan of the screen (keyboard of a Mac).
    case plan

    public static let storageKey = "fluxiptv.desk.back.v2"
    public static let defaultValue: Self = .bar
    public var id: String { rawValue }

    /// What a television and a Mac offer: the plan is drawn for the keys.
    public static var offered: [Self] {
        #if os(macOS)
        allCases
        #else
        [.bar, .leave]
        #endif
    }

    public var title: String {
        switch self {
        case .bar: "Remonter à la barre"
        case .leave: "Quitter l’écran"
        case .plan: "Montrer le plan"
        }
    }

    /// The setting saved by the 0.9.3 and before, which said only whether
    /// Back showed the plan, becomes this one.
    public static func migrate(_ defaults: UserDefaults = .standard) {
        guard defaults.object(forKey: storageKey) == nil,
              defaults.object(forKey: DeskZone.backKey) != nil else { return }
        if defaults.bool(forKey: DeskZone.backKey) { defaults.set(Self.plan.rawValue, forKey: storageKey) }
        defaults.removeObject(forKey: DeskZone.backKey)
    }
}

/// How much the icon under the remote or the pointer grows in the dock.
/// "quand on va sur icone doit zoomer plus que ça par rapport a taille
/// normale, donne le choix dans options plusieurs taille a la selection"
/// (David, 26/11).
public enum FluxDockZoom: String, CaseIterable, Identifiable, Sendable {
    case none, light, normal, strong, maximum

    public static let storageKey = "fluxiptv.dock.zoom.v1"
    public static let defaultValue: Self = .normal
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .none: "Aucune"
        case .light: "Légère"
        case .normal: "Normale"
        case .strong: "Forte"
        case .maximum: "Maximale"
        }
    }

    /// The growth of the icon at the centre of the loupe, as a share of the
    /// growth of the 0.9.3, whose loupe is now « Légère ».
    public var factor: Double {
        switch self {
        case .none: 0
        case .light: 1
        case .normal: 1.55
        case .strong: 2.1
        case .maximum: 2.7
        }
    }

    /// `base`: the largest scale of the 0.9.3 for that form of the bar.
    public func maximumScale(base: Double) -> Double { 1 + max(0, base - 1) * factor }

    /// The 0.9.3 kept only whether the loupe was on.
    public static func migrate(_ defaults: UserDefaults = .standard) {
        guard defaults.object(forKey: storageKey) == nil,
              defaults.object(forKey: FluxDockItem.magnifyKey) != nil else { return }
        if !defaults.bool(forKey: FluxDockItem.magnifyKey) { defaults.set(Self.none.rawValue, forKey: storageKey) }
        defaults.removeObject(forKey: FluxDockItem.magnifyKey)
    }
}

/// How the dock shows the icon under the remote.
public enum FluxDockSelectionLook: String, CaseIterable, Identifiable, Sendable {
    /// A white ring, as tvOS draws its focus.
    case ring
    /// A halo of the colour of the icon.
    case halo
    /// The icon rises over a shadow, without a ring.
    case lift

    public static let storageKey = "fluxiptv.dock.selectionLook.v1"
    public static let defaultValue: Self = .ring
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .ring: "Contour"
        case .halo: "Halo"
        case .lift: "Soulevé"
        }
    }
}

/// How the part of the screen that holds the remote shows it: a list, its
/// column, the line of the search, the bar. "un léger effet mouvement widget
/// Apple TV sur le panel pour montrer dans quelle zone on est" (David, 26/11).
public enum FluxPanelGlint: String, CaseIterable, Identifiable, Sendable {
    case off
    /// A light edge.
    case edge
    /// The light edge, and a glint that crosses the part entered.
    case glint

    public static let storageKey = "fluxiptv.desk.panelGlint.v1"
    /// Before anything is saved, as the glass and the motion: all of it.
    public static let defaultValue: Self = .glint
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .off: "Aucun"
        case .edge: "Liseré"
        case .glint: "Liseré et reflet"
        }
    }
}
