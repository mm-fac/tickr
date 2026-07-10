import SwiftUI
import TickrCore

@main
struct TickrApp: App {
    @State private var sidebar: SidebarViewModel
    @State private var search: SymbolSearchViewModel
    @State private var settings: SettingsModel
    @State private var selection: SidebarViewModel.Row.ID?

    /// The shared, swappable providers. All views fetch through this hub; ``settings``
    /// swaps its backing set (live Finnhub vs. offline mocks) when the API key changes,
    /// so the change takes effect without an app restart.
    private let hub: ProviderHub

    init() {
        // One store, shared by the sidebar and search so adding a result updates both.
        let store = FavoritesStore(fileURL: Self.favoritesFileURL())

        // Offline stand-ins used until a Finnhub API key is configured in Settings.
        let mock = ProviderSet(
            quote: MockQuoteProvider(),
            candle: PreviewCandleProvider(),
            search: MockSymbolSearchProvider(),
            isLive: false
        )

        // Resolve the initial providers from any key already in the Keychain, then hand
        // every view model the same hub so a later key change re-wires them all at once.
        let keyStore = KeychainAPIKeyStore()
        let initialKey = try? keyStore.read()
        let initialSet = ProviderSelector.resolve(apiKey: initialKey ?? nil, mock: mock)
        let hub = ProviderHub(providers: initialSet)
        self.hub = hub

        let sidebarModel = SidebarViewModel(store: store, provider: hub)
        _sidebar = State(initialValue: sidebarModel)
        _search = State(initialValue: SymbolSearchViewModel(provider: hub, store: store))

        let settingsModel = SettingsModel(store: keyStore, hub: hub, mock: mock)
        // Reload the sidebar's quotes whenever the providers change so a new key's live
        // data (or a cleared key's sample data) shows without waiting for a restart.
        settingsModel.onProvidersChanged = { [weak sidebarModel] in
            await sidebarModel?.refresh()
        }
        _settings = State(initialValue: settingsModel)
    }

    var body: some Scene {
        WindowGroup {
            NavigationSplitView {
                SidebarView(model: sidebar, search: search, settings: settings, selection: $selection)
            } detail: {
                if let symbol = selection {
                    DetailView(model: DetailViewModel(
                        symbol: symbol,
                        quoteProvider: hub,
                        candleProvider: hub
                    ))
                    // Rebuild the detail (and its view model) when the selection changes,
                    // or when the live/sample wiring flips, so the chart reloads through
                    // the newly selected providers.
                    .id("\(symbol)-\(settings.isLive)")
                } else {
                    DetailPlaceholderView()
                }
            }
            .frame(minWidth: 640, minHeight: 420)
        }
        .defaultSize(width: 900, height: 600)

        Settings {
            SettingsView(model: settings)
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
