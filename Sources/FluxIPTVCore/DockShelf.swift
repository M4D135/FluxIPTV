import Foundation

/// A shortcut of the bar: a channel, a film, a series, one of its seasons or
/// one of its episodes, kept there as an application is kept in the Dock of a
/// Mac. Only opaque catalogue identifiers and the name to show are stored:
/// never an address, never a credential.
public struct DockShortcut: Identifiable, Codable, Hashable, Sendable {
    public enum Target: String, Codable, Sendable { case channel, film, series, season, episode }

    /// Unique in the bar: the identifier of the channel, film, series or
    /// episode, or the series and the number of the season.
    public let id: String
    public let target: Target
    public let sourceID: UUID
    /// Channel, film or series of the catalogue. A season and an episode are
    /// reached through their series.
    public let itemID: String
    public let season: Int?
    public let episode: Int?
    public let episodeID: String?
    /// The channel, the film or the series: what stands under the icon.
    public var name: String
    /// The whole name, with the season or the episode.
    public var title: String

    /// A channel, a film or a series, as the catalogue lists them.
    public init(item: IPTVItem) {
        id = item.id
        target = item.kind == .live ? .channel : item.kind == .movie ? .film : .series
        sourceID = item.sourceID
        itemID = item.id
        season = nil
        episode = nil
        episodeID = nil
        name = item.name
        title = item.name
    }

    public init(series: IPTVItem, season number: Int) {
        id = "\(series.id)#s\(number)"
        target = .season
        sourceID = series.sourceID
        itemID = series.id
        season = number
        episode = nil
        episodeID = nil
        name = series.name
        title = "\(series.name) · Saison \(number)"
    }

    public init(series: IPTVItem, episode item: IPTVItem) {
        id = item.id
        target = .episode
        sourceID = series.sourceID
        itemID = series.id
        season = item.seasonNumber
        episode = item.episodeNumber
        episodeID = item.id
        name = series.name
        let place = [item.seasonNumber.map { "S\($0)" }, item.episodeNumber.map { "E\($0)" }].compactMap { $0 }.joined(separator: " ")
        title = place.isEmpty ? "\(series.name) · \(item.name)" : "\(series.name) · \(place)"
    }

    /// What tells a season or an episode from its series, on its icon.
    public var badge: String? {
        switch target {
        case .channel, .film, .series: nil
        case .season: season.map { "S\($0)" }
        case .episode:
            switch (season, episode) {
            case (let s?, let e?): "S\(s)·E\(e)"
            case (nil, let e?): "E\(e)"
            case (let s?, nil): "S\(s)"
            case (nil, nil): "ÉP."
            }
        }
    }

    public var kind: IPTVMediaKind {
        switch target {
        case .channel: .live
        case .film: .movie
        case .series, .season, .episode: .series
        }
    }
    /// What the viewing history knows this shortcut by: a film or an episode.
    public var playedID: String? {
        switch target {
        case .film: itemID
        case .episode: episodeID
        case .channel, .series, .season: nil
        }
    }
}

/// A named group of shortcuts. A section stands apart in the bar, between
/// two dividers, as the parts of the Dock of a Mac do. A folder is one icon
/// of the bar instead, which opens as a fan; it may hold other folders, as
/// far as one cares to sort.
public struct DockSection: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public var name: String
    public var shortcuts: [DockShortcut]
    public let isDefault: Bool
    /// One icon of the bar, opened as a fan, instead of its shortcuts side
    /// by side in the bar.
    public var folded: Bool
    /// The folder that holds this one; nil in the bar itself.
    public var parentID: String?
    /// The icon chosen for the folder; nil shows the pictures of what it holds.
    public var symbol: String?

    public init(id: String, name: String, shortcuts: [DockShortcut] = [], isDefault: Bool = false,
                folded: Bool = false, parentID: String? = nil, symbol: String? = nil) {
        self.id = id
        self.name = name
        self.shortcuts = shortcuts
        self.isDefault = isDefault
        self.folded = folded
        self.parentID = parentID
        self.symbol = symbol
    }

    /// What was kept before folders existed has none of their keys.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        shortcuts = try values.decode([DockShortcut].self, forKey: .shortcuts)
        isDefault = try values.decode(Bool.self, forKey: .isDefault)
        folded = try values.decodeIfPresent(Bool.self, forKey: .folded) ?? false
        parentID = try values.decodeIfPresent(String.self, forKey: .parentID)
        symbol = try values.decodeIfPresent(String.self, forKey: .symbol)
    }

    /// A folder: of the bar, or of another folder.
    public var isFolder: Bool { folded || parentID != nil }

    /// Icons a folder may be given, by the name the system knows them by.
    public static let symbols = ["folder.fill", "star.fill", "heart.fill", "film.fill", "tv.fill", "popcorn.fill",
                                 "theatermasks.fill", "sparkles", "flame.fill", "bolt.fill", "moon.stars.fill", "sun.max.fill",
                                 "face.smiling.fill", "figure.and.child.holdinghands", "gamecontroller.fill", "music.note",
                                 "sportscourt.fill", "trophy.fill", "globe.europe.africa.fill", "newspaper.fill",
                                 "leaf.fill", "pawprint.fill", "car.fill", "airplane", "book.fill", "crown.fill"]
    /// What each of them is called where one chooses.
    public static func symbolTitle(_ symbol: String) -> String {
        switch symbol {
        case "folder.fill": "Dossier"
        case "star.fill": "Étoile"
        case "heart.fill": "Cœur"
        case "film.fill": "Film"
        case "tv.fill": "Télévision"
        case "popcorn.fill": "Pop-corn"
        case "theatermasks.fill": "Théâtre"
        case "sparkles": "Étincelles"
        case "flame.fill": "Flamme"
        case "bolt.fill": "Éclair"
        case "moon.stars.fill": "Nuit"
        case "sun.max.fill": "Soleil"
        case "face.smiling.fill": "Sourire"
        case "figure.and.child.holdinghands": "Enfants"
        case "gamecontroller.fill": "Jeux"
        case "music.note": "Musique"
        case "sportscourt.fill": "Sport"
        case "trophy.fill": "Trophée"
        case "globe.europe.africa.fill": "Monde"
        case "newspaper.fill": "Actualités"
        case "leaf.fill": "Nature"
        case "pawprint.fill": "Animaux"
        case "car.fill": "Voitures"
        case "airplane": "Voyages"
        case "book.fill": "Livres"
        case "crown.fill": "Couronne"
        default: symbol
        }
    }
}

/// One thing shown in the bar, and the identifier that the focus knows it by.
public enum DockEntry: Identifiable, Hashable, Sendable {
    case destination(FluxDockItem)
    case shortcut(DockShortcut, section: String)
    /// The film or the episode that was left unfinished.
    case resume(DockShortcut)
    case recent(DockShortcut)
    /// A list of favourites kept in the bar as a folder.
    case stack(listID: String)
    /// A folder of shortcuts, made in the bar itself.
    case folder(sectionID: String)
    /// The shortcuts that the bar has no room for, as one more folder.
    case more

    public static let shortcutPrefix = "dock-item-"
    public static let resumePrefix = "dock-resume-"
    public static let recentPrefix = "dock-recent-"
    public static let stackPrefix = "dock-stack-"
    public static let folderPrefix = "dock-folder-"
    public static let moreID = "dock-more"
    /// A title of an open folder, above the bar.
    public static let fanPrefix = "dock-fan-"
    /// A folder kept inside the open one: OK shows what it holds.
    public static let fanFolderPrefix = "dock-fan-folder:"
    /// First row of a folder opened from another, or of a later page: back.
    public static let fanUpID = "dock-fan-up"
    /// Last row of an open folder: the whole list on its own screen, the
    /// titles that follow, or where the folder is managed.
    public static let fanAllID = "dock-fan-all"

    /// Whether a control belongs to the bar or to its open folder.
    public static func isShelfID(_ id: String) -> Bool {
        id == moreID || [shortcutPrefix, resumePrefix, recentPrefix, stackPrefix, folderPrefix, fanPrefix].contains(where: id.hasPrefix)
    }

    public var id: String {
        switch self {
        case .destination(let item): item.focusID
        case .shortcut(let shortcut, let section): "\(Self.shortcutPrefix)\(section)-\(shortcut.id)"
        case .resume(let shortcut): Self.resumePrefix + shortcut.id
        case .recent(let shortcut): Self.recentPrefix + shortcut.id
        case .stack(let listID): Self.stackPrefix + listID
        case .folder(let sectionID): Self.folderPrefix + sectionID
        case .more: Self.moreID
        }
    }
    public var shortcut: DockShortcut? {
        switch self {
        case .shortcut(let shortcut, _), .resume(let shortcut), .recent(let shortcut): shortcut
        case .destination, .stack, .folder, .more: nil
        }
    }
    /// A folder opens above the bar instead of leaving the screen.
    public var isFolder: Bool {
        switch self {
        case .stack, .folder, .more: true
        case .destination, .shortcut, .resume, .recent: false
        }
    }
}

/// The bar as it is drawn: groups that a divider separates.
public struct DockArrangement: Equatable, Sendable {
    public let groups: [[DockEntry]]
    /// Shortcuts that the bar has no room for: the `more` folder opens them.
    public let hidden: [DockEntry]
    public init(groups: [[DockEntry]], hidden: [DockEntry] = []) {
        self.groups = groups.filter { !$0.isEmpty }
        self.hidden = hidden
    }
    public var entries: [DockEntry] { groups.flatMap { $0 } }
    /// Index of the first entry of each group but the first: a divider
    /// stands before it.
    public var breaks: [Int] {
        var result: [Int] = [], count = 0
        for group in groups.dropLast() { count += group.count; result.append(count) }
        return result
    }
    public func entry(id: String) -> DockEntry? { entries.first { $0.id == id } }

    /// The same bar with at most `limit` entries, so that no icon has to
    /// shrink below what a television shows well. The recents leave first,
    /// the oldest first. Then the shortcuts added last go into one more
    /// folder, at the end of the shortcuts: nothing that was kept is lost.
    /// The destinations, what is in progress and the folders always stay.
    /// `sparingRecents`: on the home screen the recents have a row of
    /// their own to stand on, and only the shortcuts are too many.
    public func fitted(to limit: Int, sparingRecents: Bool = false) -> DockArrangement {
        var groups = groups
        var hidden = hidden
        func total() -> Int { groups.reduce(0) { $0 + $1.count } }
        func isRecent(_ entry: DockEntry) -> Bool { if case .recent = entry { return true } else { return false } }
        func isShortcut(_ entry: DockEntry) -> Bool { if case .shortcut = entry { return true } else { return false } }
        func lastGroup(_ test: (DockEntry) -> Bool) -> Int? { groups.lastIndex { $0.contains(where: test) } }
        while !sparingRecents, total() > limit, let g = lastGroup(isRecent), let i = groups[g].lastIndex(where: isRecent) {
            groups[g].remove(at: i)
        }
        let folded = groups.contains { $0.contains(.more) }
        guard total() > limit, lastGroup(isShortcut) != nil else { return DockArrangement(groups: groups, hidden: hidden) }
        // The folder takes the place of one shortcut more.
        let room = folded ? 0 : 1
        var anchor = lastGroup(isShortcut) ?? 0
        while total() + room > limit, let g = lastGroup(isShortcut), let i = groups[g].lastIndex(where: isShortcut) {
            hidden.insert(groups[g].remove(at: i), at: 0)
            anchor = g
        }
        if !folded {
            // After the last shortcut still shown, or where they stood.
            if let g = lastGroup(isShortcut) { groups[g].append(.more) } else { groups[anchor].append(.more) }
        }
        return DockArrangement(groups: groups, hidden: hidden)
    }
}

extension DockArrangement {
    /// What a group of the bar holds: its destinations, shortcuts, or what
    /// is in progress and the folders.
    private enum Part { case places, shortcuts, rest }
    private static func part(_ group: [DockEntry]) -> Part {
        switch group.first {
        case .destination: .places
        case .shortcut, .more: .shortcuts
        default: .rest
        }
    }
    /// How many shortcuts the bar shows, the folder of the others included.
    public var shortcutCount: Int { groups.filter { Self.part($0) == .shortcuts }.reduce(0) { $0 + $1.count } }
    /// What is in progress, the recents and the folders.
    public var restCount: Int { groups.filter { Self.part($0) == .rest }.reduce(0) { $0 + $1.count } }

    /// The bar of the home screen in one to three rows, so that its icons
    /// keep their size as it fills: one row while everything holds on it;
    /// then the destinations above all that the user keeps; then three
    /// rows, the destinations, the shortcuts, and what is in progress with
    /// the folders. `limit` is what one row holds.
    public func rows(limit: Int) -> [DockArrangement] {
        guard limit > 0, entries.count > limit else { return [self] }
        let places = groups.filter { Self.part($0) == .places }
        let kept = groups.filter { Self.part($0) != .places }
        guard !places.isEmpty, !kept.isEmpty else { return [self] }
        if kept.reduce(0, { $0 + $1.count }) <= limit {
            return [DockArrangement(groups: places), DockArrangement(groups: kept, hidden: hidden)]
        }
        let shortcuts = kept.filter { Self.part($0) == .shortcuts }
        let rest = kept.filter { Self.part($0) == .rest }
        return [DockArrangement(groups: places), DockArrangement(groups: shortcuts, hidden: hidden), DockArrangement(groups: rest)]
            .filter { !$0.entries.isEmpty }
    }

    /// A move of the keyboard among rows that are centred one above the
    /// other: along a row to its ends, and up or down to the icon that
    /// stands nearest above or below.
    public static func move(from current: String, action: RemoteAction, rows: [[String]]) -> String {
        guard let r = rows.firstIndex(where: { $0.contains(current) }), let i = rows[r].firstIndex(of: current) else {
            return rows.first?.first ?? current
        }
        switch action {
        case .left: return rows[r][max(0, i - 1)]
        case .right: return rows[r][min(rows[r].count - 1, i + 1)]
        case .up, .down:
            let target = r + (action == .up ? -1 : 1)
            guard rows.indices.contains(target), !rows[target].isEmpty else { return current }
            // Each icon by its distance from the middle of its row.
            let place = Double(i) - Double(rows[r].count - 1) / 2
            let middle = Double(rows[target].count - 1) / 2
            let nearest = rows[target].indices.min { abs(Double($0) - middle - place) < abs(Double($1) - middle - place) } ?? 0
            return rows[target][nearest]
        default: return current
        }
    }
}

/// What the user keeps in the bar besides its destinations: shortcuts in
/// named sections, lists of favourites as folders, and what was watched last.
public struct DockShelf: Codable, Equatable, Sendable {
    public static let storageKey = "fluxiptv.dock.shelf.v1"
    /// Whether the bar shows the video in progress and the recents.
    public static let recentsKey = "fluxiptv.dock.recents.v1"
    public static let defaultSectionID = "shortcuts"
    public static let recentLimit = 12

    public private(set) var sections: [DockSection]
    /// Lists of favourites shown as folders, in the order they were added.
    public private(set) var stacks: [String]
    /// What was opened last, the most recent first.
    public private(set) var recents: [DockShortcut]

    /// Folders inside folders, as far as this; the bar is not a disk.
    public static let folderDepth = 4

    public init() {
        sections = [DockSection(id: Self.defaultSectionID, name: "Raccourcis", shortcuts: [], isDefault: true)]
        stacks = []
        recents = []
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        sections = try values.decode([DockSection].self, forKey: .sections)
        stacks = try values.decodeIfPresent([String].self, forKey: .stacks) ?? []
        recents = try values.decodeIfPresent([DockShortcut].self, forKey: .recents) ?? []
        repair()
    }

    /// What was read is made whole again: the first section is in the
    /// bar, and a folder whose own folder is gone, or that would hold
    /// itself, returns to the bar.
    private mutating func repair() {
        if !sections.contains(where: \.isDefault) {
            sections.insert(DockSection(id: Self.defaultSectionID, name: "Raccourcis", isDefault: true), at: 0)
        }
        for index in sections.indices {
            if sections[index].isDefault { sections[index].folded = false; sections[index].parentID = nil; continue }
            guard let parent = sections[index].parentID else { continue }
            // Up from its folder to the bar without meeting itself, and within the depth allowed.
            var seen: Set<String> = [sections[index].id], cursor: String? = parent, sound = true, steps = 0
            while let id = cursor {
                guard seen.insert(id).inserted, let above = section(id: id), !above.isDefault, steps < Self.folderDepth else { sound = false; break }
                cursor = above.parentID; steps += 1
            }
            if !sound { sections[index].parentID = nil; sections[index].folded = true }
        }
    }

    public func section(id: String) -> DockSection? { sections.first { $0.id == id } }
    /// Sections that hold this shortcut.
    public func sections(holding shortcutID: String) -> Set<String> {
        Set(sections.filter { $0.shortcuts.contains { $0.id == shortcutID } }.map(\.id))
    }
    public func contains(_ shortcutID: String) -> Bool { !sections(holding: shortcutID).isEmpty }

    // MARK: Sections

    /// A section of the bar, or with `folded` a folder: in the bar, or in
    /// the folder `parentID`.
    @discardableResult public mutating func createSection(name: String, folded: Bool = false, in parentID: String? = nil,
                                                          symbol: String? = nil) -> String? {
        if let parentID {
            guard let parent = section(id: parentID), parent.isFolder, depth(of: parentID) + 1 < Self.folderDepth else { return nil }
        }
        guard let clean = availableName(name, except: nil, in: parentID) else { return nil }
        let id = UUID().uuidString
        sections.append(DockSection(id: id, name: clean, folded: folded || parentID != nil, parentID: parentID, symbol: symbol))
        return id
    }

    @discardableResult public mutating func renameSection(id: String, name: String) -> Bool {
        guard let index = sections.firstIndex(where: { $0.id == id }),
              let clean = availableName(name, except: id, in: sections[index].parentID) else { return false }
        sections[index].name = clean
        return true
    }

    /// The first section always stays; another one leaves with its
    /// shortcuts, and a folder with the folders it holds.
    @discardableResult public mutating func deleteSection(id: String) -> Bool {
        guard sections.contains(where: { $0.id == id && !$0.isDefault }) else { return false }
        let gone = Set([id] + descendants(of: id).map(\.id))
        sections.removeAll { gone.contains($0.id) }
        return true
    }

    // MARK: Folders of shortcuts

    /// The folders that stand in the bar, in the order they were made.
    public var topFolders: [DockSection] { sections.filter { $0.folded && $0.parentID == nil } }
    /// The sections whose shortcuts stand in the bar, side by side.
    public var openSections: [DockSection] { sections.filter { !$0.isFolder } }
    /// The folders that a folder holds.
    public func folders(in parentID: String) -> [DockSection] { sections.filter { $0.parentID == parentID } }
    /// Every folder under this one, at any depth.
    public func descendants(of id: String) -> [DockSection] {
        var result: [DockSection] = [], pending = [id], seen: Set<String> = [id]
        while let next = pending.popLast() {
            for child in folders(in: next) where seen.insert(child.id).inserted { result.append(child); pending.append(child.id) }
        }
        return result
    }
    /// How many folders stand above this one: none for a folder of the bar.
    public func depth(of id: String) -> Int {
        var depth = 0, cursor = section(id: id)?.parentID, seen: Set<String> = [id]
        while let above = cursor, seen.insert(above).inserted { depth += 1; cursor = section(id: above)?.parentID }
        return depth
    }
    /// The folders from the bar down to this one, itself last.
    public func path(to id: String) -> [DockSection] {
        var result: [DockSection] = [], cursor = section(id: id), seen = Set<String>()
        while let current = cursor, seen.insert(current.id).inserted {
            result.insert(current, at: 0)
            cursor = current.parentID.flatMap { section(id: $0) }
        }
        return result
    }
    /// Everything of the bar as a list one can read down: its sections,
    /// then each folder followed by the folders it holds, with its depth.
    public var tree: [(section: DockSection, depth: Int)] {
        var result = openSections.map { (section: $0, depth: 0) }
        func add(_ folder: DockSection, _ depth: Int) {
            result.append((folder, depth))
            for child in folders(in: folder.id) { add(child, depth + 1) }
        }
        for folder in topFolders { add(folder, 0) }
        return result
    }
    /// What an open folder shows for one source: the folders it holds,
    /// then its own shortcuts.
    public func content(of id: String, sourceID: UUID?) -> (folders: [DockSection], shortcuts: [DockShortcut]) {
        (folders(in: id), section(id: id)?.shortcuts.filter { $0.sourceID == sourceID } ?? [])
    }
    /// The shortcuts of a folder and of all those under it, for one
    /// source, each once: what its icon counts and shows.
    public func titles(under id: String, sourceID: UUID?) -> [DockShortcut] {
        var seen = Set<String>(), result: [DockShortcut] = []
        for part in [section(id: id)].compactMap({ $0 }) + descendants(of: id) {
            for shortcut in part.shortcuts where shortcut.sourceID == sourceID && seen.insert(shortcut.id).inserted { result.append(shortcut) }
        }
        return result
    }

    /// Shows a section as one folder of the bar, or its shortcuts in the
    /// bar again. The folders it held then stand in the bar themselves.
    @discardableResult public mutating func setFolded(_ id: String, _ folded: Bool) -> Bool {
        guard let index = sections.firstIndex(where: { $0.id == id && !$0.isDefault }), sections[index].parentID == nil else { return false }
        guard availableName(sections[index].name, except: id, in: nil) != nil else { return false }
        sections[index].folded = folded
        if !folded {
            for child in sections.indices where sections[child].parentID == id { sections[child].parentID = nil }
        }
        return true
    }

    /// Puts a folder into another, or back into the bar. Never into itself
    /// nor into one of its own, never deeper than `folderDepth`, and never
    /// beside a folder of the same name. A section moved into a folder
    /// becomes one.
    @discardableResult public mutating func moveSection(_ id: String, into parentID: String?) -> Bool {
        guard let index = sections.firstIndex(where: { $0.id == id && !$0.isDefault }) else { return false }
        if let parentID {
            guard parentID != id, let parent = section(id: parentID), parent.isFolder,
                  !descendants(of: id).contains(where: { $0.id == parentID }) else { return false }
            let below = descendants(of: id).map { depth(of: $0.id) - depth(of: id) }.max() ?? 0
            guard depth(of: parentID) + 1 + below < Self.folderDepth else { return false }
        }
        guard availableName(sections[index].name, except: id, in: parentID) != nil else { return false }
        sections[index].parentID = parentID
        sections[index].folded = true
        return true
    }

    /// The icon of a folder; nil shows the pictures of what it holds.
    @discardableResult public mutating func setSymbol(_ id: String, _ symbol: String?) -> Bool {
        guard let index = sections.firstIndex(where: { $0.id == id }), symbol == nil || DockSection.symbols.contains(symbol!) else { return false }
        sections[index].symbol = symbol
        return true
    }

    // MARK: Shortcuts

    /// The whole choice of the user for one shortcut, committed at once: the
    /// sections that keep it, and a new one to create for it. An invalid name
    /// or a section that no longer exists changes nothing.
    @discardableResult public mutating func assign(_ shortcut: DockShortcut, to sectionIDs: Set<String>,
                                                   creating name: String? = nil, folded: Bool = false,
                                                   in parentID: String? = nil) -> Bool {
        guard sectionIDs.isSubset(of: Set(sections.map(\.id))) else { return false }
        var draft = self
        var chosen = sectionIDs
        if let name {
            guard let id = draft.createSection(name: name, folded: folded, in: parentID) else { return false }
            chosen.insert(id)
        }
        for index in draft.sections.indices {
            let held = draft.sections[index].shortcuts.firstIndex { $0.id == shortcut.id }
            if chosen.contains(draft.sections[index].id) {
                if let held {
                    // The catalogue may have renamed it since.
                    draft.sections[index].shortcuts[held].title = shortcut.title
                    draft.sections[index].shortcuts[held].name = shortcut.name
                }
                else { draft.sections[index].shortcuts.append(shortcut) }
            } else if let held {
                draft.sections[index].shortcuts.remove(at: held)
            }
        }
        self = draft
        return true
    }

    public mutating func remove(shortcutID: String) {
        for index in sections.indices { sections[index].shortcuts.removeAll { $0.id == shortcutID } }
    }

    /// Places a shortcut at `index` of its section; an index outside the
    /// section is clamped to its ends.
    @discardableResult public mutating func move(shortcutID: String, in sectionID: String, to index: Int) -> Bool {
        guard let s = sections.firstIndex(where: { $0.id == sectionID }),
              let from = sections[s].shortcuts.firstIndex(where: { $0.id == shortcutID }) else { return false }
        let shortcut = sections[s].shortcuts.remove(at: from)
        sections[s].shortcuts.insert(shortcut, at: max(0, min(sections[s].shortcuts.count, index)))
        return true
    }

    // MARK: Folders

    public func showsStack(_ listID: String) -> Bool { stacks.contains(listID) }
    public mutating func setStack(_ listID: String, shown: Bool) {
        if shown { if !stacks.contains(listID) { stacks.append(listID) } }
        else { stacks.removeAll { $0 == listID } }
    }
    /// A list that was deleted leaves the bar.
    @discardableResult public mutating func retainStacks(_ valid: Set<String>) -> Bool {
        let kept = stacks.filter(valid.contains)
        guard kept != stacks else { return false }
        stacks = kept
        return true
    }

    // MARK: Recents

    /// What has just been opened comes first; the list is bounded.
    public mutating func visit(_ shortcut: DockShortcut) {
        recents.removeAll { $0.id == shortcut.id }
        recents.insert(shortcut, at: 0)
        if recents.count > Self.recentLimit { recents.removeLast(recents.count - Self.recentLimit) }
    }
    public mutating func forget(recentID: String) { recents.removeAll { $0.id == recentID } }

    /// Nothing of a source that was removed stays in the bar.
    @discardableResult public mutating func removeSource(_ sourceID: UUID) -> Bool {
        let before = self
        for index in sections.indices { sections[index].shortcuts.removeAll { $0.sourceID == sourceID } }
        recents.removeAll { $0.sourceID == sourceID }
        return before != self
    }

    // MARK: The bar

    /// The film or the episode watched last, among the recents, that
    /// `resumable` says was left unfinished.
    public func unfinished(sourceID: UUID?, resumable: (String) -> Bool) -> DockShortcut? {
        recents.first { $0.sourceID == sourceID && ($0.playedID.map(resumable) ?? false) }
    }
    /// The recent that the viewing history knows by this identifier.
    public func recent(played id: String, sourceID: UUID?) -> DockShortcut? {
        recents.first { $0.sourceID == sourceID && $0.playedID == id }
    }

    /// What the bar shows for one source: its destinations, each section of
    /// shortcuts, what is in progress with the recents, then the folders.
    /// `resume` is the film or the episode that was left unfinished. A
    /// shortcut is not repeated among the recents.
    public func arrangement(destinations: [FluxDockItem], sourceID: UUID?, lists: [String],
                            recentCount: Int = 3, resume: DockShortcut?) -> DockArrangement {
        func mine(_ shortcut: DockShortcut) -> Bool { shortcut.sourceID == sourceID }
        var groups: [[DockEntry]] = [destinations.map(DockEntry.destination)]
        // What stands in the bar itself is not repeated among the recents;
        // what a folder holds may be.
        var pinned = Set<String>()
        for section in openSections {
            let shown = section.shortcuts.filter(mine)
            shown.forEach { pinned.insert($0.id) }
            groups.append(shown.map { DockEntry.shortcut($0, section: section.id) })
        }
        let history = recents.filter(mine)
        let resume = resume.flatMap { mine($0) ? $0 : nil }
        var activity: [DockEntry] = resume.map { [.resume($0)] } ?? []
        let others = history.filter { $0.id != resume?.id && !pinned.contains($0.id) }
        activity += others.prefix(max(0, recentCount)).map(DockEntry.recent)
        groups.append(activity)
        // The folders stand together at the end of the bar, as in the Dock
        // of a Mac: those of shortcuts, then the lists of favourites.
        groups.append(topFolders.map { DockEntry.folder(sectionID: $0.id) }
                      + stacks.filter(lists.contains).map { DockEntry.stack(listID: $0) })
        return DockArrangement(groups: groups)
    }

    /// A name is unique among what stands beside it: in the bar, or in
    /// the same folder.
    private func availableName(_ name: String, except: String?, in parentID: String?) -> String? {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean.count <= 40, !clean.contains("/"), !sections.contains(where: {
            $0.id != except && $0.parentID == parentID
                && $0.name.compare(clean, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }) else { return nil }
        return clean
    }
}
