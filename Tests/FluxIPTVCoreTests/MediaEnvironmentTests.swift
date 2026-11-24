import XCTest
import Foundation
@testable import FluxIPTVCore

final class MediaEnvironmentTests: XCTestCase {
    private func withDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
        let name = "FluxIPTV.Tests.MediaEnvironment.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        try body(defaults)
    }

    func testEveryCategoryKeepsItsOwnPlaceAndResourceNamespace() throws {
        XCTAssertEqual(MediaEnvironment(kind: .movie), .cinema)
        XCTAssertEqual(MediaEnvironment(kind: .series), .videoClub)
        XCTAssertEqual(MediaEnvironment(kind: .live), .livingRoom)
        var names = Set<String>()
        for environment in MediaEnvironment.allCases {
            XCTAssertEqual(MediaEnvironment(kind: environment.kind), environment)
            XCTAssertEqual(try JSONDecoder().decode(MediaEnvironment.self, from: JSONEncoder().encode(environment)), environment)
            for theme in VideoClubTheme.allCases {
                let name = environment.assetName(theme: theme)
                XCTAssertEqual(name, "\(environment.rawValue)-\(theme.rawValue)")
                XCTAssertTrue(names.insert(name).inserted)
                XCTAssertFalse(name.contains("/"))
            }
        }
        XCTAssertEqual(names.count, 18)
        XCTAssertEqual(Set(IPTVMediaKind.allCases.map(MediaThemePreferences.key(for:))).count, 3)
    }

    func testLegacyClubThemeMigratesToFilmAndSeriesWhileTVRemainsIndependent() {
        withDefaults { defaults in
            defaults.set("artDeco", forKey: MediaThemePreferences.legacyClubKey)
            defaults.set("midnight", forKey: MediaThemePreferences.tvKey)
            defaults.set("keep-me", forKey: "unrelated")
            MediaThemePreferences.migrateLegacy(in: defaults)
            XCTAssertEqual(MediaThemePreferences.theme(for: .movie, in: defaults), .artDeco)
            XCTAssertEqual(MediaThemePreferences.theme(for: .series, in: defaults), .artDeco)
            XCTAssertEqual(MediaThemePreferences.theme(for: .live, in: defaults), .midnight)
            XCTAssertEqual(defaults.string(forKey: MediaThemePreferences.legacyClubKey), "artDeco")
            XCTAssertEqual(defaults.string(forKey: "unrelated"), "keep-me")
        }
    }

    func testMigrationPreservesAnAlreadySelectedThemeAndIsIdempotent() {
        withDefaults { defaults in
            defaults.set("vintage70", forKey: MediaThemePreferences.legacyClubKey)
            defaults.set("future", forKey: MediaThemePreferences.cinemaKey)
            MediaThemePreferences.migrateLegacy(in: defaults)
            XCTAssertEqual(MediaThemePreferences.theme(for: .movie, in: defaults), .future)
            XCTAssertEqual(MediaThemePreferences.theme(for: .series, in: defaults), .vintage70)
            defaults.set("zen", forKey: MediaThemePreferences.seriesKey)
            defaults.set("midnight", forKey: MediaThemePreferences.legacyClubKey)
            MediaThemePreferences.migrateLegacy(in: defaults)
            XCTAssertEqual(MediaThemePreferences.theme(for: .movie, in: defaults), .future)
            XCTAssertEqual(MediaThemePreferences.theme(for: .series, in: defaults), .zen)
            XCTAssertEqual(MediaThemePreferences.theme(for: .live, in: defaults), .neo90)
        }
    }

    func testCategorySelectionNeverWritesAnotherCategory() {
        withDefaults { defaults in
            MediaThemePreferences.migrateLegacy(in: defaults)
            defaults.set("future", forKey: MediaThemePreferences.key(for: .movie))
            XCTAssertEqual(MediaThemePreferences.theme(for: .movie, in: defaults), .future)
            XCTAssertEqual(MediaThemePreferences.theme(for: .series, in: defaults), .neo90)
            XCTAssertEqual(MediaThemePreferences.theme(for: .live, in: defaults), .neo90)
            defaults.set("zen", forKey: MediaThemePreferences.key(for: .live))
            XCTAssertEqual(MediaThemePreferences.theme(for: .live, in: defaults), .zen)
            XCTAssertEqual(MediaThemePreferences.theme(for: .movie, in: defaults), .future)
        }
    }

    func testUnknownValuesFallBackWithoutErasingStoredPreferences() {
        withDefaults { defaults in
            defaults.set("theme-from-a-future-version", forKey: MediaThemePreferences.legacyClubKey)
            defaults.set("unknown-cinema", forKey: MediaThemePreferences.cinemaKey)
            defaults.set(42, forKey: MediaThemePreferences.tvKey)
            MediaThemePreferences.migrateLegacy(in: defaults)
            for kind in IPTVMediaKind.allCases {
                XCTAssertEqual(MediaThemePreferences.theme(for: kind, in: defaults), .neo90)
            }
            XCTAssertEqual(defaults.string(forKey: MediaThemePreferences.cinemaKey), "unknown-cinema")
            XCTAssertEqual(defaults.integer(forKey: MediaThemePreferences.tvKey), 42)
            XCTAssertEqual(defaults.string(forKey: MediaThemePreferences.legacyClubKey), "theme-from-a-future-version")
        }
    }

    func testReadBeforeMigrationUsesLegacyThemeOnlyForFilmsAndSeries() {
        withDefaults { defaults in
            defaults.set("vintage70", forKey: MediaThemePreferences.legacyClubKey)
            XCTAssertEqual(MediaThemePreferences.theme(for: .movie, in: defaults), .vintage70)
            XCTAssertEqual(MediaThemePreferences.theme(for: .series, in: defaults), .vintage70)
            XCTAssertEqual(MediaThemePreferences.theme(for: .live, in: defaults), .neo90)
            XCTAssertNil(defaults.object(forKey: MediaThemePreferences.cinemaKey))
            XCTAssertNil(defaults.object(forKey: MediaThemePreferences.seriesKey))
        }
    }
}
