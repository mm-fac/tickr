import XCTest
import TickrCore
@testable import Tickr

final class AppLaunchModeTests: XCTestCase {
    func testExactUITestingFlagEnablesUITestingMode() {
        XCTAssertEqual(AppLaunchMode(arguments: ["/path/Tickr", "--ui-testing"]), .uiTesting)
    }

    func testNoFlagIsProduction() {
        XCTAssertEqual(AppLaunchMode(arguments: ["/path/Tickr"]), .production)
        XCTAssertEqual(AppLaunchMode(arguments: []), .production)
    }

    func testSimilarButInexactArgumentsStayProduction() {
        XCTAssertEqual(AppLaunchMode(arguments: ["/path/Tickr", "--ui-testing-extra"]), .production)
        XCTAssertEqual(AppLaunchMode(arguments: ["/path/Tickr", "-ui-testing"]), .production)
        XCTAssertEqual(AppLaunchMode(arguments: ["/path/Tickr", "--UI-TESTING"]), .production)
        XCTAssertEqual(AppLaunchMode(arguments: ["/path/Tickr", "ui-testing"]), .production)
    }
}

@MainActor
final class AppDependenciesTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        // A private subdirectory of the real temp directory: the contract under test.
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppDependenciesTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
        temporaryDirectory = nil
        try super.tearDownWithError()
    }

    func testUITestingModeForcesMockAndInMemoryDependencies() {
        let dependencies = AppDependencies(mode: .uiTesting, temporaryDirectory: temporaryDirectory)

        XCTAssertTrue(dependencies.quoteProvider is MockQuoteProvider)
        XCTAssertTrue(dependencies.candleProvider is PreviewCandleProvider)
        XCTAssertTrue(dependencies.searchProvider is MockSymbolSearchProvider)

        // Proves the graph selected the explicit in-memory secret store, not merely that
        // APIKeyStore started empty (which an empty Keychain-backed store would also do).
        XCTAssertTrue(dependencies.secretStore is EphemeralSecretStore)
        XCTAssertFalse(dependencies.secretStore is KeychainSecretStore)
        XCTAssertFalse(dependencies.apiKeyStore.hasKey)
    }

    func testUITestingModeStartsWithEmptyFavoritesBelowTemporaryDirectory() {
        let dependencies = AppDependencies(mode: .uiTesting, temporaryDirectory: temporaryDirectory)
        XCTAssertTrue(dependencies.favoritesStore.symbols.isEmpty)

        let url = AppDependencies.uiTestingFavoritesURL(temporaryDirectory: temporaryDirectory)
        XCTAssertTrue(url.path.hasPrefix(temporaryDirectory.path))
    }

    func testUITestingFavoritesURLIsFreshEveryCall() {
        let first = AppDependencies.uiTestingFavoritesURL(temporaryDirectory: temporaryDirectory)
        let second = AppDependencies.uiTestingFavoritesURL(temporaryDirectory: temporaryDirectory)
        XCTAssertNotEqual(first, second)
    }

    func testUITestingModeStartsAtSystemTheme() {
        let dependencies = AppDependencies(mode: .uiTesting, temporaryDirectory: temporaryDirectory)
        XCTAssertEqual(dependencies.themeStore.selected.id, "system")
        XCTAssertEqual(dependencies.themeStore.selected.id, BuiltInTheme.fallback.id)
    }

    func testUITestingThemeDefaultsStartFreshEveryCall() {
        // Each launch's theme persistence must be its own isolated, empty suite — never
        // a previous launch's state and never `UserDefaults.standard`.
        XCTAssertNil(AppDependencies.uiTestingThemeDefaults().string(forKey: "selectedThemeID"))
        XCTAssertNil(AppDependencies.uiTestingThemeDefaults().string(forKey: "selectedThemeID"))
    }
}
