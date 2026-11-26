import XCTest
@testable import FluxIPTVCore

final class DeskZonesTests: XCTestCase {
    private let directions: [RemoteAction] = [.up, .down, .left, .right]

    private func reachable(from start: DeskZone, available: [DeskZone], dock: FluxDockPosition) -> Set<DeskZone> {
        var seen: Set<DeskZone> = [start]
        var queue = [start]
        while let zone = queue.popLast() {
            for direction in directions {
                let next = DeskZoneMap.move(from: zone, action: direction, available: available, dock: dock)
                if seen.insert(next).inserted { queue.append(next) }
            }
        }
        return seen
    }

    func testEveryZoneOfAScreenIsReachableFromEveryOtherForEveryDockEdge() {
        let optional: [DeskZone] = [.top, .column, .actions]
        for dock in FluxDockPosition.allCases {
            for mask in 0..<(1 << optional.count) {
                var available: [DeskZone] = [.content, .dock]
                for (bit, zone) in optional.enumerated() where mask & (1 << bit) != 0 { available.append(zone) }
                for start in available {
                    XCTAssertEqual(reachable(from: start, available: available, dock: dock), Set(available),
                                   "dock \(dock), zones \(available), from \(start)")
                }
            }
        }
    }

    func testZonesFollowTheLayoutOfTheDeskWithTheBarUnderTheColumn() {
        let all = DeskZone.allCases
        func move(_ zone: DeskZone, _ action: RemoteAction, _ available: [DeskZone] = DeskZone.allCases) -> DeskZone {
            DeskZoneMap.move(from: zone, action: action, available: available, dock: .corner)
        }
        XCTAssertEqual(move(.content, .up), .top)
        XCTAssertEqual(move(.content, .left), .column)
        XCTAssertEqual(move(.content, .right), .actions)
        XCTAssertEqual(move(.content, .down), .dock)
        XCTAssertEqual(move(.column, .down), .dock)
        XCTAssertEqual(move(.column, .up), .top)
        XCTAssertEqual(move(.column, .right), .content)
        XCTAssertEqual(move(.actions, .left), .content)
        XCTAssertEqual(move(.top, .down), .content)
        XCTAssertEqual(move(.dock, .up), .column)
        XCTAssertEqual(move(.dock, .right), .content)
        // Nothing lies that way: the zone keeps the selection.
        XCTAssertEqual(move(.dock, .down), .dock)
        XCTAssertEqual(move(.dock, .left), .dock)
        XCTAssertEqual(move(.column, .left), .column)
        XCTAssertEqual(move(.actions, .right), .actions)
        XCTAssertEqual(move(.top, .up), .top)
        // A zone the screen does not offer is stepped over.
        XCTAssertEqual(move(.content, .right, [.top, .column, .content, .dock]), .content)
        XCTAssertEqual(move(.column, .right, [.column, .actions, .dock]), .actions)
        XCTAssertEqual(move(.dock, .up, [.content, .dock]), .content)
        XCTAssertEqual(move(.top, .down, [.top, .dock]), .dock)
        XCTAssertEqual(all.count, 5)
    }

    func testTheBarIsReachedFromTheEdgeThatCarriesIt() {
        let all = DeskZone.allCases
        XCTAssertEqual(DeskZoneMap.move(from: .content, action: .down, available: all, dock: .bottom), .dock)
        XCTAssertEqual(DeskZoneMap.move(from: .dock, action: .up, available: all, dock: .bottom), .content)
        XCTAssertEqual(DeskZoneMap.move(from: .top, action: .up, available: all, dock: .top), .dock)
        XCTAssertEqual(DeskZoneMap.move(from: .dock, action: .down, available: all, dock: .top), .top)
        XCTAssertEqual(DeskZoneMap.move(from: .content, action: .down, available: all, dock: .top), .content)
        XCTAssertEqual(DeskZoneMap.move(from: .column, action: .left, available: all, dock: .leading), .dock)
        XCTAssertEqual(DeskZoneMap.move(from: .dock, action: .right, available: all, dock: .leading), .column)
        XCTAssertEqual(DeskZoneMap.move(from: .actions, action: .right, available: all, dock: .trailing), .dock)
        XCTAssertEqual(DeskZoneMap.move(from: .content, action: .right, available: [.column, .content, .dock], dock: .trailing), .dock)
        XCTAssertEqual(DeskZoneMap.move(from: .dock, action: .left, available: all, dock: .trailing), .actions)
    }

    func testCyclingWalksTheZonesInReadingOrderAndWraps() {
        let available: [DeskZone] = [.dock, .content, .top, .column]
        var zone = DeskZoneMap.cycle(from: nil, forward: true, available: available)
        var walked: [DeskZone] = []
        for _ in 0..<5 {
            guard let current = zone else { return XCTFail("A screen with zones always has a next one.") }
            walked.append(current)
            zone = DeskZoneMap.cycle(from: current, forward: true, available: available)
        }
        XCTAssertEqual(walked, [.top, .column, .content, .dock, .top])
        XCTAssertEqual(DeskZoneMap.cycle(from: .top, forward: false, available: available), .dock)
        XCTAssertEqual(DeskZoneMap.cycle(from: nil, forward: false, available: available), .dock)
        // A zone that left the screen starts the walk again.
        XCTAssertEqual(DeskZoneMap.cycle(from: .actions, forward: true, available: available), .top)
        XCTAssertNil(DeskZoneMap.cycle(from: .content, forward: true, available: []))
    }

    func testTheTopOfTheColumnAndTheControlsAboveItLeadToEachOther() {
        let source = UUID()
        let items = CatalogSlice((0..<4).map { index in
            IPTVItem(id: "item-\(index)", sourceID: source, name: "Titre \(index)", group: "Groupe",
                     logoURL: nil, kind: .live, directURL: nil, xtreamStreamID: String(index), fileExtension: "m3u8")
        })
        let sidebar = ["countries", "group-all", "sports"]
        let header = ["desk-back", "desk-home"]
        let toolbar = [header + ["search-field", "reload"], ["page-prev", "page-next"]]
        func move(_ from: String?, _ action: RemoteAction, sidebar: [String] = ["countries", "group-all", "sports"]) -> String? {
            DeskNavigation.move(from: from, action: action, items: items, columns: 2, sidebarIDs: sidebar,
                                preferredSidebarID: "sports", preferredItemID: "item-1", toolbar: toolbar,
                                trailingIDs: ["watch"], headerIDs: header)
        }
        XCTAssertEqual(move("countries", .up), "desk-back")
        XCTAssertEqual(move("group-all", .up), "countries")
        XCTAssertEqual(move("desk-back", .down), "countries")
        XCTAssertEqual(move("desk-home", .down), "countries")
        XCTAssertEqual(move("desk-back", .right), "desk-home")
        XCTAssertEqual(move("desk-home", .right), "search-field")
        XCTAssertEqual(move("search-field", .right), "reload")
        XCTAssertEqual(move("search-field", .left), "desk-home")
        XCTAssertEqual(move("search-field", .down), "page-next")
        XCTAssertEqual(move("reload", .down), "page-next")
        XCTAssertEqual(move("page-next", .down), "item-1")
        XCTAssertEqual(move("item-1", .up), "page-next")
        XCTAssertEqual(move("page-prev", .up), "desk-back")
        XCTAssertEqual(move(sidebar[0], .down), sidebar[1])
        // Without a column the same controls lead down into the screen.
        XCTAssertEqual(move("desk-back", .down, sidebar: []), "page-prev")
    }

    /// One key walks the zones from the content: the bar first, then the
    /// line of the search, the column, and the content again.
    func testOneKeyHopsFromTheContentToTheBarThenTheTopThenTheColumn() {
        let available: [DeskZone] = [.top, .column, .content, .dock]
        XCTAssertEqual(DeskZoneMap.hop(from: .content, forward: true, available: available), .dock)
        XCTAssertEqual(DeskZoneMap.hop(from: .dock, forward: true, available: available), .top)
        XCTAssertEqual(DeskZoneMap.hop(from: .top, forward: true, available: available), .column)
        XCTAssertEqual(DeskZoneMap.hop(from: .column, forward: true, available: available), .content)
        // Backwards, the same walk the other way.
        XCTAssertEqual(DeskZoneMap.hop(from: .content, forward: false, available: available), .column)
        XCTAssertEqual(DeskZoneMap.hop(from: .dock, forward: false, available: available), .content)
        // The actions beside a channel come after the column when they are there.
        XCTAssertEqual(DeskZoneMap.hop(from: .column, forward: true, available: available + [.actions]), .actions)
        XCTAssertEqual(DeskZoneMap.hop(from: .actions, forward: true, available: available + [.actions]), .content)
        // From nowhere the walk starts in the content; a screen of one zone has nowhere to go.
        XCTAssertEqual(DeskZoneMap.hop(from: nil, forward: true, available: available), .content)
        XCTAssertNil(DeskZoneMap.hop(from: .dock, forward: true, available: [.dock]))
        XCTAssertNil(DeskZoneMap.hop(from: .content, forward: true, available: []))
        // A zone the screen does not offer starts the walk again.
        XCTAssertEqual(DeskZoneMap.hop(from: .actions, forward: true, available: available), .content)
    }
}
