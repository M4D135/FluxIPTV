import Foundation

/// A screen with a look of its own: the picture behind it and the theme of
/// its dock. What is chosen for all screens holds for those that keep no
/// choice of their own.
public enum FluxSpace: String, CaseIterable, Identifiable, Codable, Sendable {
    case home, live, movie, series, search, settings
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .home: "Accueil"
        case .live: "TV"
        case .movie: "Films"
        case .series: "Séries"
        case .search: "Recherche"
        case .settings: "Réglages"
        }
    }
    public init(kind: IPTVMediaKind) {
        switch kind {
        case .live: self = .live
        case .movie: self = .movie
        case .series: self = .series
        }
    }
    /// The screen in front. `searching`: the screen of the search is open,
    /// from the dock or by typing in a field; moving to a field alone
    /// changes nothing behind it, and a section never shows the pictures
    /// of the search.
    public static func current(home: Bool, settings: Bool, searching: Bool, kind: IPTVMediaKind) -> FluxSpace {
        if home { return .home }
        if settings { return .settings }
        if searching { return .search }
        return FluxSpace(kind: kind)
    }
}

/// Dock themes kept by single screens. The other screens take the theme of
/// all screens, `FluxDockTheme.storageKey`.
public enum FluxDockThemeChoices {
    public static let storageKey = "fluxiptv.dock.theme.spaces.v1"

    /// `home=phosphor,live=gel`: unknown screens and themes are dropped.
    public static func parse(_ stored: String) -> [FluxSpace: FluxDockTheme] {
        var result: [FluxSpace: FluxDockTheme] = [:]
        for pair in stored.split(separator: ",") {
            let parts = pair.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, let space = FluxSpace(rawValue: parts[0]),
                  let theme = FluxDockTheme(rawValue: parts[1]) else { continue }
            result[space] = theme
        }
        return result
    }
    public static func stored(_ choices: [FluxSpace: FluxDockTheme]) -> String {
        FluxSpace.allCases.compactMap { space in choices[space].map { "\(space.rawValue)=\($0.rawValue)" } }
            .joined(separator: ",")
    }
    public static func theme(for space: FluxSpace, all: FluxDockTheme, stored: String) -> FluxDockTheme {
        parse(stored)[space] ?? all
    }
    /// `theme` nil: the screen takes the theme of all screens again.
    public static func setting(_ theme: FluxDockTheme?, for space: FluxSpace, in stored: String) -> String {
        var choices = parse(stored)
        choices[space] = theme
        return Self.stored(choices)
    }
}

/// A picture that may stand behind a screen: one of the app's `Backdrops`
/// folder.
public enum FluxBackdropPicture: Hashable, Sendable, Identifiable {
    case art(String)

    public var id: String {
        switch self { case .art(let name): "art:" + name }
    }
    /// What an earlier version saved for a picture that the app no longer
    /// holds, such as the rooms of the 0.9.2, gives nil.
    public init?(id: String) {
        guard id.hasPrefix("art:") else { return nil }
        let name = String(id.dropFirst(4))
        guard FluxBackdropLibrary.art.contains(where: { $0.name == name }) else { return nil }
        self = .art(name)
    }
    public var title: String {
        switch self { case .art(let name): FluxBackdropLibrary.art.first { $0.name == name }?.title ?? name }
    }
    /// Its file in the bundle: a JPEG of that name in that folder.
    public var resource: (name: String, folder: String) {
        switch self { case .art(let name): (name, "Backdrops") }
    }
}

/// A picture drawn for one of the screens, or for the boutique.
public struct FluxBackdropArt: Equatable, Sendable {
    public let name: String
    public let title: String
    /// The screen that it was drawn for; any screen may show it. Nil for the
    /// boutique, which has no screen of its own yet: its pictures stand
    /// behind the studio of the appearance, its shop window.
    public let space: FluxSpace?
    public init(name: String, title: String, space: FluxSpace?) {
        self.name = name; self.title = title; self.space = space
    }
    /// What it was drawn for, as its collection is named.
    public var section: String { space?.title ?? "Boutique" }
}

public enum FluxBackdropLibrary {
    /// Pictures shipped in `Backdrops/` in 3840 × 2160, and in 1920 × 1080
    /// to the Apple TV, the size it decodes them at (`BackdropsTV`): those
    /// drawn for the screens, and three for the boutique. The entrance hall of the films
    /// and the video store of the series are gone (David, 26/11: a room with
    /// seats and a big screen, and better than a video store).
    public static let art: [FluxBackdropArt] = [
        FluxBackdropArt(name: "tv-1", title: "Salon néon 90", space: .live),
        FluxBackdropArt(name: "tv-2", title: "Loft panoramique", space: .live),
        FluxBackdropArt(name: "tv-3", title: "Régie de diffusion", space: .live),
        FluxBackdropArt(name: "films-1", title: "Grande salle", space: .movie),
        FluxBackdropArt(name: "films-2", title: "Drive-in au crépuscule", space: .movie),
        FluxBackdropArt(name: "series-2", title: "Coin binge-watching", space: .series),
        FluxBackdropArt(name: "series-3", title: "Bibliothèque des séries", space: .series),
        FluxBackdropArt(name: "recherche-1", title: "Observatoire", space: .search),
        FluxBackdropArt(name: "recherche-2", title: "Archives infinies", space: .search),
        FluxBackdropArt(name: "recherche-3", title: "Phare dans la nuit", space: .search),
        FluxBackdropArt(name: "reglages-1", title: "Cabine de projection", space: .settings),
        FluxBackdropArt(name: "reglages-2", title: "Salle des machines", space: .settings),
        FluxBackdropArt(name: "reglages-3", title: "Studio aux boutons", space: .settings),
        FluxBackdropArt(name: "store-1", title: "Boutique néon", space: nil),
        FluxBackdropArt(name: "store-2", title: "Galerie de verre", space: nil),
        FluxBackdropArt(name: "store-3", title: "Comptoir Art déco", space: nil),
    ]
    /// The pictures of the boutique, which no screen shows by itself.
    public static var boutique: [FluxBackdropPicture] {
        art.filter { $0.space == nil }.map { .art($0.name) }
    }
    /// Every picture a screen may show.
    public static var all: [FluxBackdropPicture] { art.map { .art($0.name) } }
    /// The pictures drawn for a screen.
    public static func pictures(for space: FluxSpace) -> [FluxBackdropPicture] {
        art.filter { $0.space == space }.map { .art($0.name) }
    }
    /// The pictures that a screen shows by itself: those drawn for it or,
    /// for the home screen, which has none, those of the screen of what it
    /// holds.
    public static func pictures(for space: FluxSpace, holding kind: IPTVMediaKind) -> [FluxBackdropPicture] {
        let drawn = pictures(for: space)
        return drawn.isEmpty ? pictures(for: FluxSpace(kind: kind)) : drawn
    }
}

public enum FluxSlideInterval: Int, CaseIterable, Codable, Identifiable, Sendable {
    case seconds15 = 15, seconds30 = 30, minute1 = 60, minutes5 = 300, minutes15 = 900
    public var id: Int { rawValue }
    public var title: String {
        switch self {
        case .seconds15: "15 s"
        case .seconds30: "30 s"
        case .minute1: "1 min"
        case .minutes5: "5 min"
        case .minutes15: "15 min"
        }
    }
}

public enum FluxSlideOrder: String, CaseIterable, Codable, Identifiable, Sendable {
    case listed, shuffled
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .listed: "Dans l’ordre"
        case .shuffled: "Au hasard"
        }
    }
}

public enum FluxSlideTransition: String, CaseIterable, Codable, Identifiable, Sendable {
    case fade, cut
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .fade: "Fondu"
        case .cut: "Direct"
        }
    }
}

/// What stands behind a screen: its own pictures, nothing, or chosen
/// pictures one after the other.
public struct FluxBackdropPlan: Equatable, Codable, Sendable {
    public enum Mode: String, CaseIterable, Codable, Sendable {
        /// The pictures drawn for the screen; the home screen shows those of
        /// the screen that its selected icon opens.
        case automatic
        /// No picture: the colour of the screen alone.
        case plain
        /// The pictures chosen, in turn.
        case pictures

        public var title: String {
            switch self {
            case .automatic: "Automatique"
            case .plain: "Aucun"
            case .pictures: "Images choisies"
            }
        }
    }
    public var mode: Mode
    /// Identifiers of the pictures, in the order they are shown.
    public var pictures: [String]
    public var interval: FluxSlideInterval
    public var order: FluxSlideOrder
    public var transition: FluxSlideTransition

    public init(mode: Mode = .automatic, pictures: [String] = [], interval: FluxSlideInterval = .minute1,
                order: FluxSlideOrder = .listed, transition: FluxSlideTransition = .fade) {
        self.mode = mode; self.pictures = pictures; self.interval = interval
        self.order = order; self.transition = transition
    }
    public static let automatic = FluxBackdropPlan()
    /// One picture of the library, always shown.
    public static func picture(_ name: String) -> FluxBackdropPlan {
        FluxBackdropPlan(mode: .pictures, pictures: [FluxBackdropPicture.art(name).id])
    }

    private enum CodingKeys: String, CodingKey { case mode, pictures, interval, order, transition }
    /// A value missing from what an earlier version saved takes its default.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        mode = (try? values.decodeIfPresent(Mode.self, forKey: .mode)) ?? .automatic
        pictures = (try? values.decodeIfPresent([String].self, forKey: .pictures)) ?? []
        interval = (try? values.decodeIfPresent(FluxSlideInterval.self, forKey: .interval)) ?? .minute1
        order = (try? values.decodeIfPresent(FluxSlideOrder.self, forKey: .order)) ?? .listed
        transition = (try? values.decodeIfPresent(FluxSlideTransition.self, forKey: .transition)) ?? .fade
    }

    /// The pictures shown, those the app no longer holds left out. Chosen
    /// pictures that are all gone leave the screen to its own pictures.
    public var shown: [FluxBackdropPicture] {
        mode == .pictures ? pictures.compactMap(FluxBackdropPicture.init(id:)) : []
    }
    public func contains(_ picture: FluxBackdropPicture) -> Bool { pictures.contains(picture.id) }
    /// Adds a picture at the end, or takes it out.
    public mutating func toggle(_ picture: FluxBackdropPicture) {
        if let index = pictures.firstIndex(of: picture.id) { pictures.remove(at: index) } else { pictures.append(picture.id) }
    }
    /// Moves the picture at `index` by `offset` places, within the list.
    public mutating func move(at index: Int, by offset: Int) {
        guard pictures.indices.contains(index) else { return }
        let target = max(0, min(pictures.count - 1, index + offset))
        guard target != index else { return }
        let picture = pictures.remove(at: index)
        pictures.insert(picture, at: target)
    }

    /// Among `count` pictures: the one shown at `time`, in seconds from the
    /// reference date, the one after it, and the time it comes. Every view
    /// of a screen works the same picture out of the clock alone.
    public func slot(at time: TimeInterval, count: Int) -> (current: Int, next: Int, change: TimeInterval) {
        guard count > 1 else { return (0, 0, .infinity) }
        let step = Double(interval.rawValue)
        let turn = Int64((time / step).rounded(.down))
        let change = Double(turn + 1) * step
        return (index(turn, count: count), index(turn + 1, count: count), change)
    }

    private func index(_ turn: Int64, count: Int) -> Int {
        let size = Int64(count)
        let position = Int(((turn % size) + size) % size)
        guard order == .shuffled, count > 2 else { return position }
        let round = turn >= 0 ? turn / size : (turn - size + 1) / size
        return Self.shuffle(round, count: count)[position]
    }

    /// A new order every round, the same on every device. A round never
    /// starts with the picture that ended the one before it.
    static func shuffle(_ round: Int64, count: Int) -> [Int] {
        var order = draw(round, count: count)
        if order.first == draw(round - 1, count: count).last { order.swapAt(0, 1) }
        return order
    }
    private static func draw(_ round: Int64, count: Int) -> [Int] {
        var order = Array(0..<count)
        var state = UInt64(bitPattern: round) &+ 0x9E37_79B9_7F4A_7C15
        func next() -> UInt64 {
            state = state &+ 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
        for i in stride(from: count - 1, to: 0, by: -1) {
            order.swapAt(i, Int(next() % UInt64(i + 1)))
        }
        return order
    }
}

/// The pictures behind the screens: a plan for all of them, and those of
/// the screens that keep one of their own.
public struct FluxBackdropChoices: Equatable, Codable, Sendable {
    public static let storageKey = "fluxiptv.appearance.backdrops.v1"
    public var all: FluxBackdropPlan
    /// By `FluxSpace.rawValue`.
    public var own: [String: FluxBackdropPlan]

    public init(all: FluxBackdropPlan = .automatic, own: [String: FluxBackdropPlan] = [:]) {
        self.all = all; self.own = own
    }
    private enum CodingKeys: String, CodingKey { case all, own }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        all = (try? values.decodeIfPresent(FluxBackdropPlan.self, forKey: .all)) ?? .automatic
        let saved = (try? values.decodeIfPresent([String: FluxBackdropPlan].self, forKey: .own)) ?? [:]
        // A screen that a later version adds, and this one lacks, is left out.
        own = saved.filter { FluxSpace(rawValue: $0.key) != nil }
    }
    /// What is saved, or the pictures of a new install when nothing is.
    public init(stored: String) {
        if let data = stored.data(using: .utf8), !data.isEmpty,
           let value = try? JSONDecoder().decode(Self.self, from: data) {
            self = value
        } else {
            self = .defaults
        }
    }
    /// What is saved, decoded once for each text kept. The pictures behind
    /// each screen, and the home screen, read the choices at each evaluation:
    /// on the home screen up to seven times a press, and a decoding took
    /// 14 µs on a Mac (bench of the 0.9.10).
    @MainActor public static func reading(_ stored: String) -> FluxBackdropChoices {
        if let last = lastRead, last.stored == stored { return last.choices }
        let choices = FluxBackdropChoices(stored: stored)
        lastRead = (stored, choices)
        return choices
    }
    @MainActor private static var lastRead: (stored: String, choices: FluxBackdropChoices)?
    /// The pictures of a new install: those David chose on his Apple TV,
    /// one for each screen ("garde mes preset d'images de fond pour le par
    /// defaut", 27/11). All the screens together stay on their own pictures.
    public static let defaults = FluxBackdropChoices(own: [
        FluxSpace.home.rawValue: .picture("recherche-2"),
        FluxSpace.live.rawValue: .picture("tv-1"),
        FluxSpace.movie.rawValue: .picture("films-1"),
        FluxSpace.series.rawValue: .picture("series-2"),
        FluxSpace.search.rawValue: .picture("recherche-1"),
        FluxSpace.settings.rawValue: .picture("reglages-3"),
    ])
    public var stored: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return (try? encoder.encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }
    public func plan(for space: FluxSpace?) -> FluxBackdropPlan {
        guard let space else { return all }
        return own[space.rawValue] ?? all
    }
    public func keepsOwn(_ space: FluxSpace) -> Bool { own[space.rawValue] != nil }
    public var anyOwn: Bool { !own.isEmpty }
    /// `space` nil: the plan of all screens; those that keep their own keep it.
    public mutating func set(_ plan: FluxBackdropPlan, for space: FluxSpace?) {
        if let space { own[space.rawValue] = plan } else { all = plan }
    }
    /// The screen shows the plan of all screens again.
    public mutating func follow(_ space: FluxSpace) { own[space.rawValue] = nil }
    /// Every screen shows the plan of all screens.
    public mutating func sameEverywhere() { own = [:] }
}

/// Three sets of the graphic settings, from the lightest to the richest.
public enum FluxQualityPreset: String, CaseIterable, Identifiable, Sendable {
    case fluid, balanced, quality
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .fluid: "Fluide"
        case .balanced: "Équilibré"
        case .quality: "Qualité"
        }
    }
    public var subtitle: String {
        switch self {
        case .fluid: "Ni verre, ni mouvement, ni fond, ni aperçu : le plus léger, pour une Apple TV HD."
        case .balanced: "Verre, fonds et aperçus, sans les mouvements de la sélection ni le reflet du panneau."
        case .quality: "Tout : verre, mouvements, reflet du panneau, fonds et aperçus."
        }
    }
    /// Whether the app chooses the preset by the machine it runs on. The
    /// 0.9.4 starts so; picking a preset or changing one of its settings
    /// stops it.
    public static let automaticKey = "fluxiptv.quality.automatic.v1"
    public var symbol: String {
        switch self {
        case .fluid: "hare.fill"
        case .balanced: "dial.medium.fill"
        case .quality: "sparkles"
        }
    }
    public var glass: Bool { self != .fluid }
    public var motion: Bool { self == .quality }
    public var backdrops: Bool { self != .fluid }
    public var livePreview: Bool { self != .fluid }
    /// The part of the screen that holds the remote: a still edge costs
    /// nothing; the glint that crosses it is a motion.
    public var glint: FluxPanelGlint { self == .quality ? .glint : .edge }

    /// The preset that these settings are, if they are one.
    public static func matching(glass: Bool, motion: Bool, backdrops: Bool, livePreview: Bool,
                                glint: FluxPanelGlint) -> FluxQualityPreset? {
        allCases.first {
            $0.glass == glass && $0.motion == motion && $0.backdrops == backdrops && $0.livePreview == livePreview
                && $0.glint == glint
        }
    }
}
