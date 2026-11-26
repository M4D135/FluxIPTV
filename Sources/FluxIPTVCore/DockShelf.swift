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

/// A named group of shortcuts. Each one stands apart in the bar, between two
/// dividers, as the parts of the Dock of a Mac do.
public struct DockSection: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public var name: String
    public var shortcuts: [DockShortcut]
    public let isDefault: Bool
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
    /// The shortcuts that the bar has no room for, as one more folder.
    case more

    public static let shortcutPrefix = "dock-item-"
    public static let resumePrefix = "dock-resume-"
    public static let recentPrefix = "dock-recent-"
    public static let stackPrefix = "dock-stack-"
    public static let moreID = "dock-more"
    /// A title of an open folder, above the bar.
    public static let fanPrefix = "dock-fan-"
    /// Last row of an open folder: the whole list, on its own screen.
    public static let fanAllID = "dock-fan-all"

    /// Whether a control belongs to the bar or to its open folder.
    public static func isShelfID(_ id: String) -> Bool {
        id == moreID || [shortcutPrefix, resumePrefix, recentPrefix, stackPrefix, fanPrefix].contains(where: id.hasPrefix)
    }

    public var id: String {
        switch self {
        case .destination(let item): item.focusID
        case .shortcut(let shortcut, let section): "\(Self.shortcutPrefix)\(section)-\(shortcut.id)"
        case .resume(let shortcut): Self.resumePrefix + shortcut.id
        case .recent(let shortcut): Self.recentPrefix + shortcut.id
        case .stack(let listID): Self.stackPrefix + listID
        case .more: Self.moreID
        }
    }
    public var shortcut: DockShortcut? {
        switch self {
        case .shortcut(let shortcut, _), .resume(let shortcut), .recent(let shortcut): shortcut
        case .destination, .stack, .more: nil
        }
    }
    /// A folder opens above the bar instead of leaving the screen.
    public var isFolder: Bool {
        switch self {
        case .stack, .more: true
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
    public func fitted(to limit: Int) -> DockArrangement {
        var groups = groups
        var hidden = hidden
        func total() -> Int { groups.reduce(0) { $0 + $1.count } }
        func isRecent(_ entry: DockEntry) -> Bool { if case .recent = entry { return true } else { return false } }
        func isShortcut(_ entry: DockEntry) -> Bool { if case .shortcut = entry { return true } else { return false } }
        func lastGroup(_ test: (DockEntry) -> Bool) -> Int? { groups.lastIndex { $0.contains(where: test) } }
        while total() > limit, let g = lastGroup(isRecent), let i = groups[g].lastIndex(where: isRecent) {
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

    public init() {
        sections = [DockSection(id: Self.defaultSectionID, name: "Raccourcis", shortcuts: [], isDefault: true)]
        stacks = []
        recents = []
    }

    public func section(id: String) -> DockSection? { sections.first { $0.id == id } }
    /// Sections that hold this shortcut.
    public func sections(holding shortcutID: String) -> Set<String> {
        Set(sections.filter { $0.shortcuts.contains { $0.id == shortcutID } }.map(\.id))
    }
    public func contains(_ shortcutID: String) -> Bool { !sections(holding: shortcutID).isEmpty }

    // MARK: Sections

    @discardableResult public mutating func createSection(name: String) -> String? {
        guard let clean = availableName(name, except: nil) else { return nil }
        let id = UUID().uuidString
        sections.append(DockSection(id: id, name: clean, shortcuts: [], isDefault: false))
        return id
    }

    @discardableResult public mutating func renameSection(id: String, name: String) -> Bool {
        guard let index = sections.firstIndex(where: { $0.id == id }),
              let clean = availableName(name, except: id) else { return false }
        sections[index].name = clean
        return true
    }

    /// The first section always stays; another one leaves with its shortcuts.
    @discardableResult public mutating func deleteSection(id: String) -> Bool {
        guard let index = sections.firstIndex(where: { $0.id == id && !$0.isDefault }) else { return false }
        sections.remove(at: index)
        return true
    }

    // MARK: Shortcuts

    /// The whole choice of the user for one shortcut, committed at once: the
    /// sections that keep it, and a new one to create for it. An invalid name
    /// or a section that no longer exists changes nothing.
    @discardableResult public mutating func assign(_ shortcut: DockShortcut, to sectionIDs: Set<String>,
                                                   creating name: String? = nil) -> Bool {
        guard sectionIDs.isSubset(of: Set(sections.map(\.id))) else { return false }
        var draft = self
        var chosen = sectionIDs
        if let name {
            guard let id = draft.createSection(name: name) else { return false }
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
        var pinned = Set<String>()
        for section in sections {
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
        groups.append(stacks.filter(lists.contains).map { DockEntry.stack(listID: $0) })
        return DockArrangement(groups: groups)
    }

    private func availableName(_ name: String, except: String?) -> String? {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean.count <= 40, !sections.contains(where: {
            $0.id != except && $0.name.compare(clean, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }) else { return nil }
        return clean
    }
}
