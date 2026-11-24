import XCTest
@testable import FluxIPTVCore
final class PlaybackSettingsTests: XCTestCase {
    func testProfilesAndOptions() {
        XCTAssertEqual(PlaybackSettings.Profile.fast.settings.cacheMS, 700)
        XCTAssertEqual(PlaybackSettings.Profile.stable.settings.nativeBufferSeconds, 5)
        var s = PlaybackSettings(); s.hardware = false; s.bitrateMbps = 8
        XCTAssertTrue(s.vlcOptions.contains(":avcodec-hw=none")); XCTAssertEqual(s.nativePeakBitrate, 8_000_000)
    }
    func testClampingAndPersistence() throws {
        var s = PlaybackSettings(); s.cacheMS = -1; s.retries = 200; s.skipSeconds = 999
        XCTAssertEqual(s.normalized.cacheMS, 250); XCTAssertEqual(s.normalized.retries, 5); XCTAssertEqual(s.normalized.skipSeconds, 120)
        XCTAssertEqual(try JSONDecoder().decode(PlaybackSettings.self, from: JSONEncoder().encode(s)), s)
    }
    func testReconnectOnlyLiveAndBounded() {
        var s = PlaybackSettings(); XCTAssertTrue(s.canReconnect(isLive: true, attempt: 0)); XCTAssertFalse(s.canReconnect(isLive: true, attempt: 2)); XCTAssertFalse(s.canReconnect(isLive: false, attempt: 0)); s.reconnectLive = false; XCTAssertFalse(s.canReconnect(isLive: true, attempt: 0))
    }
}
