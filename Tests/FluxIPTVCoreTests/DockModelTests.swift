import XCTest
@testable import FluxIPTVCore

final class DockModelTests: XCTestCase {
    private func slice(_ count: Int) -> CatalogSlice {
        let source = UUID()
        return CatalogSlice((0..<count).map { index in
            IPTVItem(id: "item-\(index)", sourceID: source, name: "Titre \(index)", group: "Groupe",
                     logoURL: nil, kind: .live, directURL: nil, xtreamStreamID: String(index), fileExtension: "m3u8")
        })
    }

    func testSavedOrderKeepsKnownDestinationsOnceAndAppendsNewOnes() {
        XCTAssertEqual(FluxDockItem.order(from: ""), FluxDockItem.allCases)
        XCTAssertEqual(FluxDockItem.order(from: "settings, movie,movie,unknown,live"),
                       [.settings, .movie, .live, .series, .search, .favorites])
        let order = FluxDockItem.order(from: "series,live")
        XCTAssertEqual(FluxDockItem.order(from: FluxDockItem.stored(order)), order)
        XCTAssertEqual(Set(order), Set(FluxDockItem.allCases))
    }

    func testMovingADestinationClampsToTheBarAndKeepsEveryDestination() {
        let order = FluxDockItem.allCases
        XCTAssertEqual(FluxDockItem.moving(.settings, to: 0, in: order).first, .settings)
        XCTAssertEqual(FluxDockItem.moving(.live, to: 99, in: order).last, .live)
        XCTAssertEqual(FluxDockItem.moving(.movie, to: -4, in: order).first, .movie)
        XCTAssertEqual(FluxDockItem.moving(.search, to: 3, in: order), order)
        XCTAssertEqual(FluxDockItem.moving(.live, to: 2, in: order), [.movie, .series, .live, .search, .favorites, .settings])
        for item in order { XCTAssertEqual(Set(FluxDockItem.moving(item, to: 2, in: order)), Set(order)) }
    }

    func testFocusIdentifiersAreUniqueAndReversible() {
        XCTAssertEqual(Set(FluxDockItem.allCases.map(\.focusID)).count, FluxDockItem.allCases.count)
        for item in FluxDockItem.allCases { XCTAssertEqual(FluxDockItem(focusID: item.focusID), item) }
        XCTAssertNil(FluxDockItem(focusID: "group-all"))
        for kind in IPTVMediaKind.allCases {
            XCTAssertEqual(FluxDockItem(kind: kind).mediaKind, kind)
            XCTAssertEqual(FluxDockItem(kind: kind).focusID, "tab-\(kind.rawValue)")
        }
    }

    func testMagnifierRestsWithoutPointerAndPeaksUnderIt() {
        let magnifier = FluxDockMagnifier(count: 6, cell: 72, spacing: 4, maximumScale: 1.5, radius: 170)
        let rest = magnifier.layout(pointer: nil)
        XCTAssertEqual(rest.scales, Array(repeating: 1, count: 6))
        XCTAssertEqual(rest.offsets, Array(repeating: 0, count: 6))
        XCTAssertEqual(magnifier.layout(pointer: 100, intensity: 0), rest)

        let pointer = magnifier.center(2)
        let layout = magnifier.layout(pointer: pointer)
        XCTAssertEqual(layout.scales[2], 1.5, accuracy: 1e-9)
        XCTAssertEqual(layout.offsets[2], 0, accuracy: 1e-9)
        XCTAssertGreaterThan(layout.scales[1], 1)
        XCTAssertLessThan(layout.scales[1], layout.scales[2])
        XCTAssertEqual(layout.scales[1], layout.scales[3], accuracy: 1e-9)
        XCTAssertEqual(layout.scales[5], 1, accuracy: 1e-9)
        XCTAssertLessThan(layout.leading, 0)
        XCTAssertGreaterThan(layout.trailing, 0)
        XCTAssertEqual(layout.trailing - layout.leading, layout.scales.reduce(0) { $0 + 72 * ($1 - 1) }, accuracy: 1e-9)
    }

    func testMagnifiedCellsNeverOverlapAndFollowThePointerContinuously() {
        let magnifier = FluxDockMagnifier(count: 6, cell: 72, spacing: 4, maximumScale: 1.6, radius: 180)
        var previous: FluxDockMagnifier.Layout?
        for step in stride(from: -40.0, through: magnifier.length + 40, by: 0.5) {
            let layout = magnifier.layout(pointer: step)
            for index in 1..<magnifier.count {
                let endOfPrevious = magnifier.center(index - 1) + layout.offsets[index - 1] + 36 * layout.scales[index - 1]
                let startOfCurrent = magnifier.center(index) + layout.offsets[index] - 36 * layout.scales[index]
                XCTAssertEqual(startOfCurrent - endOfPrevious, 4, accuracy: 1e-6)
            }
            if let previous {
                for index in 0..<magnifier.count {
                    XCTAssertLessThan(abs(layout.offsets[index] - previous.offsets[index]), 1.5)
                    XCTAssertLessThan(abs(layout.scales[index] - previous.scales[index]), 0.02)
                }
            }
            previous = layout
        }
        XCTAssertEqual(magnifier.index(at: -30), 0)
        XCTAssertEqual(magnifier.index(at: magnifier.center(4)), 4)
        XCTAssertEqual(magnifier.index(at: 10_000), 5)
        XCTAssertNil(FluxDockMagnifier(count: 0, cell: 72, spacing: 4, maximumScale: 1.5, radius: 170).index(at: 10))
    }

    func testDockNavigationFollowsItsEdge() {
        let dock = ["tab-live", "tab-movie", "tab-series", "search"]
        func stuck(_ id: String?, _ action: RemoteAction) -> String? { id }
        for position in FluxDockPosition.allCases {
            let along: (RemoteAction, RemoteAction) = position.isVertical ? (.up, .down) : (.left, .right)
            XCTAssertEqual(FluxDockNavigation.move(from: "tab-movie", action: along.0, position: position, dockIDs: dock,
                                                   preferredDockID: nil, entryID: "item-3", content: stuck), "tab-live")
            XCTAssertEqual(FluxDockNavigation.move(from: "tab-movie", action: along.1, position: position, dockIDs: dock,
                                                   preferredDockID: nil, entryID: "item-3", content: stuck), "tab-series")
            XCTAssertEqual(FluxDockNavigation.move(from: "search", action: along.1, position: position, dockIDs: dock,
                                                   preferredDockID: nil, entryID: "item-3", content: stuck), "search")
            XCTAssertEqual(FluxDockNavigation.move(from: "tab-movie", action: position.inward, position: position, dockIDs: dock,
                                                   preferredDockID: nil, entryID: "item-3", content: stuck), "item-3")
            XCTAssertEqual(FluxDockNavigation.move(from: "tab-movie", action: position.outward, position: position, dockIDs: dock,
                                                   preferredDockID: nil, entryID: "item-3", content: stuck), "tab-movie")
            // An edge of the screen hands the outward direction to the bar.
            XCTAssertEqual(FluxDockNavigation.move(from: "item-3", action: position.outward, position: position, dockIDs: dock,
                                                   preferredDockID: "tab-series", entryID: nil, content: stuck), "tab-series")
            XCTAssertEqual(FluxDockNavigation.move(from: "item-3", action: position.outward, position: position, dockIDs: dock,
                                                   preferredDockID: "unknown", entryID: nil, content: stuck), "tab-live")
            // A move the screen can perform stays inside the screen.
            XCTAssertEqual(FluxDockNavigation.move(from: "item-3", action: position.outward, position: position, dockIDs: dock,
                                                   preferredDockID: "tab-series", entryID: nil, content: { _, _ in "item-4" }), "item-4")
            XCTAssertEqual(FluxDockNavigation.move(from: "item-3", action: position.inward, position: position, dockIDs: dock,
                                                   preferredDockID: "tab-series", entryID: nil, content: stuck), "item-3")
        }
        XCTAssertEqual(FluxDockNavigation.move(from: "item-3", action: .down, position: .bottom, dockIDs: [],
                                               preferredDockID: nil, entryID: nil, content: stuck), "item-3")
    }

    /// "ne pas laisser de fonctionnalité vide": a fresh press at an edge of
    /// the screen goes to Back or to the dock, and the bar is a ring.
    func testAFreshPressLeavesNoDeadKey() {
        let dock = ["desk-back", "tab-live", "tab-movie", "search"]
        func stuck(_ id: String?, _ action: RemoteAction) -> String? { id }
        func move(_ from: String, _ action: RemoteAction, fresh: Bool = true, position: FluxDockPosition = .bottom,
                  ids: [String] = dock, top: String? = "find") -> String? {
            FluxDockNavigation.move(from: from, action: action, position: position, dockIDs: ids, preferredDockID: "tab-movie",
                                    entryID: "item-3", backID: "desk-back", topID: top, fresh: fresh, content: stuck)
        }
        // From an edge of the screen: Left to Back, every other way to the icon of the screen.
        XCTAssertEqual(move("item-3", .left), "desk-back")
        XCTAssertEqual(move("item-3", .right), "tab-movie")
        XCTAssertEqual(move("item-3", .up), "tab-movie")
        XCTAssertEqual(move("item-3", .down), "tab-movie")
        // A key held down stops at the edge, as it did.
        XCTAssertEqual(move("item-3", .left, fresh: false), "item-3")
        XCTAssertEqual(move("item-3", .right, fresh: false), "item-3")
        XCTAssertEqual(move("item-3", .down, fresh: false), "tab-movie")
        // Past one end of the bar comes the other; away from the screen, its top.
        XCTAssertEqual(move("desk-back", .left), "search")
        XCTAssertEqual(move("search", .right), "desk-back")
        XCTAssertEqual(move("tab-live", .down), "find")
        XCTAssertEqual(move("desk-back", .left, fresh: false), "desk-back")
        XCTAssertEqual(move("search", .right, fresh: false), "search")
        XCTAssertEqual(move("tab-live", .down, fresh: false), "tab-live")
        XCTAssertEqual(move("tab-live", .down, top: nil), "tab-live")
        // From Back: Up to where the list was left, Right along the bar.
        XCTAssertEqual(move("desk-back", .up), "item-3")
        XCTAssertEqual(move("desk-back", .right), "tab-live")
        XCTAssertEqual(move("tab-live", .left), "desk-back")
        // A move the screen can make is made.
        XCTAssertEqual(FluxDockNavigation.move(from: "item-3", action: .left, position: .bottom, dockIDs: dock,
                                               preferredDockID: "tab-movie", entryID: nil, backID: "desk-back", topID: "find",
                                               fresh: true) { _, _ in "item-2" }, "item-2")
        // Without Back in the bar, Left goes to the icon of the screen; a bar on the left edge takes Left itself.
        XCTAssertEqual(move("item-3", .left, ids: ["tab-live", "tab-movie"]), "tab-movie")
        XCTAssertEqual(move("item-3", .left, position: .leading), "tab-movie")
        // A bar on a side is a ring along Up and Down.
        XCTAssertEqual(move("desk-back", .up, position: .leading), "search")
        XCTAssertEqual(move("search", .down, position: .trailing), "desk-back")
        XCTAssertNil(FluxDockNavigation.beyond("item-3", action: .select, position: .bottom, dockIDs: dock,
                                               preferredDockID: "tab-movie", backID: "desk-back", topID: "find"))
        XCTAssertNil(FluxDockNavigation.beyond("tab-live", action: .right, position: .bottom, dockIDs: dock,
                                               preferredDockID: "tab-movie", backID: "desk-back", topID: "find"))
    }

    func testOnlyAPressAfterAPauseIsFresh() {
        let cadence = FluxPressCadence()
        XCTAssertTrue(cadence.press(at: 10))
        XCTAssertFalse(cadence.press(at: 10.1), "A run of presses stops at the edge.")
        XCTAssertFalse(cadence.press(at: 10.3))
        XCTAssertTrue(cadence.press(at: 10.8), "After a pause the next press goes beyond it.")
        XCTAssertFalse(cadence.press(at: 12, held: true), "A key held down is never fresh.")
        XCTAssertFalse(cadence.press(at: 12.2))
        XCTAssertTrue(cadence.press(at: 12.2 + FluxPressCadence.pause + 0.05))
    }

    func testDeskNavigationCrossesColumnGridAndActions() {
        let items = slice(5), sidebar = ["all", "favorites", "sports"], actions = ["watch", "favorite"]
        func move(_ from: String?, _ action: RemoteAction, columns: Int = 2, toolbar: [[String]] = [["reload"], ["page-prev", "page-next"]]) -> String? {
            DeskNavigation.move(from: from, action: action, items: items, columns: columns, sidebarIDs: sidebar,
                                preferredSidebarID: "sports", preferredItemID: "item-3", toolbar: toolbar, trailingIDs: actions)
        }
        XCTAssertEqual(move("favorites", .up), "all")
        XCTAssertEqual(move("all", .up), "all")
        XCTAssertEqual(move("sports", .down), "sports")
        XCTAssertEqual(move("all", .left), "all")
        XCTAssertEqual(move("favorites", .right), "item-3")

        XCTAssertEqual(move("item-2", .left), "sports")
        XCTAssertEqual(move("item-3", .left), "item-2")
        XCTAssertEqual(move("item-2", .right), "item-3")
        XCTAssertEqual(move("item-3", .right), "watch")
        XCTAssertEqual(move("item-4", .right), "watch")
        XCTAssertEqual(move("item-0", .down), "item-2")
        XCTAssertEqual(move("item-3", .down), "item-4")
        XCTAssertEqual(move("item-4", .down), "item-4")
        XCTAssertEqual(move("item-3", .up), "item-1")
        XCTAssertEqual(move("item-1", .up), "page-next")
        XCTAssertEqual(move("item-0", .up), "page-prev")
        XCTAssertEqual(move("item-1", .up, toolbar: []), "item-1")

        XCTAssertEqual(move("page-prev", .up), "reload")
        XCTAssertEqual(move("reload", .up), "reload")
        XCTAssertEqual(move("reload", .left), "sports")
        XCTAssertEqual(move("page-next", .right), "watch")
        XCTAssertEqual(move("page-next", .down), "item-1")
        XCTAssertEqual(move("reload", .down), "page-prev")

        XCTAssertEqual(move("watch", .right), "favorite")
        XCTAssertEqual(move("favorite", .right), "favorite")
        XCTAssertEqual(move("favorite", .left), "watch")
        XCTAssertEqual(move("watch", .left), "item-3")
        XCTAssertEqual(move("watch", .down), "watch")
        XCTAssertEqual(move(nil, .down), "item-3")
        XCTAssertEqual(move("item-2", .down, columns: 1), "item-3")
        XCTAssertEqual(move("item-2", .right, columns: 1), "watch")

        let empty = CatalogSlice()
        XCTAssertEqual(DeskNavigation.move(from: "all", action: .right, items: empty, columns: 2, sidebarIDs: sidebar,
                                           preferredSidebarID: nil, preferredItemID: nil, toolbar: [["reload"]]), "reload")
        XCTAssertEqual(DeskNavigation.move(from: "reload", action: .down, items: empty, columns: 2, sidebarIDs: sidebar,
                                           preferredSidebarID: nil, preferredItemID: nil, toolbar: [["reload"]]), "reload")
        XCTAssertEqual(DeskNavigation.move(from: "reload", action: .left, items: empty, columns: 2, sidebarIDs: sidebar,
                                           preferredSidebarID: nil, preferredItemID: nil, toolbar: [["reload"]]), "all")
    }

    func testRightAtTheEndOfARowReadsOnToTheNextRow() {
        let items = slice(5)
        func move(_ from: String, _ action: RemoteAction, columns: Int = 2, trailing: [String] = []) -> String? {
            DeskNavigation.move(from: from, action: action, items: items, columns: columns, sidebarIDs: ["all"],
                                preferredSidebarID: nil, preferredItemID: nil, toolbar: [], trailingIDs: trailing)
        }
        XCTAssertEqual(move("item-1", .right), "item-2", "The end of a row leads to the start of the next one.")
        XCTAssertEqual(move("item-3", .right), "item-4")
        XCTAssertEqual(move("item-0", .right), "item-1")
        XCTAssertEqual(move("item-4", .right), "item-4", "The last title stays: its edge leads to the icon.")
        XCTAssertEqual(move("item-1", .right, trailing: ["watch"]), "watch", "Actions beyond the grid come first.")
        XCTAssertEqual(move("item-1", .right, columns: 1), "item-1", "A list keeps Right for its edge.")
        XCTAssertEqual(move("item-2", .left), "all", "Left at the start of a row still leads to the column.")
    }

    func testThePreviewOfATelevisionWaitsOneSecond() {
        XCTAssertEqual(LiveTVPreviewDelay.defaultValue, .one)
        XCTAssertEqual(LiveTVPreviewDelay.platformDefault, .one)
        // The three seconds the 0.9.3 saved on a television were its default.
        let suite = "flux.preview.migration.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(3, forKey: LiveTVPreviewDelay.storageKey)
        LiveTVPreviewDelay.migrate(defaults, television: true)
        XCTAssertNil(defaults.object(forKey: LiveTVPreviewDelay.storageKey))
        defaults.set(3, forKey: LiveTVPreviewDelay.storageKey)
        LiveTVPreviewDelay.migrate(defaults, television: true)
        XCTAssertEqual(defaults.integer(forKey: LiveTVPreviewDelay.storageKey), 3, "Chosen after the update, it stays.")
        let mac = UserDefaults(suiteName: suite + ".mac")!
        defer { mac.removePersistentDomain(forName: suite + ".mac") }
        mac.set(3, forKey: LiveTVPreviewDelay.storageKey)
        LiveTVPreviewDelay.migrate(mac, television: false)
        XCTAssertEqual(mac.integer(forKey: LiveTVPreviewDelay.storageKey), 3, "A Mac already waited one second: three was chosen.")
        let ten = UserDefaults(suiteName: suite + ".ten")!
        defer { ten.removePersistentDomain(forName: suite + ".ten") }
        ten.set(10, forKey: LiveTVPreviewDelay.storageKey)
        LiveTVPreviewDelay.migrate(ten, television: true)
        XCTAssertEqual(ten.integer(forKey: LiveTVPreviewDelay.storageKey), 10)
    }

    func testPointerBrowsingStartsThePreviewSooner() {
        XCTAssertEqual(FluxDockPosition.defaultValue, .bottom)
        XCTAssertEqual(FluxDockTheme.defaultValue, .glass)
        for position in FluxDockPosition.allCases {
            XCTAssertNotEqual(position.inward, position.outward)
            XCTAssertEqual(position.isVertical, position.inward == .left || position.inward == .right)
        }
    }
}
