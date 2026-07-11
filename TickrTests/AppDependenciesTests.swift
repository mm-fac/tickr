import XCTest
import TickrCore
@testable import Tickr

/// Exercises the app-target launch-mode seam without launching the UI: the exact
/// `--ui-testing` opt-in versus the unchanged production path, and the isolated, offline
/// dependency graph the UI-testing launch selects. These tests never touch the Keychain,
/// the network, production Application Support, or `UserDefaults.standard`.
@MainActor
final class AppDependenciesTests: XCTestCase {

    // MARK: - Exact `--ui-testing` opt-in

    func testUITestingModeRequiresExactArgument() {
        XCTAssertEqual(LaunchMode(arguments: ["/path/Tickr", "--ui-testing"]), .uiTesting)
    }

    func testProductionIsTheDefaultAndAnyOtherArgumentStaysProduction() {
        XCTAssertEqual(LaunchMode(arguments: ["/path/Tickr"]), .production)
        // Only the exact token opts in — no prefix, suffix, or case variation.
        XCTAssertEqual(LaunchMode(arguments: ["/path/Tickr", "--ui-testingx"]), .production)
        XCTAssertEqual(LaunchMode(arguments: ["/path/Tickr", "-ui-testing"]), .production)
        XCTAssertEqual(LaunchMode(arguments: ["/path/Tickr", "--UI-TESTING"]), .production)
        XCTAssertEqual(LaunchMode(arguments: ["/path/Tickr", "--ui_testing"]), .production)
    }

    // MARK: - UI-testing dependency selection

    func testUITestingForcesOfflineMockProviders() {
        let deps = AppDependencies.make(mode: .uiTesting)
        // Forced offline mocks directly (not the key-routed providers), regardless of any
        // real Finnhub key.
        XCTAssertTrue(deps.quoteProvider is MockQuoteProvider)
        XCTAssertTrue(deps.candleProvider is PreviewCandleProvider)
        XCTAssertTrue(deps.searchProvider is MockSymbolSearchProvider)
    }

    func testUITestingUsesInMemorySecretStoreAndNeverKeychain() {
        let deps = AppDependencies.make(mode: .uiTesting)
        // Prove the graph selected the explicit in-memory secret store and did not
        // construct the Keychain-backed one.
        XCTAssertTrue(deps.secretStore is EphemeralSecretStore)
        XCTAssertFalse(deps.secretStore is KeychainSecretStore)
        // With an empty in-memory store the API key store starts with no key.
        XCTAssertNil(deps.apiKeyStore.apiKey)
        XCTAssertFalse(deps.apiKeyStore.hasKey)
    }

    func testUITestingFavoritesAreFreshEmptyAndTemporary() {
        let deps = AppDependencies.make(mode: .uiTesting)
        XCTAssertTrue(deps.favoritesStore.symbols.isEmpty)

        // The favorites file lives below the temporary directory, not Application Support.
        let tempPath = FileManager.default.temporaryDirectory.standardizedFileURL.path
        XCTAssertTrue(
            deps.favoritesURL.standardizedFileURL.path.hasPrefix(tempPath),
            "favorites should be under the temporary directory, got \(deps.favoritesURL.path)"
        )
    }

    func testUITestingFavoritesLocationIsUniquePerLaunch() {
        let first = AppDependencies.make(mode: .uiTesting)
        let second = AppDependencies.make(mode: .uiTesting)
        XCTAssertNotEqual(first.favoritesURL, second.favoritesURL)
    }

    func testUITestingThemeStartsAtSystemWithIsolatedPersistence() {
        let deps = AppDependencies.make(mode: .uiTesting)
        // Isolated theme persistence that starts at `system`.
        XCTAssertEqual(deps.themeStore.selected.id, "system")

        // Selecting a theme updates the in-memory store; a second UI-testing launch still
        // starts fresh at `system`, proving persistence is isolated and reset per launch
        // (never shared through `UserDefaults.standard`).
        deps.themeStore.select(OceanTheme())
        XCTAssertEqual(deps.themeStore.selected.id, "ocean")
        XCTAssertEqual(AppDependencies.make(mode: .uiTesting).themeStore.selected.id, "system")
    }
}

/// Focused checks on the in-memory secret store used by the UI-testing launch, proving it
/// starts empty and holds secrets only in memory (never via the Keychain).
final class EphemeralSecretStoreTests: XCTestCase {
    private let account = "finnhub"

    func testStartsEmpty() throws {
        let store = EphemeralSecretStore()
        XCTAssertNil(try store.secret(for: account))
    }

    func testRoundTripsInMemory() throws {
        let store = EphemeralSecretStore()
        try store.setSecret("k", for: account)
        XCTAssertEqual(try store.secret(for: account), "k")

        try store.setSecret(nil, for: account)
        XCTAssertNil(try store.secret(for: account))
    }

    func testEachInstanceIsIsolated() throws {
        let first = EphemeralSecretStore()
        try first.setSecret("k", for: account)
        // A separate instance does not see the other's in-memory value: nothing persists.
        XCTAssertNil(try EphemeralSecretStore().secret(for: account))
    }
}

/// Focused checks on the isolated theme persistence type, proving it holds a selection in
/// memory without any `UserDefaults` involvement.
@MainActor
final class InMemoryThemeDefaultsTests: XCTestCase {
    func testStartsEmptyAndRoundTrips() {
        let defaults = InMemoryThemeDefaults()
        XCTAssertNil(defaults.themeID(forKey: "selectedThemeID"))

        let store = ThemeStore(defaults: defaults)
        XCTAssertEqual(store.selected.id, BuiltInTheme.fallback.id)

        store.select(OceanTheme())
        XCTAssertEqual(defaults.themeID(forKey: "selectedThemeID"), "ocean")

        // A fresh store over the same isolated defaults resolves the persisted theme back.
        XCTAssertEqual(ThemeStore(defaults: defaults).selected.id, "ocean")
    }
}
