import Foundation
import TickrCore

/// How the app was launched, derived solely from process arguments.
///
/// The only way to enter ``uiTesting`` is the exact argument ``uiTestingArgument``; any
/// other argument set — including none — is ``production``. Normal launches are therefore
/// behaviorally unchanged.
enum LaunchMode: Equatable {
    /// Normal launch: production storage, Keychain, standard defaults, live/mock routing.
    case production
    /// Deterministic UI-testing launch: forced mocks and fully isolated, empty test state.
    case uiTesting

    /// The exact, non-localized process argument that opts into UI-testing mode.
    static let uiTestingArgument = "--ui-testing"

    init(arguments: [String]) {
        self = arguments.contains(Self.uiTestingArgument) ? .uiTesting : .production
    }
}

/// The concrete dependency graph the app runs against, chosen up-front from a ``LaunchMode``.
///
/// Factoring launch-mode detection and dependency construction into this seam lets unit
/// tests exercise the exact selection — forced mocks, in-memory secret store, isolated
/// theme defaults, fresh empty favorites — without launching the UI. In ``uiTesting`` mode
/// the isolated dependencies are chosen *before* any production storage or service object
/// is constructed, so no Keychain, standard defaults, or Application Support access ever
/// occurs.
@MainActor
struct AppDependencies {
    let favoritesStore: FavoritesStore
    let apiKeyStore: APIKeyStore
    let themeStore: ThemeStore
    let quoteProvider: QuoteProvider
    let candleProvider: CandleProvider
    let searchProvider: SymbolSearchProvider

    // Exposed so unit tests can prove which isolated dependencies the graph selected
    // (e.g. that `--ui-testing` chose `EphemeralSecretStore`/`InMemoryThemeDefaults` and
    // never constructed the Keychain-backed store or read `UserDefaults.standard`).
    let secretStore: SecretStore
    let themeDefaults: ThemeDefaults
    let favoritesFileURL: URL

    static func make(launchMode: LaunchMode) -> AppDependencies {
        // Choose the storage/service seams from the mode BEFORE constructing anything, so
        // UI-testing never instantiates a production object as a side effect.
        let secretStore = makeSecretStore(for: launchMode)
        let themeDefaults = makeThemeDefaults(for: launchMode)
        let favoritesFileURL = favoritesURL(for: launchMode)

        let apiKeyStore = APIKeyStore(store: secretStore)
        let themeStore = ThemeStore(defaults: themeDefaults)
        let favoritesStore = FavoritesStore(fileURL: favoritesFileURL)

        let quoteProvider: QuoteProvider
        let candleProvider: CandleProvider
        let searchProvider: SymbolSearchProvider
        switch launchMode {
        case .uiTesting:
            // Force the offline mocks directly, regardless of any real Finnhub key, so the
            // smoke is deterministic and makes no network request.
            quoteProvider = MockQuoteProvider()
            candleProvider = PreviewCandleProvider()
            searchProvider = MockSymbolSearchProvider()
        case .production:
            // Normal wiring: providers route between live Finnhub/Yahoo and the mocks based
            // on the current key, re-checked per request (unchanged behavior).
            quoteProvider = ProviderFactory.quoteProvider(keyStore: apiKeyStore)
            candleProvider = ProviderFactory.candleProvider(keyStore: apiKeyStore)
            searchProvider = ProviderFactory.searchProvider(keyStore: apiKeyStore)
        }

        return AppDependencies(
            favoritesStore: favoritesStore,
            apiKeyStore: apiKeyStore,
            themeStore: themeStore,
            quoteProvider: quoteProvider,
            candleProvider: candleProvider,
            searchProvider: searchProvider,
            secretStore: secretStore,
            themeDefaults: themeDefaults,
            favoritesFileURL: favoritesFileURL
        )
    }

    /// The ``SecretStore`` for `mode`: an isolated in-memory store for UI testing, the
    /// Keychain-backed store for production. Constructing either is side-effect-free (no
    /// Keychain access happens until a secret is actually read/written).
    static func makeSecretStore(for mode: LaunchMode) -> SecretStore {
        switch mode {
        case .uiTesting: return EphemeralSecretStore()
        case .production: return KeychainSecretStore()
        }
    }

    /// The ``ThemeDefaults`` for `mode`: isolated in-memory storage for UI testing, real
    /// standard defaults for production. UI testing never returns `UserDefaults.standard`.
    static func makeThemeDefaults(for mode: LaunchMode) -> ThemeDefaults {
        switch mode {
        case .uiTesting: return InMemoryThemeDefaults()
        case .production: return UserDefaults.standard
        }
    }

    /// Where favorites persist for `mode`. UI testing points at a fresh, per-launch
    /// location under the temporary directory (starting empty and never mutating the
    /// user's Application Support favorites); production uses Application Support.
    static func favoritesURL(for mode: LaunchMode) -> URL {
        switch mode {
        case .uiTesting:
            return FileManager.default.temporaryDirectory
                .appendingPathComponent("TickrUITests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
                .appendingPathComponent("favorites.json")
        case .production:
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            return base
                .appendingPathComponent("Tickr", isDirectory: true)
                .appendingPathComponent("favorites.json")
        }
    }
}
