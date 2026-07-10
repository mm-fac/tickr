import Foundation
import TickrCore

/// Which dependency graph the app should build for this launch.
///
/// The default is ``production`` — the real Keychain, standard defaults, Application
/// Support favorites, and key-routing providers. ``uiTesting`` is opted into *only* by
/// the exact process argument ``uiTestingArgument``; any other argument (including a
/// prefix or suffix variant) leaves the app on the production path, so normal launches
/// stay behaviorally unchanged.
enum LaunchMode: Equatable {
    case production
    case uiTesting

    /// The one, exact argument that enables the deterministic UI-testing launch mode.
    static let uiTestingArgument = "--ui-testing"

    init(arguments: [String]) {
        self = arguments.contains(Self.uiTestingArgument) ? .uiTesting : .production
    }
}

/// The concrete stores and providers the app runs against, chosen once at launch from the
/// process arguments. Factoring selection into this seam lets unit tests exercise the
/// exact ``LaunchMode/uiTesting`` graph — forced mocks, in-memory secrets, fresh favorites,
/// isolated theme state — without launching the UI, and keeps ``TickrApp`` declarative.
@MainActor
struct AppDependencies {
    let apiKeyStore: APIKeyStore
    let themeStore: ThemeStore
    let favoritesStore: FavoritesStore
    let quoteProvider: QuoteProvider
    let candleProvider: CandleProvider
    let searchProvider: SymbolSearchProvider
    let mode: LaunchMode

    /// Build the dependency graph for `arguments` (the real process arguments by default).
    static func make(arguments: [String] = CommandLine.arguments) -> AppDependencies {
        switch LaunchMode(arguments: arguments) {
        case .production:
            return production()
        case .uiTesting:
            return uiTesting()
        }
    }

    /// The shipping graph: Keychain-backed key store, standard-defaults theme store,
    /// Application Support favorites, and providers that route between live Finnhub and
    /// the offline mocks based on the stored key. Identical to the pre-seam wiring.
    static func production() -> AppDependencies {
        let apiKeyStore = APIKeyStore()
        let favoritesStore = FavoritesStore(fileURL: productionFavoritesFileURL())
        let themeStore = ThemeStore()
        return AppDependencies(
            apiKeyStore: apiKeyStore,
            themeStore: themeStore,
            favoritesStore: favoritesStore,
            quoteProvider: ProviderFactory.quoteProvider(keyStore: apiKeyStore),
            candleProvider: ProviderFactory.candleProvider(keyStore: apiKeyStore),
            searchProvider: ProviderFactory.searchProvider(keyStore: apiKeyStore),
            mode: .production
        )
    }

    /// The deterministic UI-testing graph. Every dependency is isolated from production
    /// state and from the network:
    ///
    /// - the offline mocks are forced directly, regardless of any real Finnhub key, so no
    ///   request is ever made;
    /// - the key store is backed by an in-memory ``SecretStore`` — ``KeychainSecretStore``
    ///   is never constructed, read, written, or cleared;
    /// - favorites start empty at a fresh per-launch file below the temporary directory,
    ///   so the user's Application Support favorites are never touched;
    /// - the theme store reads and writes an isolated, empty defaults domain that starts on
    ///   `system` and never falls through to `UserDefaults.standard`.
    static func uiTesting() -> AppDependencies {
        // In-memory secrets only: never touch the Keychain under --ui-testing.
        let apiKeyStore = APIKeyStore(store: EphemeralSecretStore())
        let favoritesStore = FavoritesStore(fileURL: ephemeralFavoritesFileURL())
        let themeStore = makeIsolatedThemeStore()
        return AppDependencies(
            apiKeyStore: apiKeyStore,
            themeStore: themeStore,
            favoritesStore: favoritesStore,
            quoteProvider: MockQuoteProvider(),
            candleProvider: PreviewCandleProvider(),
            searchProvider: MockSymbolSearchProvider(),
            mode: .uiTesting
        )
    }

    /// The shipping favorites file under Application Support (temporary directory only as a
    /// last resort if Application Support can't be resolved). Unchanged from the original
    /// `TickrApp` wiring.
    private static func productionFavoritesFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("Tickr", isDirectory: true)
            .appendingPathComponent("favorites.json")
    }

    /// A fresh, empty favorites file below the temporary directory, unique per launch so a
    /// UI run never reads or mutates the user's real favorites.
    private static func ephemeralFavoritesFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("TickrUITesting", isDirectory: true)
            .appendingPathComponent("favorites-\(UUID().uuidString).json")
    }

    /// A ``ThemeStore`` over an isolated, empty defaults domain that starts on `system`.
    ///
    /// Fail-closed by contract: if the private suite can't be created we stop rather than
    /// fall through to `UserDefaults.standard`, so there is no path from --ui-testing to
    /// the user's real theme defaults.
    private static func makeIsolatedThemeStore() -> ThemeStore {
        let suiteName = "com.mmfac.tickr.ui-testing.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            preconditionFailure("Could not create an isolated UI-testing defaults suite")
        }
        // Start from a known-empty domain so the theme resolves to `system`.
        defaults.removePersistentDomain(forName: suiteName)
        return ThemeStore(defaults: defaults, storageKey: "selectedThemeID")
    }
}

/// In-memory ``SecretStore`` used only by the ``LaunchMode/uiTesting`` graph so a UI run
/// never constructs or touches ``KeychainSecretStore``. Starts empty and lives only for
/// the process lifetime.
final class EphemeralSecretStore: SecretStore {
    private var storage: [String: String] = [:]

    func secret(for account: String) throws -> String? {
        storage[account]
    }

    func setSecret(_ secret: String?, for account: String) throws {
        storage[account] = secret
    }
}
