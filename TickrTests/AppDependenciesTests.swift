import XCTest
import TickrCore
@testable import Tickr

/// Exercises the launch-mode seam without launching the UI: the exact `--ui-testing`
/// opt-in versus the unchanged production path, and the fully-isolated UI-testing graph
/// (forced mocks, in-memory secrets, fresh/empty favorites, isolated `system` theme).
///
/// These tests only ever construct the `--ui-testing` graph, never the production one, so
/// they never touch the Keychain, the network, production Application Support, or
/// `UserDefaults.standard`.
@MainActor
final class AppDependenciesTests: XCTestCase {

    // MARK: - Launch-mode detection (exact opt-in)

    func testProductionIsTheDefaultWithoutTheFlag() {
        XCTAssertEqual(LaunchMode(arguments: ["Tickr"]), .production)
        XCTAssertEqual(LaunchMode(arguments: []), .production)
    }

    func testUITestingRequiresTheExactFlag() {
        XCTAssertEqual(LaunchMode(arguments: ["Tickr", "--ui-testing"]), .uiTesting)
    }

    func testNearMissArgumentsStayOnProduction() {
        // Only the exact token opts in; prefixes, suffixes, and value forms do not.
        XCTAssertEqual(LaunchMode(arguments: ["Tickr", "--ui-testing=1"]), .production)
        XCTAssertEqual(LaunchMode(arguments: ["Tickr", "--ui-testing-mode"]), .production)
        XCTAssertEqual(LaunchMode(arguments: ["Tickr", "ui-testing"]), .production)
        XCTAssertEqual(LaunchMode(arguments: ["Tickr", "--UI-TESTING"]), .production)
    }

    func testMakeDispatchesToUITestingGraphOnTheFlag() {
        let deps = AppDependencies.make(arguments: ["Tickr", "--ui-testing"])
        XCTAssertEqual(deps.mode, .uiTesting)
    }

    // MARK: - Forced mock / in-memory dependency selection

    func testUITestingForcesOfflineMockProviders() {
        let deps = AppDependencies.uiTesting()
        XCTAssertTrue(deps.quoteProvider is MockQuoteProvider)
        XCTAssertTrue(deps.candleProvider is PreviewCandleProvider)
        XCTAssertTrue(deps.searchProvider is MockSymbolSearchProvider)
        // Crucially not the key-routing providers, so no live path and no key dependence.
        XCTAssertFalse(deps.quoteProvider is RoutingQuoteProvider)
        XCTAssertFalse(deps.candleProvider is RoutingCandleProvider)
        XCTAssertFalse(deps.searchProvider is RoutingSymbolSearchProvider)
    }

    func testUITestingKeyStoreStartsEmptyAndIsInMemory() {
        let deps = AppDependencies.uiTesting()
        // In-memory secret store, so no key is present and the Keychain is never read.
        XCTAssertNil(deps.apiKeyStore.apiKey)
        XCTAssertFalse(deps.apiKeyStore.hasKey)
    }

    func testUITestingProvidersAnswerFromMocksOffline() async throws {
        let deps = AppDependencies.uiTesting()
        // AAPL is present in every mock, proving the forced offline providers answer.
        let quote = try await deps.quoteProvider.quote(for: "AAPL")
        XCTAssertEqual(quote.symbol, "AAPL")
        let results = try await deps.searchProvider.search(matching: "AAPL")
        XCTAssertEqual(results.first?.symbol, "AAPL")
        let series = try await deps.candleProvider.candles(for: "AAPL", range: .day1)
        XCTAssertFalse(series.candles.isEmpty)
    }

    // MARK: - Fresh / empty favorites state

    func testUITestingFavoritesStartEmpty() {
        let deps = AppDependencies.uiTesting()
        XCTAssertTrue(deps.favoritesStore.symbols.isEmpty)
    }

    func testUITestingFavoritesAreFreshPerLaunch() throws {
        // Adding to one launch's favorites must not leak into the next launch's graph.
        let first = AppDependencies.uiTesting()
        try first.favoritesStore.add("TSLA")
        XCTAssertEqual(first.favoritesStore.symbols, ["TSLA"])

        let second = AppDependencies.uiTesting()
        XCTAssertTrue(second.favoritesStore.symbols.isEmpty)
    }

    // MARK: - Isolated System theme state

    func testUITestingThemeStartsOnSystem() {
        let deps = AppDependencies.uiTesting()
        XCTAssertEqual(deps.themeStore.selected.id, "system")
    }

    func testUITestingThemeSelectionIsIsolatedPerLaunch() {
        // Selecting a theme in one launch's isolated store must not bleed into another.
        let first = AppDependencies.uiTesting()
        first.themeStore.select(OceanTheme())
        XCTAssertEqual(first.themeStore.selected.id, "ocean")

        let second = AppDependencies.uiTesting()
        XCTAssertEqual(second.themeStore.selected.id, "system")
    }
}
