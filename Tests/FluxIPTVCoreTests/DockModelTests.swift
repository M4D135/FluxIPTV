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

    func testPointerBrowsingStartsThePreviewSooner() {
        XCTAssertEqual(LiveTVPreviewDelay.defaultValue, .three)
        #if os(tvOS)
        XCTAssertEqual(LiveTVPreviewDelay.platformDefault, .three)
        #else
        XCTAssertEqual(LiveTVPreviewDelay.platformDefault, .one)
        #endif
        XCTAssertEqual(FluxDockPosition.defaultValue, .bottom)
        XCTAssertEqual(FluxDockTheme.defaultValue, .glass)
        for position in FluxDockPosition.allCases {
            XCTAssertNotEqual(position.inward, position.outward)
            XCTAssertEqual(position.isVertical, position.inward == .left || position.inward == .right)
        }
    }
}
