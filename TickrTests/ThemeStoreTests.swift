import XCTest
@testable import Tickr

@MainActor
final class ThemeStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        // A private suite keeps the round-trip off the app's real defaults.
        suiteName = "ThemeStoreTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        try super.tearDownWithError()
    }

    func testDefaultsToFallbackWhenNothingPersisted() {
        let store = ThemeStore(defaults: defaults)
        XCTAssertEqual(store.selected.id, BuiltInTheme.fallback.id)
    }

    func testSelectionPersistsAcrossStoreInstances() {
        let store = ThemeStore(defaults: defaults)
        store.select(OceanTheme())

        // A fresh store over the same defaults must resolve the same theme back.
        let reloaded = ThemeStore(defaults: defaults)
        XCTAssertEqual(reloaded.selected.id, OceanTheme().id)
    }

    func testEveryBuiltInThemeRoundTrips() {
        for theme in BuiltInTheme.all {
            let store = ThemeStore(defaults: defaults)
            store.select(theme)
            let reloaded = ThemeStore(defaults: defaults)
            XCTAssertEqual(reloaded.selected.id, theme.id, "\(theme.name) did not round-trip")
        }
    }

    func testUnknownPersistedIDFallsBack() {
        defaults.set("no-such-theme", forKey: "selectedThemeID")
        let store = ThemeStore(defaults: defaults)
        XCTAssertEqual(store.selected.id, BuiltInTheme.fallback.id)
    }

    func testBuiltInLookupResolvesEachThemeAndFallsBack() {
        XCTAssertEqual(BuiltInTheme.all.count, 4)
        XCTAssertEqual(Set(BuiltInTheme.all.map(\.id)).count, 4, "theme ids must be unique")
        for theme in BuiltInTheme.all {
            XCTAssertEqual(BuiltInTheme.theme(id: theme.id).id, theme.id)
        }
        XCTAssertEqual(BuiltInTheme.theme(id: "bogus").id, BuiltInTheme.fallback.id)
    }
}
