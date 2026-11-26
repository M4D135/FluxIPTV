import XCTest
@testable import FluxIPTVCore

final class DockShelfTests: XCTestCase {
    private let source = UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!
    private let other = UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!

    private func item(_ id: String, _ kind: IPTVMediaKind, source: UUID? = nil, collection: Bool = false,
                      season: Int? = nil, episode: Int? = nil) -> IPTVItem {
        IPTVItem(id: id, sourceID: source ?? self.source, name: "Titre \(id)", group: "Groupe", logoURL: nil, kind: kind,
                 directURL: nil, xtreamStreamID: nil, fileExtension: nil, isSeriesCollection: collection,
                 seasonNumber: season, episodeNumber: episode)
    }

    func testAShortcutNamesWhatItOpensAndKeepsNoAddress() throws {
        let channel = DockShortcut(item: item("c1", .live))
        XCTAssertEqual(channel.target, .channel)
        XCTAssertNil(channel.playedID)
        let film = DockShortcut(item: item("f1", .movie))
        XCTAssertEqual(film.playedID, "f1")
        let series = item("s1", .series, collection: true)
        XCTAssertEqual(DockShortcut(item: series).target, .series)
        let season = DockShortcut(series: series, season: 12)
        XCTAssertEqual(season.id, "s1#s12")
        XCTAssertEqual(season.itemID, "s1")
        let episode = DockShortcut(series: series, episode: item("s1-e15", .series, season: 12, episode: 15))
        XCTAssertEqual(episode.id, "s1-e15")
        XCTAssertEqual(episode.itemID, "s1")
        XCTAssertEqual(episode.playedID, "s1-e15")
        XCTAssertEqual(episode.title, "Titre s1 · S12 E15")
        // Under the icon the series; on it, which season or episode.
        XCTAssertEqual([season.name, episode.name], ["Titre s1", "Titre s1"])
        XCTAssertEqual([channel.badge, film.badge, season.badge, episode.badge], [nil, nil, "S12", "S12·E15"])
        XCTAssertEqual(DockShortcut(series: series, episode: item("s1-x", .series)).badge, "ÉP.")
        XCTAssertEqual(Set([channel, film, season, episode].map(\.kind)), [.live, .movie, .series])
        // What is written to the preferences names identifiers and titles only.
        let stored = String(decoding: try JSONEncoder().encode([channel, season, episode]), as: UTF8.self)
        XCTAssertFalse(stored.contains("http"))
    }

    func testSectionsAreNamedOnceAndTheFirstOneStays() {
        var shelf = DockShelf()
        XCTAssertEqual(shelf.sections.map(\.id), [DockShelf.defaultSectionID])
        let sport = shelf.createSection(name: "  Sport ")
        XCTAssertNotNil(sport)
        XCTAssertEqual(shelf.sections.last?.name, "Sport")
        XCTAssertNil(shelf.createSection(name: "sport"), "A second section of the same name, whatever its case.")
        XCTAssertNil(shelf.createSection(name: "   "))
        XCTAssertNil(shelf.createSection(name: String(repeating: "x", count: 41)))
        XCTAssertTrue(shelf.renameSection(id: sport!, name: "Le sport"))
        XCTAssertFalse(shelf.renameSection(id: sport!, name: "Raccourcis"))
        XCTAssertFalse(shelf.deleteSection(id: DockShelf.defaultSectionID))
        XCTAssertTrue(shelf.deleteSection(id: sport!))
        XCTAssertEqual(shelf.sections.count, 1)
    }

    func testAssigningCommitsTheWholeChoiceOrNothing() {
        var shelf = DockShelf()
        let channel = DockShortcut(item: item("c1", .live))
        XCTAssertTrue(shelf.assign(channel, to: [DockShelf.defaultSectionID], creating: "Sport"))
        let sport = shelf.sections[1].id
        XCTAssertEqual(shelf.sections(holding: "c1"), [DockShelf.defaultSectionID, sport])
        // An invalid name changes nothing, not even the sections chosen with it.
        let before = shelf
        XCTAssertFalse(shelf.assign(channel, to: [], creating: "sport"))
        XCTAssertFalse(shelf.assign(channel, to: ["gone"]))
        XCTAssertEqual(shelf, before)
        // The same shortcut is never twice in a section.
        XCTAssertTrue(shelf.assign(channel, to: [sport]))
        XCTAssertEqual(shelf.sections(holding: "c1"), [sport])
        XCTAssertEqual(shelf.sections[1].shortcuts.count, 1)
        XCTAssertTrue(shelf.assign(channel, to: []))
        XCTAssertFalse(shelf.contains("c1"))
    }

    func testShortcutsMoveInsideTheirSection() {
        var shelf = DockShelf()
        for id in ["a", "b", "c"] { shelf.assign(DockShortcut(item: item(id, .live)), to: [DockShelf.defaultSectionID]) }
        XCTAssertTrue(shelf.move(shortcutID: "c", in: DockShelf.defaultSectionID, to: 0))
        XCTAssertEqual(shelf.sections[0].shortcuts.map(\.id), ["c", "a", "b"])
        XCTAssertTrue(shelf.move(shortcutID: "c", in: DockShelf.defaultSectionID, to: 99))
        XCTAssertEqual(shelf.sections[0].shortcuts.map(\.id), ["a", "b", "c"])
        XCTAssertFalse(shelf.move(shortcutID: "z", in: DockShelf.defaultSectionID, to: 0))
        shelf.remove(shortcutID: "b")
        XCTAssertEqual(shelf.sections[0].shortcuts.map(\.id), ["a", "c"])
    }

    func testRecentsComeFirstOnceAndAreBounded() {
        var shelf = DockShelf()
        for index in 0..<(DockShelf.recentLimit + 5) { shelf.visit(DockShortcut(item: item("r\(index)", .live))) }
        XCTAssertEqual(shelf.recents.count, DockShelf.recentLimit)
        XCTAssertEqual(shelf.recents.first?.id, "r\(DockShelf.recentLimit + 4)")
        shelf.visit(DockShortcut(item: item("r10", .live)))
        XCTAssertEqual(shelf.recents.first?.id, "r10")
        XCTAssertEqual(shelf.recents.filter { $0.id == "r10" }.count, 1)
        shelf.forget(recentID: "r10")
        XCTAssertFalse(shelf.recents.contains { $0.id == "r10" })
    }

    func testTheBarShowsSectionsThenWhatIsInProgressThenFolders() {
        var shelf = DockShelf()
        let channel = DockShortcut(item: item("c1", .live))
        let film = DockShortcut(item: item("f1", .movie))
        let elsewhere = DockShortcut(item: item("x1", .live, source: other))
        shelf.assign(channel, to: [DockShelf.defaultSectionID])
        shelf.assign(elsewhere, to: [DockShelf.defaultSectionID])
        shelf.assign(film, to: [], creating: "Cinéma")
        shelf.setStack("list-a", shown: true)
        shelf.setStack("list-gone", shown: true)
        shelf.setStack("list-a", shown: true)
        XCTAssertEqual(shelf.stacks, ["list-a", "list-gone"])
        // Watched: a film left unfinished, the pinned channel, two other channels, one of another source.
        for id in ["c9", "c8"] { shelf.visit(DockShortcut(item: item(id, .live))) }
        shelf.visit(elsewhere)
        shelf.visit(channel)
        shelf.visit(DockShortcut(item: item("f2", .movie)))

        let unfinished = shelf.unfinished(sourceID: source) { $0 == "f2" }
        XCTAssertEqual(unfinished?.id, "f2")
        XCTAssertNil(shelf.unfinished(sourceID: other) { $0 == "f2" })
        XCTAssertEqual(shelf.recent(played: "f2", sourceID: source)?.id, "f2")
        XCTAssertNil(shelf.recent(played: "c1", sourceID: source), "A channel is not in the viewing history.")
        let bar = shelf.arrangement(destinations: [.live, .movie], sourceID: source, lists: ["list-a"], resume: unfinished)
        XCTAssertEqual(bar.groups.count, 5)
        XCTAssertEqual(bar.groups[0], [.destination(.live), .destination(.movie)])
        XCTAssertEqual(bar.groups[1], [.shortcut(channel, section: DockShelf.defaultSectionID)], "A shortcut of another source is not shown.")
        XCTAssertEqual(bar.groups[2].map(\.id), ["dock-item-\(shelf.sections[1].id)-f1"])
        // The film in progress first; a pinned title is not repeated among the recents.
        XCTAssertEqual(bar.groups[3].map(\.id), ["dock-resume-f2", "dock-recent-c8", "dock-recent-c9"])
        XCTAssertEqual(bar.groups[4], [.stack(listID: "list-a")], "A folder whose list is gone is not shown.")
        XCTAssertEqual(bar.breaks, [2, 3, 4, 7])
        XCTAssertEqual(Set(bar.entries.map(\.id)).count, bar.entries.count, "Every entry has its own identifier.")
        XCTAssertEqual(bar.entry(id: "dock-resume-f2")?.shortcut?.id, "f2")

        // Nothing in progress, and no section in use: their dividers leave with them.
        let quiet = DockShelf().arrangement(destinations: [.live], sourceID: source, lists: [], resume: nil)
        // Without the recents, what is in progress stays alone.
        let bare = shelf.arrangement(destinations: [.live], sourceID: source, lists: [], recentCount: 0, resume: unfinished)
        XCTAssertEqual(bare.groups.last, [.resume(unfinished!)])
        XCTAssertTrue(bar.entries.allSatisfy { $0.id == "tab-live" || $0.id == "tab-movie" || DockEntry.isShelfID($0.id) })
        XCTAssertFalse(DockEntry.isShelfID("tab-live"))
        XCTAssertTrue(DockEntry.isShelfID(DockEntry.fanAllID))
        XCTAssertEqual(quiet.groups, [[.destination(.live)]])
        XCTAssertEqual(quiet.breaks, [])
        XCTAssertTrue(shelf.retainStacks(["list-a"]))
        XCTAssertEqual(shelf.stacks, ["list-a"])
        XCTAssertFalse(shelf.retainStacks(["list-a"]))
    }

    func testABarThatIsTooLongLosesItsRecentsThenFoldsItsLastShortcuts() {
        var shelf = DockShelf()
        for id in ["a", "b", "c"] { shelf.assign(DockShortcut(item: item(id, .live)), to: [DockShelf.defaultSectionID]) }
        shelf.assign(DockShortcut(item: item("d", .movie)), to: [], creating: "Cinéma")
        let cinema = shelf.sections[1].id
        shelf.setStack("list", shown: true)
        for id in ["r1", "r2", "f1"] { shelf.visit(DockShortcut(item: item(id, id == "f1" ? .movie : .live))) }
        let bar = shelf.arrangement(destinations: [.live, .movie], sourceID: source, lists: ["list"],
                                    resume: shelf.unfinished(sourceID: source) { $0 == "f1" })
        XCTAssertEqual(bar.entries.count, 10)
        XCTAssertEqual(bar.fitted(to: 10), bar)
        // The recents leave first, the oldest first.
        XCTAssertEqual(bar.fitted(to: 9).entries.map(\.id).filter { $0.hasPrefix("dock-recent-") }, ["dock-recent-r2"])
        let tight = bar.fitted(to: 8)
        XCTAssertEqual(tight.entries.map(\.id), ["tab-live", "tab-movie", "dock-item-shortcuts-a", "dock-item-shortcuts-b", "dock-item-shortcuts-c",
                                                 "dock-item-\(cinema)-d", "dock-resume-f1", "dock-stack-list"])
        XCTAssertTrue(tight.hidden.isEmpty)
        // Then the shortcuts added last go into one more folder, which takes a place.
        let folded = bar.fitted(to: 7)
        XCTAssertEqual(folded.entries.map(\.id), ["tab-live", "tab-movie", "dock-item-shortcuts-a", "dock-item-shortcuts-b", "dock-more",
                                                  "dock-resume-f1", "dock-stack-list"])
        XCTAssertEqual(folded.hidden.map(\.id), ["dock-item-shortcuts-c", "dock-item-\(cinema)-d"], "In the order of the bar.")
        XCTAssertEqual(folded.breaks, [2, 5, 6], "The section that is wholly in the folder leaves its divider.")
        XCTAssertEqual(folded.fitted(to: 7), folded, "Fitting again changes nothing.")
        XCTAssertEqual(folded.fitted(to: 6).entries.map(\.id), ["tab-live", "tab-movie", "dock-item-shortcuts-a", "dock-more",
                                                                "dock-resume-f1", "dock-stack-list"])
        let least = bar.fitted(to: 1)
        XCTAssertEqual(least.entries.map(\.id), ["tab-live", "tab-movie", "dock-more", "dock-resume-f1", "dock-stack-list"],
                       "The destinations, what is in progress and the folders always stay.")
        XCTAssertEqual(least.hidden.count, 4)
        XCTAssertEqual(least.breaks, [2, 3, 4])
        XCTAssertTrue(DockEntry.more.isFolder)
        XCTAssertNil(DockEntry.more.shortcut)
    }

    func testARemovedSourceLeavesNothingInTheBar() {
        var shelf = DockShelf()
        shelf.assign(DockShortcut(item: item("c1", .live)), to: [DockShelf.defaultSectionID])
        shelf.assign(DockShortcut(item: item("x1", .live, source: other)), to: [DockShelf.defaultSectionID])
        shelf.visit(DockShortcut(item: item("x2", .live, source: other)))
        XCTAssertTrue(shelf.removeSource(other))
        XCTAssertEqual(shelf.sections[0].shortcuts.map(\.id), ["c1"])
        XCTAssertTrue(shelf.recents.isEmpty)
        XCTAssertFalse(shelf.removeSource(other))
    }

    func testTheShelfSurvivesBeingStored() throws {
        var shelf = DockShelf()
        shelf.assign(DockShortcut(item: item("c1", .live)), to: [DockShelf.defaultSectionID], creating: "Sport")
        shelf.setStack("list", shown: true)
        shelf.visit(DockShortcut(series: item("s1", .series, collection: true), season: 3))
        let restored = try JSONDecoder().decode(DockShelf.self, from: JSONEncoder().encode(shelf))
        XCTAssertEqual(restored, shelf)
    }

    func testDividersTakeTheirRoomAndNeverGrow() {
        let plain = FluxDockMagnifier(count: 6, cell: 100, spacing: 10, maximumScale: 1.4, radius: 240)
        let parted = FluxDockMagnifier(count: 6, cell: 100, spacing: 10, maximumScale: 1.4, radius: 240, breaks: [0, 2, 5, 9, 2], gap: 20)
        XCTAssertEqual(parted.breaks, [2, 5], "A divider stands between two cells, once.")
        XCTAssertEqual(parted.length, plain.length + 40)
        XCTAssertEqual(parted.start(1), plain.start(1))
        XCTAssertEqual(parted.start(2), plain.start(2) + 20)
        XCTAssertEqual(parted.start(5), plain.start(5) + 40)
        XCTAssertEqual(parted.divider(before: 2), 225, "Half way between the end of a cell (210) and the start of the next (240).")
        // A position belongs to the cell that starts before it.
        XCTAssertEqual(parted.index(at: parted.center(2)), 2)
        XCTAssertEqual(parted.index(at: 225), 1)
        XCTAssertEqual(parted.index(at: parted.center(5)), 5)
        XCTAssertEqual(plain.index(at: 215), 1)
        // The cell under the pointer keeps its place; nothing overlaps.
        let layout = parted.layout(pointer: parted.center(3))
        XCTAssertEqual(layout.scales[3], 1.4, accuracy: 0.0001)
        XCTAssertEqual(layout.offsets[3], 0, accuracy: 0.0001)
        for index in 0..<5 {
            let end = parted.center(index) + layout.offsets[index] + 50 * layout.scales[index]
            let next = parted.center(index + 1) + layout.offsets[index + 1] - 50 * layout.scales[index + 1]
            XCTAssertGreaterThanOrEqual(next - end, 10 - 0.0001)
        }
        XCTAssertEqual(plain.layout(pointer: 250), FluxDockMagnifier(count: 6, cell: 100, spacing: 10, maximumScale: 1.4, radius: 240,
                                                                     breaks: [], gap: 20).layout(pointer: 250))
    }

    /// On the home screen the bar takes a second row, then a third, as it
    /// fills, instead of making its icons smaller.
    func testTheBarOfTheHomeScreenTakesRowsAsItFills() {
        var shelf = DockShelf()
        let places: [FluxDockItem] = [.live, .movie, .series, .search, .favorites, .settings]
        for index in 0..<4 { XCTAssertTrue(shelf.assign(DockShortcut(item: item("f\(index)", .movie)), to: [DockShelf.defaultSectionID])) }
        shelf.setStack("list", shown: true)
        var bar = shelf.arrangement(destinations: places, sourceID: source, lists: ["list"], resume: nil)
        // Eleven icons hold on one row of twelve.
        XCTAssertEqual(bar.rows(limit: 12).map(\.entries.count), [11])
        // More than a row: the destinations above everything that is kept.
        for index in 4..<9 { XCTAssertTrue(shelf.assign(DockShortcut(item: item("f\(index)", .movie)), to: [DockShelf.defaultSectionID])) }
        bar = shelf.arrangement(destinations: places, sourceID: source, lists: ["list"], resume: nil)
        let two = bar.rows(limit: 12)
        XCTAssertEqual(two.map(\.entries.count), [6, 10])
        XCTAssertEqual(two[0].entries.map(\.id), places.map(\.focusID))
        XCTAssertEqual(two[1].breaks, [9])
        XCTAssertEqual(bar.shortcutCount, 9)
        XCTAssertEqual(bar.restCount, 1)
        // More than two rows: the shortcuts have a row, the folders another.
        for index in 9..<12 { XCTAssertTrue(shelf.assign(DockShortcut(item: item("f\(index)", .movie)), to: [DockShelf.defaultSectionID])) }
        shelf.visit(DockShortcut(item: item("recent", .live)))
        bar = shelf.arrangement(destinations: places, sourceID: source, lists: ["list"], resume: nil)
        let three = bar.rows(limit: 12)
        XCTAssertEqual(three.map(\.entries.count), [6, 12, 2])
        XCTAssertEqual(three.flatMap { $0.entries.map(\.id) }, bar.entries.map(\.id))
        // The shortcuts that a row cannot hold go into the folder of the
        // others, and the recents keep their place on the last row.
        for index in 12..<16 { XCTAssertTrue(shelf.assign(DockShortcut(item: item("f\(index)", .movie)), to: [DockShelf.defaultSectionID])) }
        bar = shelf.arrangement(destinations: places, sourceID: source, lists: ["list"], resume: nil)
        let fitted = bar.fitted(to: bar.entries.count - (bar.shortcutCount - 12), sparingRecents: true)
        XCTAssertEqual(fitted.shortcutCount, 12)
        XCTAssertEqual(fitted.hidden.count, 5)
        XCTAssertEqual(fitted.restCount, 2)
        XCTAssertEqual(fitted.rows(limit: 12).map(\.entries.count), [6, 12, 2])
        XCTAssertEqual(fitted.rows(limit: 12)[1].hidden.count, 5)
    }

    func testTheArrowsWalkTheRowsOfTheHomeScreen() {
        let rows = [["a", "b", "c", "d", "e", "f"], ["g", "h"], ["i", "j", "k", "l"]]
        XCTAssertEqual(DockArrangement.move(from: "b", action: .right, rows: rows), "c")
        XCTAssertEqual(DockArrangement.move(from: "a", action: .left, rows: rows), "a")
        XCTAssertEqual(DockArrangement.move(from: "f", action: .right, rows: rows), "f")
        // Down and up reach the icon that stands nearest under or over.
        XCTAssertEqual(DockArrangement.move(from: "a", action: .down, rows: rows), "g")
        XCTAssertEqual(DockArrangement.move(from: "f", action: .down, rows: rows), "h")
        XCTAssertEqual(DockArrangement.move(from: "g", action: .down, rows: rows), "j")
        XCTAssertEqual(DockArrangement.move(from: "h", action: .down, rows: rows), "k")
        XCTAssertEqual(DockArrangement.move(from: "l", action: .up, rows: rows), "h")
        XCTAssertEqual(DockArrangement.move(from: "g", action: .up, rows: rows), "c")
        // Past the first and the last row nothing moves.
        XCTAssertEqual(DockArrangement.move(from: "c", action: .up, rows: rows), "c")
        XCTAssertEqual(DockArrangement.move(from: "k", action: .down, rows: rows), "k")
        XCTAssertEqual(DockArrangement.move(from: "nowhere", action: .down, rows: rows), "a")
    }
}
