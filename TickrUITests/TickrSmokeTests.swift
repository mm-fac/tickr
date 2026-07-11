import XCTest

/// One real, deterministic smoke covering Tickr's primary journey end to end: launch in
/// the `--ui-testing` launch mode (forced mocks, in-memory secrets, isolated favorites/
/// theme persistence — see `AppDependencies`), search, favorite, view the detail chart,
/// and switch the theme in Settings.
///
/// Every asynchronous transition (debounced search, sidebar reload, chart load, Settings
/// presentation, theme selection) is awaited with `waitForExistence(timeout:)` or an
/// `NSPredicate` expectation — never a fixed delay — and every element is looked up by
/// its exact, non-localized accessibility identifier.
final class TickrSmokeTests: XCTestCase {
    func testPrimaryJourney() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()

        let searchField = app.searchFields["sidebar.search"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 30), "sidebar.search never appeared")
        searchField.click()
        searchField.typeText("AAPL")

        let searchResult = app.descendants(matching: .any)["search.result.AAPL"]
        XCTAssertTrue(searchResult.waitForExistence(timeout: 30), "search.result.AAPL never appeared")

        let addFavorite = app.buttons["search.addFavorite.AAPL"]
        XCTAssertTrue(addFavorite.waitForExistence(timeout: 10), "search.addFavorite.AAPL never appeared")
        addFavorite.click()

        // Clear the search field (select all, delete) rather than depending on a
        // localized cancel-button label or element index.
        searchField.typeKey("a", modifierFlags: .command)
        searchField.typeKey(.delete, modifierFlags: [])

        let favoriteRow = app.buttons["favorites.row.AAPL"]
        XCTAssertTrue(favoriteRow.waitForExistence(timeout: 30), "favorites.row.AAPL never appeared")
        favoriteRow.click()

        let chart = app.descendants(matching: .any)["detail.chart"]
        XCTAssertTrue(chart.waitForExistence(timeout: 30), "detail.chart never appeared")

        // Open Settings by key equivalent, not a localized menu title.
        app.typeKey(",", modifierFlags: .command)

        let appearanceTab = app.radioButtons["settings.appearanceTab"]
        XCTAssertTrue(appearanceTab.waitForExistence(timeout: 30), "settings.appearanceTab never appeared")
        appearanceTab.click()

        let themePicker = app.descendants(matching: .any)["settings.themePicker"]
        XCTAssertTrue(themePicker.waitForExistence(timeout: 30), "settings.themePicker never appeared")
        XCTAssertEqual(themePicker.value as? String, "system")

        let oceanOption = app.radioButtons["settings.theme.ocean"]
        XCTAssertTrue(oceanOption.waitForExistence(timeout: 30), "settings.theme.ocean never appeared")
        oceanOption.click()

        let selectedOcean = NSPredicate(format: "value == %@", "ocean")
        let oceanExpectation = expectation(for: selectedOcean, evaluatedWith: themePicker, handler: nil)
        wait(for: [oceanExpectation], timeout: 10)
    }
}
