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
    // key in `apiKeyStore` (or are forced mocks under `--ui-testing`), re-checked per
    // request so entering a key in Settings takes effect immediately (no restart).
    private let quoteProvider: QuoteProvider
    private let candleProvider: CandleProvider

    init() {
        // Chooses the whole dependency graph — production or the deterministic
        // `--ui-testing` mode — before any production storage/service object exists.
        let dependencies = AppDependencies()

        _apiKeyStore = State(initialValue: dependencies.apiKeyStore)
        _themeStore = State(initialValue: dependencies.themeStore)

        self.quoteProvider = dependencies.quoteProvider
        self.candleProvider = dependencies.candleProvider
        // One store, shared by the sidebar and search so adding a result updates both.
        _sidebar = State(initialValue: SidebarViewModel(store: dependencies.favoritesStore, provider: quoteProvider))
        _search = State(initialValue: SymbolSearchViewModel(
            provider: dependencies.searchProvider,
            store: dependencies.favoritesStore
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
            // The Settings TabView renders its tabs as one native NSSegmentedControl;
            // this tags the real Appearance segment's exposed AXRadioButton element (see
            // AccessibilityBridge for why a plain SwiftUI identifier can't do this).
            .background(SegmentedTabAccessibilityTag(
                identifier: "settings.appearanceTab",
                segmentIndex: 1,
                segmentCount: 2
            ))
        }
    }
}
