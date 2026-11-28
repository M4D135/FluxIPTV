import XCTest
@testable import FluxIPTVCore

final class DeskPanelsTests: XCTestCase {
    func testNothingIsFoldedUntilItIsAsked() {
        let folds = DeskFolds()
        for kind in IPTVMediaKind.allCases {
            for panel in DeskPanel.allCases {
                XCTAssertFalse(folds.isFolded(panel, in: kind), "\(panel) \(kind)")
            }
        }
        XCTAssertEqual(folds.rawValue, "")
        XCTAssertEqual(DeskFolds(rawValue: ""), folds)
    }

    func testEachSectionKeepsItsOwnPanels() {
        let folds = DeskFolds().setting(.column, in: .movie, folded: true).setting(.preview, in: .live, folded: true)
        XCTAssertTrue(folds.isFolded(.column, in: .movie))
        XCTAssertFalse(folds.isFolded(.column, in: .series))
        XCTAssertFalse(folds.isFolded(.column, in: .live))
        XCTAssertTrue(folds.isFolded(.preview, in: .live))
        XCTAssertEqual(folds.rawValue, "column-movie,preview-live")

        let open = folds.setting(.column, in: .movie, folded: false)
        XCTAssertFalse(open.isFolded(.column, in: .movie))
        XCTAssertTrue(open.isFolded(.preview, in: .live))
    }

    func testOnlyTheChannelsHaveAPreviewToFold() {
        XCTAssertTrue(DeskPanel.preview.exists(in: .live))
        XCTAssertFalse(DeskPanel.preview.exists(in: .movie))
        XCTAssertFalse(DeskPanel.preview.exists(in: .series))
        for kind in IPTVMediaKind.allCases { XCTAssertTrue(DeskPanel.column.exists(in: kind)) }

        let folds = DeskFolds().setting(.preview, in: .movie, folded: true)
        XCTAssertEqual(folds, DeskFolds())
        XCTAssertFalse(folds.isFolded(.preview, in: .movie))
    }

    func testThePreferenceSurvivesItsTextAndForgetsWhatItDoesNotKnow() {
        let folds = DeskFolds().setting(.column, in: .live, folded: true).setting(.column, in: .series, folded: true)
        XCTAssertEqual(DeskFolds(rawValue: folds.rawValue), folds)

        let read = DeskFolds(rawValue: " column-live , preview-movie,dock-live,,column-series")
        XCTAssertEqual(read?.rawValue, "column-live,column-series")
    }

    func testTheKeysOfThePanelsAreDistinct() {
        let ids = DeskPanel.allCases.flatMap { [$0.foldID, $0.unfoldID] }
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertEqual(DeskPanel.preview.unfoldID, "desk-preview-unfold")
        XCTAssertEqual(DeskPanel.column.foldTitle, "Replier la colonne")
    }

    func testTheTableTakesAsManyTilesAsTheWidthHolds() {
        XCTAssertEqual(DeskChannelGrid.columns(width: 600, tile: 300, gap: 10), 1)
        XCTAssertEqual(DeskChannelGrid.columns(width: 610, tile: 300, gap: 10), 2)
        XCTAssertEqual(DeskChannelGrid.columns(width: 604, tile: 300, gap: 10), 2, "a rounding does not cost a column")
        XCTAssertEqual(DeskChannelGrid.columns(width: 1_240, tile: 300, gap: 10), 4)
        XCTAssertEqual(DeskChannelGrid.columns(width: 5_000, tile: 300, gap: 10), 6)
        XCTAssertEqual(DeskChannelGrid.columns(width: 5_000, tile: 300, gap: 10, limit: 3), 3)
        XCTAssertEqual(DeskChannelGrid.columns(width: 100, tile: 300, gap: 10), 1)
        XCTAssertEqual(DeskChannelGrid.columns(width: .nan, tile: 300, gap: 10), 1)
        XCTAssertEqual(DeskChannelGrid.columns(width: 900, tile: 0, gap: 10), 1)
    }

    func testAPageHoldsAboutFortyChannelsInFullRows() {
        XCTAssertEqual(DeskChannelGrid.pageSize(columns: 1), 40)
        XCTAssertEqual(DeskChannelGrid.pageSize(columns: 2), 40)
        XCTAssertEqual(DeskChannelGrid.pageSize(columns: 3), 42)
        XCTAssertEqual(DeskChannelGrid.pageSize(columns: 4), 40)
        XCTAssertEqual(DeskChannelGrid.pageSize(columns: 6), 48)
        XCTAssertEqual(DeskChannelGrid.pageSize(columns: 0), 40)
        for columns in 1...6 { XCTAssertEqual(DeskChannelGrid.pageSize(columns: columns) % columns, 0) }
    }
}
