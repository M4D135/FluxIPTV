import XCTest
@testable import FluxIPTVCore

final class LiveTVNavigationTests: XCTestCase {
    private func channels(_ count: Int) -> CatalogSlice {
        let source = UUID()
        return CatalogSlice((0..<count).map { index in
            IPTVItem(id: "channel-\(index)", sourceID: source, name: "Chaîne \(index)", group: "France",
                     logoURL: nil, kind: .live, directURL: nil, xtreamStreamID: String(index), fileExtension: "m3u8")
        })
    }
    func testLeftEdgeReturnsToSelectedCategoryAndRightEntersChannels() {
        let slice = channels(120), sidebar = ["all", "favorites", "sports"]
        XCTAssertEqual(LiveTVNavigation.move(from: "channel-6", action: .left, channels: slice, columns: 3, sidebarIDs: sidebar, preferredSidebarID: "sports", prefix: [["header"]]), "sports")
        XCTAssertEqual(LiveTVNavigation.move(from: "sports", action: .right, channels: slice, columns: 3, sidebarIDs: sidebar, preferredSidebarID: "sports", prefix: [["header"]]), "channel-0")
        XCTAssertEqual(LiveTVNavigation.move(from: "sports", action: .right, channels: slice, columns: 3, sidebarIDs: sidebar, preferredSidebarID: "sports", preferredChannelID: "channel-6", prefix: [["header"]]), "channel-6")
        XCTAssertEqual(LiveTVNavigation.move(from: "channel-7", action: .left, channels: slice, columns: 3, sidebarIDs: sidebar, preferredSidebarID: "sports", prefix: []), "channel-6")
    }
    func testSidebarBoundariesAndEmptyChannelsRemainNavigable() {
        let slice = CatalogSlice(), sidebar = ["all", "favorites"]
        func move(_ from: String, _ action: RemoteAction) -> String? {
            LiveTVNavigation.move(from: from, action: action, channels: slice, columns: 1, sidebarIDs: sidebar, preferredSidebarID: nil, prefix: [["tab-live"], ["reload"]])
        }
        XCTAssertEqual(move("all", .down), "favorites")
        XCTAssertEqual(move("favorites", .down), "favorites")
        XCTAssertEqual(move("favorites", .up), "all")
        XCTAssertEqual(move("all", .up), "reload")
        XCTAssertEqual(move("favorites", .right), "reload")
    }
    func testCompactLayoutRetainsIndexedNavigationAcrossPageBoundaries() {
        let slice = channels(24_000)
        XCTAssertEqual(LiveTVNavigation.move(from: "channel-35", action: .down, channels: slice, columns: 3, sidebarIDs: [], preferredSidebarID: nil, prefix: [["reload"]]), "channel-38")
        XCTAssertEqual(LiveTVNavigation.move(from: "channel-23", action: .down, channels: slice, columns: 1, sidebarIDs: [], preferredSidebarID: nil, prefix: []), "channel-24")
        XCTAssertEqual(LiveTVNavigation.move(from: "channel-23", action: .left, channels: slice, columns: 1, sidebarIDs: [], preferredSidebarID: nil, prefix: []), "channel-23")
    }
    func testTVPreviewDelayIsIndependentFromMovieTrailerPreferences() {
        XCTAssertEqual(LiveTVPreviewDelay.allCases.map(\.rawValue), [1, 3, 5, 10])
        XCTAssertEqual(LiveTVPreviewDelay.defaultValue, .one)
        XCTAssertNotEqual(LiveTVPreviewDelay.storageKey, TrailerPreviewDelay.storageKey)
        XCTAssertNotEqual(LiveTVPreviewDelay.automaticKey, TrailerPreviewDelay.automaticKey)
    }
}
