import XCTest

/// One deterministic, offline smoke over Tickr's primary journey:
/// launch → search `AAPL` → add to favorites (forced mocks) → clear search → open the
/// AAPL detail → assert the chart → open Settings / Appearance → switch System → Ocean.
///
/// The app is launched with the single `--ui-testing` argument, which forces the offline
/// mock providers, an in-memory secret store, empty temporary favorites, and an isolated
/// `system` theme — so the run makes no network request and never touches production
/// state. Every asynchronous transition (debounced search, sidebar reload, chart load,
/// Settings presentation, theme selection) is awaited with `waitForExistence` or an
/// XCTest predicate expectation — no sleeps, fixed delays, element indices, or localized
/// display strings.
final class TickrSmokeTests: XCTestCase {
    private var app: XCUIApplication!
    private let timeout: TimeInterval = 15

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
        try super.tearDownWithError()
    }

    func testPrimaryJourney() throws {
        // 1. Launch → the sidebar search field is ready.
        let search = element("sidebar.search")
        XCTAssertTrue(search.waitForExistence(timeout: timeout), "sidebar search field should appear")

        // 2. Search AAPL, wait for the debounced result, add it, then clear the field.
        search.click()
        search.typeText("AAPL")

        let result = element("search.result.AAPL")
        XCTAssertTrue(result.waitForExistence(timeout: timeout), "AAPL search result should appear")

        let addFavorite = element("search.addFavorite.AAPL")
        XCTAssertTrue(addFavorite.waitForExistence(timeout: timeout), "AAPL add-favorite button should appear")
        addFavorite.click()

        // Clear the field by selecting all and deleting — no localized clear-button title.
        search.click()
        app.typeKey("a", modifierFlags: .command)
        app.typeKey(.delete, modifierFlags: [])

        // 3. The favorites row appears after the sidebar reload; open its detail and assert
        //    the chart renders.
        let favorite = element("favorites.row.AAPL")
        XCTAssertTrue(favorite.waitForExistence(timeout: timeout), "AAPL favorites row should appear")
        favorite.click()

        let chart = element("detail.chart")
        XCTAssertTrue(chart.waitForExistence(timeout: timeout), "AAPL detail chart should load")

        // 4. Open Settings with Command-, select the Appearance tab, and switch to Ocean.
        app.typeKey(",", modifierFlags: .command)

        let appearanceTab = element("settings.appearanceTab")
        XCTAssertTrue(appearanceTab.waitForExistence(timeout: timeout), "Appearance settings tab should appear")
        appearanceTab.click()

        let themePicker = element("settings.themePicker")
        XCTAssertTrue(themePicker.waitForExistence(timeout: timeout), "theme picker should appear")
        // The picker starts on `system` once the pane is presented.
        expect(themePicker, toHaveValue: "system")

        let ocean = element("settings.theme.ocean")
        XCTAssertTrue(ocean.waitForExistence(timeout: timeout), "Ocean theme option should appear")
        ocean.click()

        // The theme selection is asynchronous; wait until the picker reports `ocean`.
        expect(themePicker, toHaveValue: "ocean")
    }

    /// Element lookup by exact accessibility identifier, agnostic to the platform's element
    /// classification (search field vs button vs list row vs container), so the test
    /// asserts semantic identity rather than a specific element type.
    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    /// Wait until `element` exposes `value` as its accessibility value.
    private func expect(_ element: XCUIElement, toHaveValue value: String) {
        let predicate = NSPredicate(format: "value == %@", value)
        expectation(for: predicate, evaluatedWith: element)
        waitForExpectations(timeout: timeout)
    }
}
