import XCTest

/// One deterministic end-to-end smoke over Tickr's primary journey:
/// launch → search `AAPL` → add it to favorites (forced offline mocks) → clear search →
/// open the AAPL detail → assert the chart → open Settings / Appearance → switch the theme
/// from System to Ocean.
///
/// The app is launched with the single `--ui-testing` argument, which selects a fully
/// isolated, offline dependency graph (forced mocks, in-memory secret store, fresh
/// temporary favorites, isolated System-theme persistence). Every asynchronous transition
/// is awaited with `waitForExistence`/predicate expectations — no sleeps, fixed delays,
/// element indexes, or localized display strings.
final class TickrSmokeTests: XCTestCase {
    private let timeout: TimeInterval = 30

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testPrimaryJourney() {
        // 1. Launch in the deterministic UI-testing mode and wait for the sidebar search.
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()

        let searchField = app.searchFields["sidebar.search"]
        XCTAssertTrue(searchField.waitForExistence(timeout: timeout), "sidebar search field never appeared")

        // 2. Search AAPL, add it to favorites, then clear the search field.
        searchField.click()
        searchField.typeText("AAPL")

        let result = element(app, "search.result.AAPL")
        XCTAssertTrue(result.waitForExistence(timeout: timeout), "AAPL search result never appeared")

        let addFavorite = app.buttons["search.addFavorite.AAPL"]
        XCTAssertTrue(addFavorite.waitForExistence(timeout: timeout), "add-to-favorites button never appeared")
        addFavorite.click()

        // Clear the field (select-all + delete) so the sidebar returns to the favorites list.
        searchField.click()
        searchField.typeKey("a", modifierFlags: .command)
        searchField.typeKey(.delete, modifierFlags: [])

        // 3. Open the AAPL favorite and assert its chart renders.
        let favoriteRow = element(app, "favorites.row.AAPL")
        XCTAssertTrue(favoriteRow.waitForExistence(timeout: timeout), "AAPL favorite row never appeared")
        favoriteRow.click()

        let chart = element(app, "detail.chart")
        XCTAssertTrue(chart.waitForExistence(timeout: timeout), "detail chart never appeared")

        // 4. Open Settings via Command-, (no localized menu title), switch to Appearance,
        //    and change the theme from System to Ocean.
        app.typeKey(",", modifierFlags: .command)

        let appearanceTab = element(app, "settings.appearanceTab")
        XCTAssertTrue(appearanceTab.waitForExistence(timeout: timeout), "Appearance tab never appeared")
        appearanceTab.click()

        let picker = element(app, "settings.themePicker")
        XCTAssertTrue(picker.waitForExistence(timeout: timeout), "theme picker never appeared")
        // The picker starts on the System theme...
        expectValue("system", of: picker, message: "theme picker did not start on system")

        let ocean = element(app, "settings.theme.ocean")
        XCTAssertTrue(ocean.waitForExistence(timeout: timeout), "Ocean theme option never appeared")
        ocean.click()

        // ...and reports Ocean after selection.
        expectValue("ocean", of: picker, message: "theme picker did not switch to ocean")
    }

    // MARK: - Helpers

    /// Resolves the single element carrying `identifier`, regardless of its resolved type.
    /// Every required identifier is attached to exactly one element, so a subscript by
    /// identifier (not by index) addresses it unambiguously.
    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    /// Waits until `element` exposes accessibility `value`, driving on semantic state
    /// rather than pixel color.
    private func expectValue(_ value: String, of element: XCUIElement, message: String) {
        let predicate = NSPredicate(format: "value == %@", value)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: timeout), .completed, message)
    }
}
