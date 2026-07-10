import XCTest
import TickrCore
@testable import Tickr

/// Unit coverage for the launch-mode seam: exact `--ui-testing` opt-in versus the unchanged
/// production path, and the fully isolated dependency graph the flag selects. These tests
/// never touch the Keychain, the network, production Application Support, or
/// `UserDefaults.standard` — they only construct the in-memory / temporary UI-testing graph
/// and type-check the (inert) production selectors.
@MainActor
final class AppDependenciesTests: XCTestCase {

    // MARK: - Exact opt-in

    func testUITestingFlagOptsIn() {
        XCTAssertEqual(LaunchMode(arguments: ["Tickr", "--ui-testing"]), .uiTesting)
    }

    func testUITestingFlagDetectedAmongOtherArguments() {
        let args = ["Tickr", "-NSDocumentRevisionsDebugMode", "YES", "--ui-testing", "extra"]
        XCTAssertEqual(LaunchMode(arguments: args), .uiTesting)
    }

    func testNoArgumentsIsProduction() {
        XCTAssertEqual(LaunchMode(arguments: ["Tickr"]), .production)
        XCTAssertEqual(LaunchMode(arguments: []), .production)
    }

    func testOnlyExactFlagOptsIn() {
        // Near-misses must NOT enable UI-testing mode — a normal launch stays production.
        XCTAssertEqual(LaunchMode(arguments: ["Tickr", "--UI-Testing"]), .production)
        XCTAssertEqual(LaunchMode(arguments: ["Tickr", "--ui-testing=1"]), .production)
        XCTAssertEqual(LaunchMode(arguments: ["Tickr", "--ui-testingx"]), .production)
        XCTAssertEqual(LaunchMode(arguments: ["Tickr", "ui-testing"]), .production)
    }

    // MARK: - Production selection (side-effect-free: no Keychain access happens here)

    func testProductionSelectsKeychainSecretStore() {
        let store = AppDependencies.makeSecretStore(for: .production)
        XCTAssertTrue(store is KeychainSecretStore)
        XCTAssertFalse(store is EphemeralSecretStore)
    }

    func testUITestingSelectsEphemeralSecretStore() {
        let store = AppDependencies.makeSecretStore(for: .uiTesting)
        XCTAssertTrue(store is EphemeralSecretStore)
        XCTAssertFalse(store is KeychainSecretStore)
    }

    func testUITestingSelectsInMemoryThemeDefaults() {
        let defaults = AppDependencies.makeThemeDefaults(for: .uiTesting)
        XCTAssertTrue(defaults is InMemoryThemeDefaults)
    }

    // MARK: - UI-testing graph isolation

    func testUITestingForcesMockAndInMemoryDependencies() {
        let deps = AppDependencies.make(launchMode: .uiTesting)

        // Forced offline mocks, regardless of any real key.
        XCTAssertTrue(deps.quoteProvider is MockQuoteProvider)
        XCTAssertTrue(deps.candleProvider is PreviewCandleProvider)
        XCTAssertTrue(deps.searchProvider is MockSymbolSearchProvider)

        // In-memory secret store, never the Keychain-backed one. This proves the graph
        // selected the ephemeral store (an empty Keychain-backed store would also start
        // empty, so an emptiness check alone is not sufficient).
        XCTAssertTrue(deps.secretStore is EphemeralSecretStore)
        XCTAssertFalse(deps.secretStore is KeychainSecretStore)

        // Isolated theme persistence, never standard defaults.
        XCTAssertTrue(deps.themeDefaults is InMemoryThemeDefaults)
    }

    func testUITestingStartsWithNoApiKey() {
        let deps = AppDependencies.make(launchMode: .uiTesting)
        XCTAssertNil(deps.apiKeyStore.apiKey)
        XCTAssertFalse(deps.apiKeyStore.hasKey)
    }

    func testUITestingFavoritesStartEmptyUnderTemporaryDirectory() {
        let deps = AppDependencies.make(launchMode: .uiTesting)

        XCTAssertTrue(deps.favoritesStore.symbols.isEmpty)

        let tempPath = FileManager.default.temporaryDirectory.standardizedFileURL.path
        XCTAssertTrue(
            deps.favoritesFileURL.standardizedFileURL.path.hasPrefix(tempPath),
            "favorites must persist below the temporary directory, was \(deps.favoritesFileURL.path)"
        )
        // Nothing has been written yet: the fresh location does not exist on disk.
        XCTAssertFalse(FileManager.default.fileExists(atPath: deps.favoritesFileURL.path))
    }

    func testUITestingFavoritesLocationIsFreshPerLaunch() {
        let first = AppDependencies.make(launchMode: .uiTesting)
        let second = AppDependencies.make(launchMode: .uiTesting)
        XCTAssertNotEqual(first.favoritesFileURL, second.favoritesFileURL)
    }

    func testUITestingThemeStartsAtSystem() {
        let deps = AppDependencies.make(launchMode: .uiTesting)
        XCTAssertEqual(deps.themeStore.selected.id, "system")
    }

    func testUITestingThemeSelectionWritesOnlyToInjectedInMemoryDefaults() throws {
        let deps = AppDependencies.make(launchMode: .uiTesting)
        let inMemory = try XCTUnwrap(deps.themeDefaults as? InMemoryThemeDefaults)

        deps.themeStore.select(OceanTheme())

        XCTAssertEqual(deps.themeStore.selected.id, "ocean")
        // The write landed in the isolated in-memory defaults, not any UserDefaults suite.
        XCTAssertEqual(inMemory.themeID(forKey: "selectedThemeID"), "ocean")
    }
}
