import SwiftUI
import TickrCore

@main
struct TickrApp: App {
    @State private var sidebar: SidebarViewModel
    @State private var search: SymbolSearchViewModel
    @State private var selection: SidebarViewModel.Row.ID?
    @State private var themeStore = ThemeStore()
    @State private var apiKeyStore: APIKeyStore

    // Routing providers switch between live Finnhub and the offline mocks based on the
    // key in `apiKeyStore`, re-checked per request so entering a key in Settings takes
    // effect immediately (no restart).
    private let quoteProvider: QuoteProvider
    private let candleProvider: CandleProvider

    init() {
        // One store, shared by the sidebar and search so adding a result updates both.
        let store = FavoritesStore(fileURL: Self.favoritesFileURL())
        let apiKeyStore = APIKeyStore()
        _apiKeyStore = State(initialValue: apiKeyStore)

        self.quoteProvider = ProviderFactory.quoteProvider(keyStore: apiKeyStore)
        self.candleProvider = ProviderFactory.candleProvider(keyStore: apiKeyStore)
        _sidebar = State(initialValue: SidebarViewModel(store: store, provider: quoteProvider))
        _search = State(initialValue: SymbolSearchViewModel(
            provider: ProviderFactory.searchProvider(keyStore: apiKeyStore),
            store: store
        ))
    }

    var body: some Scene {
        WindowGroup {
            NavigationSplitView {
                SidebarView(model: sidebar, search: search, selection: $selection)
            } detail: {
                if let symbol = selection {
                    DetailView(model: DetailViewModel(
                        symbol: symbol,
                        quoteProvider: quoteProvider,
                        candleProvider: candleProvider
                    ))
                    // Rebuild the detail (and its view model) when the selection changes.
                    .id(symbol)
                } else {
                    DetailPlaceholderView()
                }
            }
            .frame(minWidth: 640, minHeight: 420)
            // A single selection recolors the whole tree: inject the active theme and
            // drive the app-wide accent from it.
            .environment(\.theme, themeStore.selected)
            .tint(themeStore.selected.accent)
        }
        .defaultSize(width: 900, height: 600)

        Settings {
            TabView {
                APIKeySettingsView(store: apiKeyStore)
                    .tabItem { Label("Data", systemImage: "key") }
                ThemeSettingsView(store: themeStore)
                    .tabItem { Label("Appearance", systemImage: "paintbrush") }
            }
        }
    }

    private static func favoritesFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("Tickr", isDirectory: true)
            .appendingPathComponent("favorites.json")
    }
}
