import SwiftUI
import TickrCore

@main
struct TickrApp: App {
    @State private var sidebar: SidebarViewModel
    @State private var search: SymbolSearchViewModel
    @State private var selection: SidebarViewModel.Row.ID?
    @State private var themeStore: ThemeStore
    @State private var apiKeyStore: APIKeyStore

    // Routing providers switch between live Finnhub and the offline mocks based on the
    // key in `apiKeyStore`, re-checked per request so entering a key in Settings takes
    // effect immediately (no restart).
    private let quoteProvider: QuoteProvider
    private let candleProvider: CandleProvider

    init() {
        // Choose the whole dependency graph before any store or provider is built, so a
        // `--ui-testing` launch is fully isolated and a normal launch is unchanged.
        let deps = AppDependencies.make()
        _themeStore = State(initialValue: deps.themeStore)
        _apiKeyStore = State(initialValue: deps.apiKeyStore)

        self.quoteProvider = deps.quoteProvider
        self.candleProvider = deps.candleProvider
        // One favorites store, shared by the sidebar and search so adding a result updates both.
        _sidebar = State(initialValue: SidebarViewModel(store: deps.favoritesStore, provider: deps.quoteProvider))
        _search = State(initialValue: SymbolSearchViewModel(
            provider: deps.searchProvider,
            store: deps.favoritesStore
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
                    // Identify the always-present tab button (built from the tabItem label)
                    // rather than the tab's content, which is only in the tree once selected.
                    .tabItem {
                        Label("Appearance", systemImage: "paintbrush")
                            .accessibilityIdentifier("settings.appearanceTab")
                    }
            }
        }
    }
}
