import Foundation
import TickrCore

/// How the app was launched, decided solely from the process arguments.
///
/// The deterministic XCUITest smoke opts in with the single exact argument `--ui-testing`;
/// every other launch (including any other argument) stays ``production`` and behaves
/// exactly as it always has. Isolated here as a tiny value type so unit tests can prove the
/// exact opt-in without launching the UI.
enum LaunchMode: Equatable {
    /// Normal launch: real Keychain, standard defaults, Application Support favorites, and
    /// the key-routed live/mock providers.
    case production
    /// Deterministic UI-testing launch: forced offline mocks and fully isolated, per-launch
    /// temporary state. Never touches production storage or system services.
    case uiTesting

    /// The exact process argument that opts into UI-testing isolation. Only this exact
    /// token counts — no prefix, suffix, or case variation enables it.
    static let uiTestingArgument = "--ui-testing"

    init(arguments: [String]) {
        self = arguments.contains(Self.uiTestingArgument) ? .uiTesting : .production
    }
}

/// The concrete dependency graph the app runs against, chosen entirely from the
/// ``LaunchMode`` *before* any storage or service object is constructed.
///
/// This is the app-target seam the issue calls for: ``TickrApp`` asks ``make(mode:)`` for a
/// fully wired graph, and unit tests exercise the same factory without launching the UI.
/// In ``LaunchMode/uiTesting`` the factory constructs only isolated, offline objects — the
/// production branch (Keychain, standard defaults, Application Support) is never entered —
/// so tests can build and inspect the UI-testing graph without touching any real system
/// state.
@MainActor
struct AppDependencies {
    let favoritesStore: FavoritesStore
    let apiKeyStore: APIKeyStore
    let themeStore: ThemeStore
    let quoteProvider: QuoteProvider
    let candleProvider: CandleProvider
    let searchProvider: SymbolSearchProvider

    /// The secret store backing ``apiKeyStore``, retained so tests can prove a UI-testing
    /// launch selected an in-memory ``EphemeralSecretStore`` and never constructed
    /// ``KeychainSecretStore``.
    let secretStore: SecretStore
    /// Where favorites persist, exposed so tests can prove a UI-testing launch points at a
    /// fresh temporary location rather than production Application Support.
    let favoritesURL: URL

    static func make(mode: LaunchMode) -> AppDependencies {
        switch mode {
        case .production:
            return makeProduction()
        case .uiTesting:
            return makeUITesting()
        }
    }

    /// Normal launch wiring — identical in behavior to the app's original `init`: real
    /// Keychain-backed key store, standard theme defaults, Application Support favorites,
    /// and the providers that route between live Finnhub/Yahoo and the offline mocks based
    /// on the stored key.
    private static func makeProduction() -> AppDependencies {
        let favoritesURL = productionFavoritesURL()
        let favoritesStore = FavoritesStore(fileURL: favoritesURL)
        let secretStore = KeychainSecretStore()
        let apiKeyStore = APIKeyStore(store: secretStore)
        let themeStore = ThemeStore()

        return AppDependencies(
            favoritesStore: favoritesStore,
            apiKeyStore: apiKeyStore,
            themeStore: themeStore,
            quoteProvider: ProviderFactory.quoteProvider(keyStore: apiKeyStore),
            candleProvider: ProviderFactory.candleProvider(keyStore: apiKeyStore),
            searchProvider: ProviderFactory.searchProvider(keyStore: apiKeyStore),
            secretStore: secretStore,
            favoritesURL: favoritesURL
        )
    }

    /// Deterministic UI-testing wiring. Forces the offline mocks regardless of any real
    /// key, injects an in-memory secret store (no Keychain), points favorites at a fresh
    /// per-launch temporary file (starts empty), and gives the theme store isolated
    /// in-memory persistence that starts at `system`. Writes only isolated temporary/test
    /// state and makes no network request.
    private static func makeUITesting() -> AppDependencies {
        let favoritesURL = uiTestingFavoritesURL()
        let favoritesStore = FavoritesStore(fileURL: favoritesURL)
        let secretStore = EphemeralSecretStore()
        let apiKeyStore = APIKeyStore(store: secretStore)
        let themeStore = ThemeStore(defaults: InMemoryThemeDefaults())

        return AppDependencies(
            favoritesStore: favoritesStore,
            apiKeyStore: apiKeyStore,
            themeStore: themeStore,
            quoteProvider: MockQuoteProvider(),
            candleProvider: PreviewCandleProvider(),
            searchProvider: MockSymbolSearchProvider(),
            secretStore: secretStore,
            favoritesURL: favoritesURL
        )
    }

    /// Production favorites location under Application Support (falling back to the temp
    /// directory only if Application Support is somehow unavailable). Matches the app's
    /// original path so normal launches keep reading the user's existing favorites.
    private static func productionFavoritesURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("Tickr", isDirectory: true)
            .appendingPathComponent("favorites.json")
    }

    /// A fresh, per-launch favorites file below the temporary directory, so a UI-testing
    /// launch always starts with an empty favorites list and never reads, writes, or
    /// clears the user's real Application Support favorites.
    private static func uiTestingFavoritesURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("TickrUITests", isDirectory: true)
            .appendingPathComponent("favorites-\(UUID().uuidString).json")
    }
}
