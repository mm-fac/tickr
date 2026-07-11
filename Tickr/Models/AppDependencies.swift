import Foundation
import TickrCore

/// Whether the app should launch in the deterministic UI-testing mode: forced mock
/// providers, an in-memory secret store, and isolated favorites/theme persistence,
/// instead of the normal production wiring. Gated behind the exact `--ui-testing`
/// process argument (a whole argument match, never a prefix/suffix/substring) so a
/// normal launch is unaffected.
///
/// Kept separate from ``AppDependencies`` so a unit test can exercise mode detection
/// without constructing anything: `TickrUITests` cannot run under `swift test` or the
/// app-target unit-test host, so this is the seam those unit tests exercise instead.
enum AppLaunchMode: Equatable {
    case production
    case uiTesting

    /// The exact opt-in flag. Must equal a whole launch argument.
    static let uiTestingArgument = "--ui-testing"

    init(arguments: [String]) {
        self = arguments.contains(Self.uiTestingArgument) ? .uiTesting : .production
    }
}

/// Builds every top-level dependency ``TickrApp`` needs, choosing the whole graph up
/// front — before any production storage or service object is constructed — based on
/// ``AppLaunchMode``.
///
/// - `.production` is the app's normal wiring, unchanged: Application Support favorites,
///   `UserDefaults.standard`-backed theme, and a Keychain-backed API key feeding the
///   existing live/mock ``ProviderFactory`` routing.
/// - `.uiTesting` forces the offline mock providers, an in-memory ``EphemeralSecretStore``
///   (the Keychain is never constructed, read, written, or cleared), a fresh per-launch
///   favorites file below the temporary directory (so favorites always start empty), and
///   a freshly created, isolated `UserDefaults` suite for the theme (so it always starts
///   at `system` and `UserDefaults.standard` is never read or written). Suite creation is
///   fail-closed: if it cannot be created there is no fallback to `.standard`, only a
///   crash (issue #37 retry evidence: a prior draft's `?? .standard` fallback was
///   rejected as an isolation violation).
@MainActor
struct AppDependencies {
    let favoritesStore: FavoritesStore
    let secretStore: SecretStore
    let apiKeyStore: APIKeyStore
    let themeStore: ThemeStore
    let quoteProvider: QuoteProvider
    let candleProvider: CandleProvider
    let searchProvider: SymbolSearchProvider

    init(
        arguments: [String] = CommandLine.arguments,
        temporaryDirectory: URL = FileManager.default.temporaryDirectory
    ) {
        self.init(mode: AppLaunchMode(arguments: arguments), temporaryDirectory: temporaryDirectory)
    }

    init(mode: AppLaunchMode, temporaryDirectory: URL = FileManager.default.temporaryDirectory) {
        switch mode {
        case .uiTesting:
            let favorites = FavoritesStore(fileURL: Self.uiTestingFavoritesURL(temporaryDirectory: temporaryDirectory))
            let secrets = EphemeralSecretStore()
            let apiKeys = APIKeyStore(store: secrets)

            self.favoritesStore = favorites
            self.secretStore = secrets
            self.apiKeyStore = apiKeys
            self.themeStore = ThemeStore(defaults: Self.uiTestingThemeDefaults())
            self.quoteProvider = MockQuoteProvider()
            self.candleProvider = PreviewCandleProvider()
            self.searchProvider = MockSymbolSearchProvider()

        case .production:
            let favorites = FavoritesStore(fileURL: Self.productionFavoritesURL())
            let secrets = KeychainSecretStore()
            let apiKeys = APIKeyStore(store: secrets)

            self.favoritesStore = favorites
            self.secretStore = secrets
            self.apiKeyStore = apiKeys
            self.themeStore = ThemeStore()
            self.quoteProvider = ProviderFactory.quoteProvider(keyStore: apiKeys)
            self.candleProvider = ProviderFactory.candleProvider(keyStore: apiKeys)
            self.searchProvider = ProviderFactory.searchProvider(keyStore: apiKeys)
        }
    }

    private static func productionFavoritesURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("Tickr", isDirectory: true)
            .appendingPathComponent("favorites.json")
    }

    /// A fresh, never-before-used path below `temporaryDirectory` so favorites always
    /// start empty and one launch's state can never bleed into another's.
    static func uiTestingFavoritesURL(temporaryDirectory: URL) -> URL {
        temporaryDirectory
            .appendingPathComponent("TickrUITesting", isDirectory: true)
            .appendingPathComponent("favorites-\(UUID().uuidString).json")
    }

    /// A freshly created, isolated `UserDefaults` suite for the UI-testing theme store.
    static func uiTestingThemeDefaults() -> UserDefaults {
        let suiteName = "io.tickr.ui-testing.theme.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("AppDependencies: could not create an isolated UserDefaults suite for --ui-testing; refusing to fall back to UserDefaults.standard")
        }
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
