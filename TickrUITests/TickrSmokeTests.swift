import XCTest

/// One deterministic end-to-end smoke over Tickr's primary journey:
/// launch → search `AAPL` → add to favorites → clear search → open the AAPL detail and
/// assert the chart → open Settings / Appearance → switch the theme from System to Ocean.
///
/// The app is launched with the single `--ui-testing` argument, which forces the offline
/// mock providers and fully isolated, empty test state, so this journey is deterministic
/// and makes no network request. Every asynchronous transition (debounced search, sidebar
/// reload, chart load, Settings presentation, theme selection) is awaited with
/// `waitForExistence(timeout:)` or an XCTest predicate expectation — never a fixed delay,
/// element index, or localized display string. `continueAfterFailure` is off so the journey
/// stops at its first broken assumption instead of cascading into confusing follow-on
/// failures.
final class TickrSmokeTests: XCTestCase {

    /// Generous upper bound; each transition resolves as soon as its element/value appears.
    private let timeout: TimeInterval = 30

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testPrimaryJourney() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()

        // 1. Launch → the sidebar search field is present. Queried as a real search field
        // (the native `NSSearchField` behind `.searchable`, tagged by an AppKit bridge), not
        // through a generic any-element lookup.
        let searchField = app.searchFields["sidebar.search"]
        XCTAssertTrue(searchField.waitForExistence(timeout: timeout), "sidebar.search never appeared")

        // 2. Search AAPL → wait for its result → add it → clear the field.
        searchField.click()
        searchField.typeText("AAPL")

        let result = container(app, "search.result.AAPL")
        XCTAssertTrue(result.waitForExistence(timeout: timeout), "search.result.AAPL never appeared")

        let addFavorite = app.buttons["search.addFavorite.AAPL"]
        XCTAssertTrue(addFavorite.waitForExistence(timeout: timeout), "search.addFavorite.AAPL never appeared")
        addFavorite.click()

        clear(searchField)

        // 3. Favorites list shows AAPL → open its detail → the chart rendered.
        let favoriteRow = app.buttons["favorites.row.AAPL"]
        XCTAssertTrue(favoriteRow.waitForExistence(timeout: timeout), "favorites.row.AAPL never appeared")
        favoriteRow.click()

        let chart = container(app, "detail.chart")
        XCTAssertTrue(chart.waitForExistence(timeout: timeout), "detail.chart never appeared")

        // 4. Settings via ⌘, → Appearance tab → select Ocean → picker value becomes ocean.
        app.typeKey(",", modifierFlags: .command)

        let appearanceTab = app.radioButtons["settings.appearanceTab"]
        XCTAssertTrue(appearanceTab.waitForExistence(timeout: timeout), "settings.appearanceTab never appeared")
        appearanceTab.click()

        let themePicker = container(app, "settings.themePicker")
        XCTAssertTrue(themePicker.waitForExistence(timeout: timeout), "settings.themePicker never appeared")
        // Assert semantic state, not pixel color: the picker starts at System…
        wait(for: [expectValue(themePicker, "system")], timeout: timeout)

        let oceanRow = app.radioButtons["settings.theme.ocean"]
        XCTAssertTrue(oceanRow.waitForExistence(timeout: timeout), "settings.theme.ocean never appeared")
        oceanRow.click()

        // …and reports Ocean once selected.
        wait(for: [expectValue(themePicker, "ocean")], timeout: timeout)
    }

    // MARK: - Helpers

    /// Resolves an element by its exact, non-localized accessibility identifier without
    /// assuming a specific element type. Used for SwiftUI accessibility *containers* (built
    /// with `.accessibilityElement(children: .contain)`, or the semantic native Picker
    /// container whose generated AppKit role is not part of the app's contract). Every
    /// interactive control above is queried by its real role: search field, button, or
    /// native radio button.
    private func container(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    /// Clear a text field deterministically: focus it, select all, delete — no localized
    /// clear-button title and no fixed delay.
    private func clear(_ field: XCUIElement) {
        field.click()
        field.typeKey("a", modifierFlags: .command)
        field.typeKey(.delete, modifierFlags: [])
    }

    /// A predicate expectation that resolves when `element`'s accessibility value equals
    /// `value` — used to await theme-selection state without polling or fixed delays.
    private func expectValue(_ element: XCUIElement, _ value: String) -> XCTestExpectation {
        XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", value),
            object: element
        )
    }
}
