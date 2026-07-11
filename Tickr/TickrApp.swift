import SwiftUI
import TickrCore

@main
struct TickrApp: App {
    @State private var sidebar: SidebarViewModel
    @State private var search: SymbolSearchViewModel
    @State private var selection: SidebarViewModel.Row.ID?
    @State private var themeStore: ThemeStore
    @State private var apiKeyStore: APIKeyStore

    // The active providers for the sidebar/detail. In a normal launch these route between
    // live Finnhub/Yahoo and the offline mocks based on the key in `apiKeyStore`; in a
    // `--ui-testing` launch they are the forced offline mocks (see `AppDependencies`).
    private let quoteProvider: QuoteProvider
    private let candleProvider: CandleProvider

    init() {
        // Choose the whole dependency graph up front from the launch mode, before any
        // storage or service object is constructed. A normal launch is behaviorally
        // unchanged; only the exact `--ui-testing` argument selects the isolated, offline
        // graph. One favorites store is shared by the sidebar and search so adding a result
        // updates both.
        let deps = AppDependencies.make(mode: LaunchMode(arguments: CommandLine.arguments))
        _apiKeyStore = State(initialValue: deps.apiKeyStore)
        _themeStore = State(initialValue: deps.themeStore)

        self.quoteProvider = deps.quoteProvider
        self.candleProvider = deps.candleProvider
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
                    .tabItem {
                        Label("Data", systemImage: "key")
                            .accessibilityIdentifier("settings.dataTab")
                    }
                ThemeSettingsView(store: themeStore)
                    .tabItem {
                        Label("Appearance", systemImage: "paintbrush")
                            .accessibilityIdentifier("settings.appearanceTab")
                    }
            }
        }
    }
}
