import XCTest
@testable import FluxIPTVCore

final class SeriesSeasonRackLayoutTests: XCTestCase {
    func testLongSeriesKeepsSelectedSeasonVisibleAndOriginalIndices() {
        let seasons = Array(0..<40)
        for selected in [-100, 0, 1, 7, 8, 20, 39, 100] {
            let layout = SeriesSeasonRackLayout(seasonNumbers: seasons, selectedIndex: selected, format: .dvd)
            XCTAssertEqual(layout.slots.count, SeriesSeasonRackLayout.maximumVisibleSeasons)
            XCTAssertTrue(layout.visibleRange.contains(layout.selectedIndex))
            XCTAssertEqual(layout.slots.map(\.index), Array(layout.visibleRange))
            XCTAssertEqual(layout.slots.map(\.seasonNumber), Array(seasons[layout.visibleRange]))
            XCTAssertEqual(layout.selectedIndex, max(0, min(selected, seasons.count - 1)))
        }
    }

    func testBothFormatsKeepEveryCaseInsideBoundsWithoutSideCollisions() {
        for format in CasePackageFormat.allCases {
            for count in [1, 2, 8, 30] {
                for selected in 0..<count {
                    let layout = SeriesSeasonRackLayout(seasonNumbers: Array(1...count), selectedIndex: selected, format: format)
                    for slot in layout.slots {
                        XCTAssertLessThanOrEqual(abs(slot.x) + layout.caseThickness / 2, layout.halfWidth - layout.wall + 0.0001)
                        XCTAssertGreaterThanOrEqual(slot.z - layout.caseDepth / 2, -layout.halfDepth + layout.wall - 0.0001)
                        XCTAssertLessThanOrEqual(slot.z + layout.caseDepth / 2, layout.halfDepth + 0.0001)
                    }
                    for pair in zip(layout.slots, layout.slots.dropFirst()) {
                        XCTAssertGreaterThan(pair.1.x - pair.0.x, layout.caseThickness)
                    }
                    let chosen = layout.slots.first { $0.index == layout.selectedIndex }!
                    XCTAssertEqual(chosen.z, layout.baseCaseZ + layout.selectionAdvance, accuracy: 0.0001)
                    XCTAssertTrue(layout.slots.filter { $0.index != layout.selectedIndex }.allSatisfy { $0.z == layout.baseCaseZ })
                }
            }
        }
    }

    func testEmptySeriesHasNoInventedSeasonAndFormatKeepsPhysicalThickness() {
        let empty = SeriesSeasonRackLayout(seasonNumbers: [], selectedIndex: Int.min, format: .dvd)
        XCTAssertTrue(empty.slots.isEmpty)
        XCTAssertEqual(empty.visibleRange, 0..<0)
        let dvd = SeriesSeasonRackLayout(seasonNumbers: [1, 2], selectedIndex: 0, format: .dvd)
        let vhs = SeriesSeasonRackLayout(seasonNumbers: [1, 2], selectedIndex: 0, format: .vhs)
        XCTAssertEqual(vhs.halfHeight, dvd.halfHeight)
        XCTAssertGreaterThan(vhs.caseThickness, dvd.caseThickness * 1.8)
    }
}
