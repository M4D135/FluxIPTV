import XCTest

/// These tests only observe accessibility state. Every navigation/activation
/// comes from XCUIRemote, through the real tvOS focus engine and production UI.
final class TVRemoteNavigationTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testCountryChangeReopenAndMenuPreservesSelection() {
        let app = launch("live-fr")
        defer { app.terminate() }
        let firstFrance = element("live-channel-fixture-country-fr-0", in: app)
        let countries = element("navigation-countries", in: app)
        let france = element("live-country-option-FR", in: app)
        let spain = element("live-country-option-ES", in: app)
        assertFocus(firstFrance, logical: "fixture-country-fr-0", in: app)

        XCUIRemote.shared.press(.up)
        assertCondition("hasFocus == false", on: firstFrance, in: app)
        move(.left, to: countries, maximumPresses: 6, in: app)
        assertFocus(countries, logical: "countries", in: app)
        XCUIRemote.shared.press(.select)
        assertFocus(france, in: app)
        XCTAssertTrue((france.value as? String ?? "").contains("sélectionné"))
        retainScreenshot("country-01-picker-france-focused", in: app)

        XCUIRemote.shared.press(.up)
        assertFocus(spain, in: app)
        XCUIRemote.shared.press(.select)
        assertCondition("exists == false", on: spain, in: app)
        assertSpanishResults(in: app)
        assertFocus(countries, logical: "countries", in: app)
        retainScreenshot("country-02-spain-results", in: app)
        print("PASS: TV_REMOTE country FR -> ES through Up and Select")

        XCUIRemote.shared.press(.select)
        assertFocus(spain, in: app)
        XCTAssertTrue((spain.value as? String ?? "").contains("sélectionné"))
        XCTAssertFalse((france.value as? String ?? "").contains("sélectionné"))
        retainScreenshot("country-03-reopened-spain-focused", in: app)
        XCUIRemote.shared.press(.down)
        assertFocus(france, in: app)
        // Moving the highlight is not selecting a country. Menu must cancel.
        retainScreenshot("country-04-france-highlight-before-menu", in: app)
        XCUIRemote.shared.press(.menu)
        assertCondition("exists == false", on: france, in: app)
        assertSpanishResults(in: app)
        assertFocus(countries, logical: "countries", in: app)
        retainScreenshot("country-05-menu-preserved-spain", in: app)
        print("PASS: TV_REMOTE reopened ES, moved to FR, Menu preserved ES and returned focus to Pays")

        // Returning to the top-level tab must preserve the catalogue's view
        // identity; the next Menu belongs to tvOS when no Back action remains.
        let liveTab = element("navigation-tab-live", in: app)
        XCUIRemote.shared.press(.menu)
        assertFocus(liveTab, logical: "tab-live", in: app)
        XCUIRemote.shared.press(.menu)
        // A crash/termination is not evidence that tvOS received Menu.
        assertCondition(NSPredicate(format: "state == %lu OR state == %lu",
                                    XCUIApplication.State.runningBackground.rawValue,
                                    XCUIApplication.State.runningBackgroundSuspended.rawValue),
                        on: app, in: app)
        print("PASS: TV_REMOTE Menu returned to TV, then Menu backgrounded the app without terminating it")
    }

    @MainActor
    func testRestoredChannelCanLoseAndRegainRemoteFocus() {
        let app = launch("live-restored")
        defer { app.terminate() }
        let channel = element("live-channel-fixture-country-fr-1", in: app)
        let countries = element("navigation-countries", in: app)
        assertFocus(channel, logical: "fixture-country-fr-1", in: app)
        retainScreenshot("restored-01-remembered-channel", in: app)

        XCUIRemote.shared.press(.up)
        assertCondition("hasFocus == false", on: channel, in: app)
        move(.left, to: countries, maximumPresses: 6, in: app)
        assertFocus(countries, logical: "countries", in: app)
        retainScreenshot("restored-02-focus-away-on-pays", in: app)
        XCUIRemote.shared.press(.down)
        assertFocus(channel, logical: "fixture-country-fr-1", in: app)
        XCTAssertEqual(countries.label, "Pays : France · FR")
        XCTAssertTrue(app.textFields.matching(NSPredicate(format: "value == %@", "Grand écran")).firstMatch.exists)
        XCTAssertFalse(element("live-channel-fixture-country-fr-0", in: app).exists)
        retainScreenshot("restored-03-returned-to-remembered-channel", in: app)
        print("PASS: TV_REMOTE saved FR/Grand écran channel released native focus and accepted Down reentry")
    }

    @MainActor
    func testFailedSourceReconnectHighlightFollowsRemoteFocus() {
        let app = launch("live-error")
        defer { app.terminate() }
        let countries = element("navigation-countries", in: app)
        let reconnect = element("navigation-reconnect-source", in: app)
        assertFocus(countries, logical: "countries", in: app)
        XCTAssertTrue(reconnect.waitForExistence(timeout: 10))

        XCUIRemote.shared.press(.down)
        assertFocus(reconnect, logical: "reconnect-source", in: app)
        retainScreenshot("error-01-reconnect-native-and-logical-focus", in: app)
        XCUIRemote.shared.press(.up)
        assertFocus(countries, logical: "countries", in: app)
        XCTAssertFalse(reconnect.hasFocus)
        retainScreenshot("error-02-reconnect-highlight-released", in: app)
        XCUIRemote.shared.press(.down)
        assertFocus(reconnect, logical: "reconnect-source", in: app)
        retainScreenshot("error-03-reconnect-highlight-restored", in: app)
        print("PASS: TV_REMOTE failed source reconnect highlight followed native Down/Up/Down without a loaded catalogue")
    }

    @MainActor
    private func launch(_ scenario: String) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "com.m4d135.FluxIPTV.TVCatalogUISmoke")
        app.launchEnvironment["FLUX_UI_SCENARIO"] = scenario
        app.launchEnvironment["FLUX_UI_REMOTE_TESTING"] = "1"
        app.launch()
        XCTAssertTrue(element("flux-catalog-logical-focus", in: app).waitForExistence(timeout: 15))
        return app
    }

    @MainActor
    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    @MainActor
    private func assertFocus(_ control: XCUIElement, logical: String? = nil, in app: XCUIApplication,
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(control.waitForExistence(timeout: 10), file: file, line: line)
        assertCondition("hasFocus == true", on: control, in: app, file: file, line: line)
        if let logical {
            assertCondition(NSPredicate(format: "value == %@", logical),
                            on: element("flux-catalog-logical-focus", in: app), in: app, file: file, line: line)
        }
        print("TV_REMOTE focus: \(control.identifier), native=\(control.hasFocus), logical=\(logical ?? "picker-local"), frame=\(control.frame)")
    }

    @MainActor
    private func assertCondition(_ format: String, on control: XCUIElement, in app: XCUIApplication,
                                 file: StaticString = #filePath, line: UInt = #line) {
        assertCondition(NSPredicate(format: format), on: control, in: app, file: file, line: line)
    }

    @MainActor
    private func assertCondition(_ predicate: NSPredicate, on control: XCUIElement, in app: XCUIApplication,
                                 file: StaticString = #filePath, line: UInt = #line) {
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: control)
        let result = XCTWaiter.wait(for: [expectation], timeout: 10)
        if result != .completed {
            retainScreenshot("failure-\(control.identifier)", in: app)
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "failed-remote-navigation-accessibility-tree"
            tree.lifetime = .keepAlways
            add(tree)
        }
        XCTAssertEqual(result, .completed, "\(control.identifier): \(predicate.predicateFormat)", file: file, line: line)
    }

    @MainActor
    private func move(_ direction: XCUIRemote.Button, to target: XCUIElement, maximumPresses: Int,
                      in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        // Each press synchronizes with XCTest's UI idleness. A bounded row walk
        // tolerates the native engine landing on either neighbour above a tile.
        for _ in 0..<maximumPresses {
            if target.exists && target.hasFocus { return }
            XCUIRemote.shared.press(direction)
        }
        assertFocus(target, in: app, file: file, line: line)
    }

    @MainActor
    private func assertSpanishResults(in app: XCUIApplication) {
        assertCondition(NSPredicate(format: "label == %@", "Pays : Espagne · ES"),
                        on: element("navigation-countries", in: app), in: app)
        for index in 0..<2 {
            XCTAssertTrue(element("live-channel-fixture-country-es-\(index)", in: app).waitForExistence(timeout: 10))
        }
        for index in 0..<3 {
            assertCondition("exists == false", on: element("live-channel-fixture-country-fr-\(index)", in: app), in: app)
        }
    }

    @MainActor
    private func retainScreenshot(_ name: String, in app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
